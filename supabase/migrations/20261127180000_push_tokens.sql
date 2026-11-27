-- #30: powiadomienia push o ataku (FCM), ADR 0012.
--
-- `public.push_tokens` trzyma tokeny FCM urządzeń gracza (najwyżej 5 na konto) i przełącznik
-- „Ataki” każdego urządzenia. Tabela jest wyłącznie dla serwera: klient nie ma do niej żadnych
-- uprawnień (nie czyta ani swojego, ani cudzego tokenu). Token zapisuje i usuwa Edge Function
-- `push_token` z id gracza z jego tokenu JWT, przez `push_token_register` / `push_token_unregister`
-- (tylko service_role). Token jest identyfikatorem urządzenia, więc nie trafia do logów, a wiersze
-- znikają razem z kontem (on delete cascade).
--
-- Push o ataku wysyła `finish_attack` po zapisaniu wyniku. `attack_push_claim` jednorazowo oznacza
-- atak jako powiadomiony (`attacks.push_sent_at`) i oddaje tokeny obrońcy z włączonym przełącznikiem
-- oraz wynik, więc ponowione `finish_attack` nie wyśle drugiego pusha. Atak w weryfikacji (tryb
-- enforce, bez `outcome_applied_at`) nie dostaje pusha. Token, który FCM odrzuci, usuwa `push_token_drop`.

create table public.push_tokens (
  player_id uuid not null references public.players (id) on delete cascade,
  -- token rejestracji FCM: znaki base64url i dwukropek, długość z zapasem
  token text not null check (char_length(token) between 20 and 512 and token ~ '^[A-Za-z0-9_:-]+$'),
  -- przełącznik „Ataki” na tym urządzeniu
  attacks boolean not null default true,
  updated_at timestamptz not null default now(),
  primary key (player_id, token)
);
comment on table public.push_tokens is
  'Tokeny FCM urządzeń gracza (#30, ADR 0012), najwyżej 5. Tylko serwer (Edge Functions push_token i finish_attack).';
create unique index push_tokens_token on public.push_tokens (token);

alter table public.push_tokens enable row level security;
revoke all on public.push_tokens from public, anon, authenticated;
grant select, insert, update, delete on public.push_tokens to service_role;
-- service_role omija RLS; klient nie ma grantów, a polityka i tak wpuszcza tylko właściciela
create policy "push_tokens: tylko własne" on public.push_tokens
  for all to authenticated
  using ((select auth.uid()) = player_id)
  with check ((select auth.uid()) = player_id);

-- jednorazowy znacznik pusha o ataku; bez grantu kolumny dla authenticated
alter table public.attacks add column push_sent_at timestamptz;
comment on column public.attacks.push_sent_at is 'Kiedy serwer wysłał push o tym ataku do obrońcy (#30); null = jeszcze nie.';

-- Zapis tokenu urządzenia. Ten sam token u innego gracza (to samo urządzenie po zmianie konta)
-- przechodzi na wołającego, żeby push o cudzym ataku nie trafiał na telefon. Tokeny nieodświeżane
-- od 60 dni wypadają, a nad limit 5 wypadają najstarsze.
create function public.push_token_register(p_player uuid, p_token text, p_attacks boolean)
returns void
language plpgsql
volatile
security invoker
set search_path = ''
as $$
begin
  if p_player is null or p_token is null or p_attacks is null
      or char_length(p_token) not between 20 and 512 or p_token !~ '^[A-Za-z0-9_:-]+$' then
    raise exception 'bad_token' using errcode = 'P0001';
  end if;
  delete from public.push_tokens t where t.token = p_token and t.player_id <> p_player;
  insert into public.push_tokens as t (player_id, token, attacks, updated_at)
  values (p_player, p_token, p_attacks, now())
  on conflict (player_id, token) do update set attacks = excluded.attacks, updated_at = excluded.updated_at;
  delete from public.push_tokens t where t.player_id = p_player and t.updated_at < now() - interval '60 days';
  -- MAX_TOKENS = 5
  delete from public.push_tokens t
  where t.player_id = p_player
    and t.token not in (
      select k.token from public.push_tokens k where k.player_id = p_player
      order by k.updated_at desc, k.token limit 5);
end;
$$;
comment on function public.push_token_register(uuid, text, boolean) is
  'Zapis tokenu FCM urządzenia gracza i przełącznika Ataki (#30). Tylko service_role (Edge Function push_token).';
revoke all on function public.push_token_register(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.push_token_register(uuid, text, boolean) to service_role;

-- Usunięcie tokenu przez gracza (wyłączenie powiadomień na urządzeniu): tylko jego własny wiersz.
create function public.push_token_unregister(p_player uuid, p_token text)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  delete from public.push_tokens t where t.player_id = p_player and t.token = p_token
$$;
comment on function public.push_token_unregister(uuid, text) is
  'Usunięcie własnego tokenu FCM (#30). Tylko service_role (Edge Function push_token).';
revoke all on function public.push_token_unregister(uuid, text) from public, anon, authenticated;
grant execute on function public.push_token_unregister(uuid, text) to service_role;

-- Token odrzucony przez FCM (UNREGISTERED, zły token): usuwa serwer po próbie wysyłki.
create function public.push_token_drop(p_token text)
returns void
language sql
volatile
security invoker
set search_path = ''
as $$
  delete from public.push_tokens t where t.token = p_token
$$;
comment on function public.push_token_drop(text) is
  'Usunięcie tokenu odrzuconego przez FCM (#30). Tylko service_role (finish_attack).';
revoke all on function public.push_token_drop(text) from public, anon, authenticated;
grant execute on function public.push_token_drop(text) to service_role;

-- Jednorazowe pobranie odbiorców pusha o ataku. Oznacza atak jako powiadomiony tylko wtedy, gdy
-- to zakończony atak na gracza ze skutkami (outcome_applied_at), wołany przez jego atakującego.
-- Drugie wywołanie nic nie zwraca. Oddaje tokeny obrońcy z włączonymi Atakami, wynik ataku
-- (`won` z perspektywy atakującego) i procent zniszczeń.
create function public.attack_push_claim(p_attacker uuid, p_attack uuid)
returns table (token text, won boolean, percent integer)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  a public.attacks%rowtype;
begin
  update public.attacks t set push_sent_at = now()
  where t.id = p_attack and t.attacker_id = p_attacker and t.defender_id is not null
    and t.status = 'finished' and t.outcome_applied_at is not null and t.push_sent_at is null
  returning * into a;
  if not found then
    return;
  end if;
  return query
    select k.token, coalesce((a.result ->> 'won')::boolean, false),
      least(greatest(coalesce((a.result ->> 'percent')::integer, 0), 0), 100)
    from public.push_tokens k
    where k.player_id = a.defender_id and k.attacks
    order by k.updated_at desc, k.token;
end;
$$;
comment on function public.attack_push_claim(uuid, uuid) is
  'Jednorazowo: tokeny FCM obrońcy i wynik zakończonego ataku do pusha (#30). Tylko service_role (finish_attack).';
revoke all on function public.attack_push_claim(uuid, uuid) from public, anon, authenticated;
grant execute on function public.attack_push_claim(uuid, uuid) to service_role;
