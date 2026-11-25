-- Weryfikacja ataków PvP na serwerze (#284, #304): kolejka jobów dla workera Godot headless na VPS.
--
-- Przepływ:
--   finish_attack → public.end_attack: zapisuje wynik zgłoszony przez telefon (`claimed_result`), ustawia
--     `verification = 'pending'` i wkłada atak do kolejki `private.attack_verifications`.
--   worker (rola `verifier`) → private.claim_verification: bierze jeden job (FOR UPDATE SKIP LOCKED, lease
--     5 minut, najwyżej 3 próby) w kształcie odpowiedzi `attack_replay` z `sim_version`.
--   worker → private.submit_verification: wynik przeliczony przez ten sam GDScript (VerifyJob, #303).
--     Serwer sprawdza kształt, zapisuje `verified_result`, porównuje z `claimed_result` (wygrana, procent,
--     gwiazdki, ocaleli i zgłoszone ruiny: `verified` albo `mismatch`) i woła private.apply_attack_outcome.
--   private.apply_attack_outcome: łup, ranking, tarcza i ruiny liczone wyłącznie z `verified_result`.
--     Idempotentna: skutki ataku wchodzą raz (`attacks.outcome_applied_at`).
--
-- Tryb (`private.settings`, klucz `verification_mode`, §7 #284):
--   'off'     – jak przed tą migracją, bez kolejki;
--   'shadow'  – (domyślny) end_attack daje skutki od razu z wyniku telefonu, worker tylko liczy i oznacza
--               `verified`/`mismatch`. Cel: zero niezgodności u uczciwych klientów;
--   'enforce' – end_attack nie daje żadnych skutków; łup, ranking, tarcza i ruiny dopiero z wyniku workera.
--               Wymaga Edge Function i klienta, które rozumieją status 'verifying' (§6 #284).
-- Powrót do 'shadow' to jeden update, bez wydania klienta:
--   update private.settings set value = 'shadow' where key = 'verification_mode';
--
-- Rola `verifier` powstaje tu jako NOLOGIN, bez hasła. LOGIN i hasło ustawia właścicielka ręcznie na projekcie
-- (nigdy w repo, PR ani w logach). Ma tylko USAGE na schemacie private i EXECUTE na claim/submit: żadnych
-- uprawnień do tabel i żadnego service_role.

-- ---- ustawienia i wspierane wersje symulacji ----

create table private.settings (
  key text primary key,
  value text not null,
  constraint settings_verification_mode check (key <> 'verification_mode' or value in ('off', 'shadow', 'enforce'))
);
comment on table private.settings is 'Przełączniki serwera ustawiane ręcznie przez właścicielkę (np. verification_mode, #284).';
alter table private.settings enable row level security;
revoke all on private.settings from public, anon, authenticated, service_role;
insert into private.settings (key, value) values ('verification_mode', 'shadow');

-- sim_version = kod wersji gry (tools/version.py: MAJOR*10000 + MINOR*100 + PATCH, VerifyJob.project_sim_version).
-- Worker liczy job packiem `verify_<sim_version>.pck`; wersja bez packa nie startuje ataku.
create table private.sim_versions (
  version integer primary key check (version > 0),
  supported boolean not null default true,
  added_at timestamptz not null default now()
);
comment on table private.sim_versions is 'Wersje symulacji z packiem na workerze weryfikacji (#284 §2). Nowe wydanie: insert przed wypuszczeniem klienta.';
alter table private.sim_versions enable row level security;
revoke all on private.sim_versions from public, anon, authenticated, service_role;
-- 0.5.1
insert into private.sim_versions (version) values (501);

create function private.verification_mode()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select s.value from private.settings s where s.key = 'verification_mode'), 'off');
$$;
comment on function private.verification_mode() is 'Tryb weryfikacji ataków PvP: off, shadow albo enforce (#284 §7).';
revoke all on function private.verification_mode() from public, anon, authenticated;
grant execute on function private.verification_mode() to service_role;

-- Wersja symulacji ataku: podana przez klienta musi być wspierana, brak (starszy klient albo Edge Function)
-- oznacza najnowszą wspieraną. Null tylko wtedy, gdy tabela jest pusta.
create function private.checked_sim_version(p_version integer)
returns integer
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_version is null then
    return (select max(v.version) from private.sim_versions v where v.supported);
  end if;
  if not exists (select 1 from private.sim_versions v where v.version = p_version and v.supported) then
    raise exception 'unsupported_version' using errcode = 'P0001';
  end if;
  return p_version;
end;
$$;
revoke all on function private.checked_sim_version(integer) from public, anon, authenticated;
grant execute on function private.checked_sim_version(integer) to service_role;

-- ---- kolumny weryfikacji na attacks ----

alter table public.attacks
  add column sim_version integer check (sim_version is null or sim_version > 0),
  -- wynik z telefonu: {won, percent, stars, loot, survivors[, destroyed_ids]}; tylko do porównania
  add column claimed_result jsonb check (claimed_result is null or jsonb_typeof(claimed_result) = 'object'),
  add column verification text check (verification in ('pending', 'verified', 'mismatch', 'failed')),
  -- wynik workera: {won, percent, stars, destroyed_ids, survivors, ticks, checksum, sim_version}
  add column verified_result jsonb check (verified_result is null or jsonb_typeof(verified_result) = 'object'),
  add column verified_at timestamptz,
  -- kiedy weszły skutki ataku (łup, ranking, tarcza); null przy ataku w weryfikacji w trybie enforce
  add column outcome_applied_at timestamptz;

comment on column public.attacks.claimed_result is 'Wynik zgłoszony przez telefon atakującego (#284). Nie daje skutków w trybie enforce.';
comment on column public.attacks.verified_result is 'Wynik przeliczony przez worker weryfikacji (#284). Źródło skutków ataku w trybie enforce.';
comment on column public.attacks.outcome_applied_at is 'Skutki ataku (łup, ranking, tarcza, ruiny) już weszły (#284); apply_attack_outcome działa raz.';

-- Ranking PvP liczy się, gdy wchodzą skutki ataku, a nie przy samym zgłoszeniu wyniku. Stary wyzwalacz znika
-- przed uzupełnieniem kolumny, żeby uzupełnienie nie zmieniło rankingu drugi raz.
drop trigger attacks_pvp_rating on public.attacks;
update public.attacks t set outcome_applied_at = t.finished_at where t.status = 'finished';

create trigger attacks_pvp_rating
  after update of status, outcome_applied_at on public.attacks
  for each row
  when (new.defender_id is not null and (
    (old.status = 'started' and new.status = 'abandoned')
    or (old.outcome_applied_at is null and new.outcome_applied_at is not null and new.status = 'finished')))
  execute function private.apply_pvp_rating();

-- obrońcy z atakiem w weryfikacji (enforce) są zablokowani w begin_attack i match_targets
create index attacks_defender_awaiting_idx on public.attacks (defender_id)
  where verification = 'pending' and outcome_applied_at is null;

-- ---- kolejka ----

create table private.attack_verifications (
  attack_id uuid primary key references public.attacks (id) on delete cascade,
  attempts smallint not null default 0 check (attempts >= 0),
  leased_until timestamptz,
  -- identyfikator workera z WORKER_ID (np. worker-1), bez danych gracza
  leased_by text check (leased_by is null or char_length(leased_by) <= 64),
  -- tylko kod błędu (np. bad_result, lease_expired), nigdy treść jobu ani dane gracza
  last_error text check (last_error is null or last_error ~ '^[a-z_]{1,32}$'),
  -- finish_attack woła record_destroyed zaraz po end_attack: job czeka na zgłoszone ruiny (albo 15 s, gdy
  -- klient ich nie wysyła), żeby porównanie nie przegapiło różnicy w ruinach
  not_before timestamptz not null default now() + interval '15 seconds',
  created_at timestamptz not null default now()
);
comment on table private.attack_verifications is 'Kolejka weryfikacji ataków PvP (#284): czyta i pisze tylko claim/submit/apply w schemacie private.';
create index attack_verifications_lease_idx on private.attack_verifications (leased_until, created_at);
alter table private.attack_verifications enable row level security;
revoke all on private.attack_verifications from public, anon, authenticated, service_role;

-- Wkłada atak do kolejki (wołane z end_attack, które działa jako service_role bez uprawnień do kolejki).
create function private.enqueue_verification(p_attack uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  insert into private.attack_verifications (attack_id) values (p_attack) on conflict (attack_id) do nothing;
$$;
revoke all on function private.enqueue_verification(uuid) from public, anon, authenticated;
grant execute on function private.enqueue_verification(uuid) to service_role;

-- Job gotowy od razu (wołane z record_destroyed, gdy ruiny z telefonu już są w claimed_result).
create function private.verification_ready(p_attack uuid)
returns void
language sql
volatile
security definer
set search_path = ''
as $$
  update private.attack_verifications v set not_before = now()
  where v.attack_id = p_attack and v.not_before > now();
$$;
revoke all on function private.verification_ready(uuid) from public, anon, authenticated;
grant execute on function private.verification_ready(uuid) to service_role;

-- ---- łup z wyniku (port BattleResult / PlayerCastle.result_of) ----

-- Łup ataku na gracza: niechroniona część kopii zapasów obrońcy (PROTECTED_PERCENT = 50) × LOOT_PERCENT = 20
-- × procent łupu (wygrana: co najmniej WIN_LOOT_PERCENT = 50, przegrana 0), Łupieżca +15 % (#32), a potem
-- przycięcie do capacity ocalałych (limit_to_capacity: każdy surowiec w tej samej proporcji, w dół).
-- Dzielenie całkowite w tej samej kolejności co w GDScript.
create function private.attack_loot(a public.attacks, p_won boolean, p_percent bigint, p_survivors jsonb)
returns integer[]
language plpgsql
stable
set search_path = ''
as $$
declare
  v_loot bigint[] := array[0, 0, 0, 0];
  v_pct bigint := case when p_won then greatest(p_percent, 50) else 0 end;
  v_capacity bigint := 0;
  v_total bigint := 0;
  v_stash bigint;
  v_squad jsonb;
  v_alive bigint;
begin
  if a.defender_id is null then
    raise exception 'not_pvp' using errcode = 'P0001';
  end if;
  for i in 0 .. 3 loop
    v_stash := coalesce(private.json_int(a.castle_snapshot -> 'economy' -> 'amounts' -> i, 0, 10000000), 0);
    v_loot[i + 1] := v_stash * (100 - 50) / 100 * 20 / 100 * v_pct / 100;
    if a.attacker_ruler_perk = 1 then
      v_loot[i + 1] := v_loot[i + 1] * 115 / 100;
    end if;
    v_total := v_total + v_loot[i + 1];
  end loop;
  for i in 0 .. jsonb_array_length(a.attacker_army) - 1 loop
    v_squad := a.attacker_army -> i;
    v_alive := least(greatest(coalesce(private.json_int(p_survivors -> i, 0, 2147483647), 0), 0),
      coalesce(private.json_int(v_squad -> 1, 0, 10), 0));
    v_capacity := v_capacity + v_alive * private.unit_carry(private.json_int(v_squad -> 0, 0, 1000)::integer);
  end loop;
  if v_total > v_capacity then
    for i in 1 .. 4 loop
      v_loot[i] := v_loot[i] * v_capacity / v_total;
    end loop;
  end if;
  return v_loot::integer[];
end;
$$;
revoke all on function private.attack_loot(public.attacks, boolean, bigint, jsonb) from public, anon, authenticated;

-- Wynik workera w kształcie VerifyJob.verify, sprawdzony względem kopii ataku. Null, gdy kształt albo zakresy
-- się nie zgadzają (worker z inną wersją albo zepsuty pack nie ustali skutków).
create function private.checked_verified_result(a public.attacks, p_result jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_won boolean;
  v_percent bigint;
  v_stars jsonb;
  v_ids integer[] := '{}';
  v_alive jsonb := '[]'::jsonb;
  v_total bigint;
  v_ticks bigint;
  v_checksum bigint;
  v_sim bigint;
  x bigint;
  e jsonb;
begin
  if p_result is null or jsonb_typeof(p_result) <> 'object'
      or jsonb_typeof(p_result -> 'won') is distinct from 'boolean'
      or jsonb_typeof(p_result -> 'stars') is distinct from 'array'
      or jsonb_typeof(p_result -> 'destroyed_ids') is distinct from 'array'
      or jsonb_typeof(p_result -> 'survivors') is distinct from 'array' then
    return null;
  end if;
  v_won := (p_result ->> 'won')::boolean;
  v_percent := private.json_int(p_result -> 'percent', 0, 100);
  v_stars := p_result -> 'stars';
  v_ticks := private.json_int(p_result -> 'ticks', 0, 2147483647);
  v_checksum := private.json_int(p_result -> 'checksum', -9223372036854775808, 9223372036854775807);
  v_sim := private.json_int(p_result -> 'sim_version', 1, 2147483647);
  -- STAR_PERCENT = 50: druga gwiazdka od połowy zniszczeń, trzecia za wygraną
  if v_percent is null or v_ticks is null or v_checksum is null or v_sim is null
      or v_sim is distinct from a.sim_version::bigint
      or jsonb_array_length(v_stars) <> 3
      or jsonb_typeof(v_stars -> 0) <> 'boolean' or jsonb_typeof(v_stars -> 1) <> 'boolean'
      or jsonb_typeof(v_stars -> 2) <> 'boolean'
      or (v_stars ->> 1)::boolean <> (v_percent >= 50)
      or (v_stars ->> 2)::boolean <> v_won then
    return null;
  end if;

  -- zniszczone budynki: gotowe budynki z kopii zamku bez wału i palisady (jak record_destroyed), bez powtórzeń
  if jsonb_array_length(p_result -> 'destroyed_ids') > 200 then
    return null;
  end if;
  for e in select y.value from jsonb_array_elements(p_result -> 'destroyed_ids') as y loop
    x := private.json_int(e, 1, 2147483647);
    if x is null or x::integer = any (v_ids) then
      return null;
    end if;
    v_ids := v_ids || x::integer;
  end loop;
  if exists (
    select 1 from unnest(v_ids) as d(id)
    where not exists (
      select 1 from private.castle_buildings(a.castle_snapshot) b
      where b.id = d.id and b.level >= 1 and b.kind not in (0, 1))) then
    return null;
  end if;
  select count(*) into v_total from private.castle_buildings(a.castle_snapshot) b
  where b.level >= 1 and b.kind not in (0, 1);
  if cardinality(v_ids) > 0 and cardinality(v_ids)::bigint * 100 / greatest(v_total, 1) > v_percent then
    return null;
  end if;

  -- ocaleli: liczba na każdy oddział armii z chwili startu
  if jsonb_array_length(p_result -> 'survivors') <> jsonb_array_length(a.attacker_army) then
    return null;
  end if;
  for i in 0 .. jsonb_array_length(a.attacker_army) - 1 loop
    x := private.json_int(p_result -> 'survivors' -> i, 0,
      coalesce(private.json_int(a.attacker_army -> i -> 1, 0, 10), 0));
    if x is null then
      return null;
    end if;
    v_alive := v_alive || to_jsonb(x);
  end loop;

  return jsonb_build_object('won', v_won, 'percent', v_percent, 'stars', v_stars,
    'destroyed_ids', to_jsonb(array(select i from unnest(v_ids) as i order by i)),
    'survivors', v_alive, 'ticks', v_ticks, 'checksum', v_checksum, 'sim_version', v_sim);
end;
$$;
revoke all on function private.checked_verified_result(public.attacks, jsonb) from public, anon, authenticated;

-- ---- skutki ataku z wyniku workera ----

-- Łup (castle_loot_pending obu graczy), ranking (wyzwalacz attacks_pvp_rating), tarcza (SHIELD_PERCENT = 30,
-- SHIELD_HOURS = 8) i ruiny, wyłącznie z `verified_result`. `result` i `loot` dostają wynik serwera, więc
-- powtórka, raport obrony i złoto PvP generałów (attacks.loot[4]) widzą prawdę. Drugi raz nic nie robi.
create function private.apply_attack_outcome(p_attack uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  a public.attacks%rowtype;
  v jsonb;
  v_loot integer[];
  v_percent bigint;
begin
  select * into a from public.attacks t where t.id = p_attack for update;
  if not found or a.outcome_applied_at is not null or a.verified_result is null
      or a.verification not in ('verified', 'mismatch') or a.defender_id is null or a.status <> 'finished' then
    return false;
  end if;
  v := a.verified_result;
  v_percent := (v ->> 'percent')::bigint;
  v_loot := private.attack_loot(a, (v ->> 'won')::boolean, v_percent, v -> 'survivors');

  update public.attacks t set
    result = jsonb_build_object('won', v -> 'won', 'percent', v -> 'percent', 'stars', v -> 'stars'),
    loot = v_loot,
    destroyed = array(select (x.value #>> '{}')::integer from jsonb_array_elements(v -> 'destroyed_ids') as x),
    outcome_applied_at = now()
  where t.id = a.id;

  if v_loot[1] + v_loot[2] + v_loot[3] + v_loot[4] > 0 then
    perform private.add_loot_pending(a.attacker_id,
      array[v_loot[1], v_loot[2], v_loot[3], v_loot[4]]::bigint[]);
    perform private.add_loot_pending(a.defender_id,
      array[-v_loot[1], -v_loot[2], -v_loot[3], -v_loot[4]]::bigint[]);
  end if;
  if v_percent >= 30 then
    insert into public.shields as s (player_id, until) values (a.defender_id, now() + interval '8 hours')
    on conflict (player_id) do update set until = greatest(s.until, excluded.until);
  end if;
  return true;
end;
$$;
comment on function private.apply_attack_outcome(uuid) is
  'Skutki ataku PvP z wyniku workera (#284): łup, ranking, tarcza i ruiny tylko z verified_result; idempotentna.';
revoke all on function private.apply_attack_outcome(uuid) from public, anon, authenticated, service_role;

-- ---- API workera ----

-- Bierze jeden job: najstarszy bez ważnego lease i z mniej niż 3 próbami. Lease 5 minut. Joby po 3 próbach
-- z wygasłym lease kończą się `failed`: atak bez skutków, cel odblokowany. Zwraca null przy pustej kolejce.
create function private.claim_verification(p_worker text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  q private.attack_verifications%rowtype;
  a public.attacks%rowtype;
begin
  if p_worker is null or p_worker !~ '^[A-Za-z0-9_.-]{1,64}$' then
    raise exception 'bad_worker' using errcode = 'P0001';
  end if;

  with dead as (
    select v.attack_id from private.attack_verifications v
    where v.attempts >= 3 and v.leased_until <= now()
    for update skip locked
  ), gone as (
    delete from private.attack_verifications v using dead where v.attack_id = dead.attack_id
    returning v.attack_id
  )
  update public.attacks t set verification = 'failed', verified_at = now()
  from gone where t.id = gone.attack_id and t.verification = 'pending';

  select * into q from private.attack_verifications v
  where v.attempts < 3 and (v.leased_until is null or v.leased_until <= now()) and v.not_before <= now()
  order by v.created_at, v.attack_id
  limit 1
  for update skip locked;
  if not found then
    return null;
  end if;

  update private.attack_verifications v set
    attempts = v.attempts + 1,
    leased_until = now() + interval '5 minutes',
    leased_by = p_worker,
    -- poprzedni lease wygasł bez wyniku (timeout, crash albo błąd Godota po stronie workera)
    last_error = case when v.attempts > 0 then 'lease_expired' else v.last_error end
  where v.attack_id = q.attack_id;

  select * into a from public.attacks t where t.id = q.attack_id;
  return jsonb_build_object(
    'attack_id', a.id, 'id', a.id, 'sim_version', a.sim_version,
    'map_seed', a.map_seed, 'battle_seed', a.battle_seed,
    'castle', coalesce(a.castle_snapshot - 'scout', '{}'::jsonb), 'defense', coalesce(a.defense_snapshot, '{}'::jsonb),
    'army', a.attacker_army, 'plan', a.orders, 'techs', to_jsonb(coalesce(a.attacker_techs, '{}')),
    'general', a.attacker_general, 'ruler_perk', coalesce(a.attacker_ruler_perk, -1::smallint));
end;
$$;
comment on function private.claim_verification(text) is
  'Worker weryfikacji (#284): bierze jeden job z kolejki (SKIP LOCKED, lease 5 min, max 3 próby). Tylko dla roli verifier.';

-- Przyjmuje wynik workera dla jobu z ważnym lease. Zły kształt nie przerywa transakcji: job zostaje w kolejce
-- z kodem błędu i wolnym lease (kolejna próba). Zwraca verified, mismatch albo rejected.
create function private.submit_verification(p_attack uuid, p_result jsonb)
returns text
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  a public.attacks%rowtype;
  c jsonb;
  v jsonb;
  v_status text;
begin
  -- kolejność blokad jak w end_attack: najpierw atak, potem kolejka
  select * into a from public.attacks t where t.id = p_attack for update;
  if not found or a.verification is distinct from 'pending' then
    raise exception 'not_pending' using errcode = 'P0001';
  end if;
  perform 1 from private.attack_verifications v
  where v.attack_id = p_attack and v.leased_until > now()
  for update;
  if not found then
    raise exception 'lease_expired' using errcode = 'P0001';
  end if;

  v := private.checked_verified_result(a, p_result);
  if v is null then
    update private.attack_verifications q set last_error = 'bad_result', leased_until = now()
    where q.attack_id = p_attack;
    return 'rejected';
  end if;

  c := a.claimed_result;
  v_status := case
    when c is null then 'mismatch'
    -- ocaleli decydują o capacity łupu, więc też muszą się zgadzać
    when c -> 'won' = v -> 'won' and c -> 'percent' = v -> 'percent' and c -> 'stars' = v -> 'stars'
      and c -> 'survivors' is not distinct from v -> 'survivors'
      and (c -> 'destroyed_ids' is null
        or to_jsonb(array(select (x.value #>> '{}')::integer from jsonb_array_elements(c -> 'destroyed_ids') as x
          order by 1)) = v -> 'destroyed_ids')
      then 'verified'
    else 'mismatch'
  end;

  update public.attacks t set verified_result = v, verification = v_status, verified_at = now()
  where t.id = p_attack;
  delete from private.attack_verifications q where q.attack_id = p_attack;
  -- tryb enforce: skutki dopiero teraz; w trybie shadow już weszły w end_attack i to nic nie robi
  perform private.apply_attack_outcome(p_attack);
  return v_status;
end;
$$;
comment on function private.submit_verification(uuid, jsonb) is
  'Worker weryfikacji (#284): wynik przeliczonej bitwy, porównanie z wynikiem telefonu i skutki ataku. Tylko dla roli verifier.';

-- Ponowne wrzucenie jobu po poprawce (np. po `failed`). Tylko ręcznie, jako właścicielka projektu.
create function private.requeue_verification(p_attack uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.attacks t set verification = 'pending', verified_result = null, verified_at = null
  where t.id = p_attack and t.defender_id is not null and t.status = 'finished'
    and t.verification in ('failed', 'pending');
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;
  insert into private.attack_verifications (attack_id) values (p_attack)
  on conflict (attack_id) do update set attempts = 0, leased_until = null, leased_by = null, last_error = null,
    not_before = now();
  update private.attack_verifications v set not_before = now() where v.attack_id = p_attack;
end;
$$;
revoke all on function private.requeue_verification(uuid) from public, anon, authenticated, service_role;

-- Stan kolejki do monitoringu (§ Monitoring #284), tylko dla właścicielki.
create view private.verification_health
with (security_invoker = true)
as
-- zawsze jeden wiersz: długość kolejki widać także wtedy, gdy w 24 h nic się nie zweryfikowało
select
  (select count(*) from private.attack_verifications) as queue_length,
  (select extract(epoch from now() - min(v.created_at))::integer from private.attack_verifications v) as oldest_pending_s,
  d.verified_24h, d.mismatch_24h, d.failed_24h
from (
  select
    count(*) filter (where t.verification = 'verified') as verified_24h,
    count(*) filter (where t.verification = 'mismatch') as mismatch_24h,
    count(*) filter (where t.verification = 'failed') as failed_24h
  from public.attacks t
  where t.verified_at > now() - interval '24 hours'
) as d;
revoke all on private.verification_health from public, anon, authenticated, service_role;

-- ---- rola workera ----

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'verifier') then
    create role verifier nologin noinherit;
  end if;
end;
$$;
comment on role verifier is 'Worker weryfikacji ataków PvP (#284): tylko claim_verification i submit_verification. LOGIN i hasło ręcznie na projekcie.';
alter role verifier set statement_timeout = '10s';
alter role verifier set search_path = '';

revoke all on function private.claim_verification(text) from public, anon, authenticated, service_role;
revoke all on function private.submit_verification(uuid, jsonb) from public, anon, authenticated, service_role;
grant usage on schema private to verifier;
grant execute on function private.claim_verification(text) to verifier;
grant execute on function private.submit_verification(uuid, jsonb) to verifier;

-- ---- end_attack: wynik telefonu do porównania, skutki zależnie od trybu ----

create or replace function public.end_attack(p_attacker uuid, p_attack uuid, p_result jsonb, p_loot jsonb,
  p_survivors jsonb)
returns table (
  status text,
  result jsonb,
  loot integer[],
  shield_until timestamptz
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  a public.attacks%rowtype;
  v_won boolean;
  v_percent bigint;
  v_stars jsonb;
  v_loot_pct bigint;
  v_loot integer[] := array[0, 0, 0, 0];
  v_capacity bigint := 0;
  v_sum bigint := 0;
  v_stash bigint;
  v_cap bigint;
  v_squad jsonb;
  v_alive bigint;
  v_count bigint;
  v_shield timestamptz;
  v_mode text := 'off';
  x bigint;
begin
  select * into a from public.attacks t
  where t.id = p_attack and t.attacker_id = p_attacker
  for update;
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;

  if a.status = 'finished' then
    -- #284: atak w weryfikacji (enforce) nie ma jeszcze skutków ani łupu
    return query select case when a.outcome_applied_at is null then 'verifying'::text else a.status end,
      a.result, a.loot,
      (select s.until from public.shields s where s.player_id = a.defender_id);
    return;
  end if;
  -- wygasły atak: zapis porzucenia bez wyjątku, żeby się nie cofnął
  if a.status = 'started' and a.started_at < now() - interval '10 minutes' then
    update public.attacks t set status = 'abandoned' where t.id = a.id;
    a.status := 'abandoned';
  end if;
  if a.status <> 'started' then
    return query select a.status, null::jsonb, null::integer[], null::timestamptz;
    return;
  end if;

  -- wynik: dokładnie {won, percent, stars}; STAR_PERCENT = 50
  if p_result is null or jsonb_typeof(p_result) <> 'object'
      or (select count(*) from jsonb_object_keys(p_result)) <> 3
      or jsonb_typeof(p_result -> 'won') is distinct from 'boolean'
      or jsonb_typeof(p_result -> 'stars') is distinct from 'array' then
    raise exception 'bad_result' using errcode = 'P0001';
  end if;
  v_won := (p_result ->> 'won')::boolean;
  v_percent := private.json_int(p_result -> 'percent', 0, 100);
  v_stars := p_result -> 'stars';
  if v_percent is null or jsonb_array_length(v_stars) <> 3
      or jsonb_typeof(v_stars -> 0) <> 'boolean' or jsonb_typeof(v_stars -> 1) <> 'boolean'
      or jsonb_typeof(v_stars -> 2) <> 'boolean'
      or (v_stars ->> 1)::boolean <> (v_percent >= 50)
      or (v_stars ->> 2)::boolean <> v_won then
    raise exception 'bad_result' using errcode = 'P0001';
  end if;

  -- ocaleli: liczba na każdy oddział z armii zapisanej przy starcie
  if p_survivors is null or jsonb_typeof(p_survivors) <> 'array'
      or jsonb_array_length(p_survivors) <> jsonb_array_length(a.attacker_army) then
    raise exception 'bad_survivors' using errcode = 'P0001';
  end if;
  for i in 0 .. jsonb_array_length(a.attacker_army) - 1 loop
    v_squad := a.attacker_army -> i;
    v_count := private.json_int(v_squad -> 1, 0, 10);
    v_alive := private.json_int(p_survivors -> i, 0, coalesce(v_count, 0));
    if v_alive is null then
      raise exception 'bad_survivors' using errcode = 'P0001';
    end if;
    v_capacity := v_capacity + v_alive * private.unit_carry(private.json_int(v_squad -> 0, 0, 1000)::integer);
  end loop;

  -- łup: 4 liczby w kolejności EconomyConfig.Res (drewno, kamień, żywność, złoto)
  if p_loot is null or jsonb_typeof(p_loot) <> 'array' or jsonb_array_length(p_loot) <> 4 then
    raise exception 'bad_loot' using errcode = 'P0001';
  end if;
  -- WIN_LOOT_PERCENT = 50: wygrana liczy łup co najmniej jak przy połowie zniszczeń
  v_loot_pct := case when v_won then greatest(v_percent, 50) else 0 end;
  for i in 0 .. 3 loop
    x := private.json_int(p_loot -> i, 0, 10000000);
    if x is null then
      raise exception 'bad_loot' using errcode = 'P0001';
    end if;
    if a.defender_id is not null then
      v_stash := coalesce(private.json_int(a.castle_snapshot -> 'economy' -> 'amounts' -> i, 0, 10000000), 0);
    elsif i = 3 then
      -- skarbiec zamku-bota (BotRoster): GOLD_BASE = 20, GOLD_STEP = 10
      v_stash := 20 + 10 * a.bot_idx;
    else
      -- STASH_BASE = 1000, STASH_STEP = 500
      v_stash := 1000 + 500 * a.bot_idx;
    end if;
    -- PROTECTED_PERCENT = 50, LOOT_PERCENT = 20; dzielenie całkowite jak BattleResult.compute_loot
    v_cap := v_stash * (100 - 50) / 100 * 20 / 100 * v_loot_pct / 100;
    -- Łupieżca (#32): LOOTER_LOOT_PERCENT = 115 tylko przy ataku na gracza, z perkiem zapisanym przy
    -- zatwierdzeniu planu (attacks.attacker_ruler_perk); dzielenie całkowite jak RulerPerks.pvp_loot
    if a.defender_id is not null and a.attacker_ruler_perk = 1 then
      v_cap := v_cap * 115 / 100;
    end if;
    if x > v_cap then
      raise exception 'loot_too_high' using errcode = 'P0001';
    end if;
    v_loot[i + 1] := x::integer;
    v_sum := v_sum + x;
  end loop;
  if v_sum > v_capacity then
    raise exception 'loot_too_high' using errcode = 'P0001';
  end if;

  -- #284: atak na gracza idzie do weryfikacji na serwerze (worker z tym samym GDScript). Wynik telefonu zostaje
  -- w claimed_result tylko do porównania.
  if a.defender_id is not null then
    v_mode := private.verification_mode();
  end if;
  if v_mode = 'enforce' then
    -- bez łupu, rankingu, tarczy i ruin: wszystko policzy apply_attack_outcome z wyniku workera. Cel zostaje
    -- zablokowany (begin_attack, match_targets), więc nikt nie złupi tych samych zapasów drugi raz.
    update public.attacks t set status = 'finished', result = p_result, loot = null, finished_at = now(),
      claimed_result = jsonb_build_object('won', v_won, 'percent', v_percent, 'stars', v_stars,
        'loot', to_jsonb(v_loot), 'survivors', p_survivors),
      verification = 'pending'
    where t.id = a.id;
    perform private.enqueue_verification(a.id);
    return query select 'verifying'::text, p_result, null::integer[],
      (select s.until from public.shields s where s.player_id = a.defender_id);
    return;
  end if;

  update public.attacks t set status = 'finished', result = p_result, loot = v_loot, finished_at = now(),
    outcome_applied_at = now(),
    claimed_result = case when v_mode = 'shadow' then jsonb_build_object('won', v_won, 'percent', v_percent,
      'stars', v_stars, 'loot', to_jsonb(v_loot), 'survivors', p_survivors) end,
    verification = case when v_mode = 'shadow' and a.sim_version is not null then 'pending' end
  where t.id = a.id;
  -- tryb shadow: skutki już weszły z wyniku telefonu, worker tylko porówna (attacks.verification)
  if v_mode = 'shadow' and a.sim_version is not null then
    perform private.enqueue_verification(a.id);
  end if;

  -- #274: łup przenosi serwer w tej samej transakcji: atakujący zyskuje, a obrońca-gracz traci. Od #282 także
  -- łup z zamku-bota (bez obrońcy). Zmiana czeka w castle_loot_pending i wchodzi do `castles.data` przy
  -- najbliższym zapisie zamku każdego z nich (wyzwalacz castles_resources, po bilansie surowców). Ponowienie
  -- wraca wyżej (status 'finished'), więc łup liczy się raz.
  if v_sum > 0 then
    perform private.add_loot_pending(a.attacker_id,
      array[v_loot[1], v_loot[2], v_loot[3], v_loot[4]]::bigint[]);
  end if;
  if a.defender_id is not null and v_sum > 0 then
    perform private.add_loot_pending(a.defender_id,
      array[-v_loot[1], -v_loot[2], -v_loot[3], -v_loot[4]]::bigint[]);
  end if;

  -- SHIELD_PERCENT = 30, SHIELD_HOURS = 8
  if a.defender_id is not null and v_percent >= 30 then
    insert into public.shields as s (player_id, until) values (a.defender_id, now() + interval '8 hours')
    on conflict (player_id) do update set until = greatest(s.until, excluded.until);
  end if;
  if a.defender_id is not null then
    select s.until into v_shield from public.shields s where s.player_id = a.defender_id;
  end if;

  return query select 'finished'::text, p_result, v_loot, v_shield;
end;
$$;

comment on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) is
  'Koniec ataku (#25): wynik i łup w limitach (zapasy obrońcy, capacity ocalałych, Łupieżca #32). Atak na gracza idzie do weryfikacji (#284): w trybie shadow skutki od razu i porównanie przez worker, w enforce status verifying bez łupu, rankingu, tarczy i ruin, które da wynik workera. Łup przez castle_loot_pending (#274, #282); ponowienie zwraca zapisany wynik. Tylko dla service_role (Edge Function finish_attack).';
revoke all on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) to service_role;

-- ---- record_destroyed: w weryfikacji lista telefonu tylko do porównania ----

create or replace function public.record_destroyed(p_attacker uuid, p_attack uuid, p_destroyed jsonb)
returns integer[]
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  a public.attacks%rowtype;
  v_ids integer[] := '{}';
  v_total bigint;
  v_percent bigint;
  e jsonb;
  x bigint;
begin
  select * into a from public.attacks t
  where t.id = p_attack and t.attacker_id = p_attacker
  for update;
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;
  if a.status <> 'finished' then
    raise exception 'attack_not_finished' using errcode = 'P0001';
  end if;
  if a.defender_id is null then
    return null;
  end if;
  if a.destroyed is not null then
    return a.destroyed;
  end if;
  -- #284: lista z telefonu w weryfikacji (enforce) tylko do porównania; ruiny da wynik workera
  if a.outcome_applied_at is null and a.claimed_result ? 'destroyed_ids' then
    return array(select (x.value #>> '{}')::integer from jsonb_array_elements(a.claimed_result -> 'destroyed_ids') as x);
  end if;

  -- MAX_DESTROYED = 200
  if p_destroyed is null or jsonb_typeof(p_destroyed) <> 'array' or jsonb_array_length(p_destroyed) > 200 then
    raise exception 'bad_destroyed' using errcode = 'P0001';
  end if;
  for e in select y.value from jsonb_array_elements(p_destroyed) as y loop
    x := private.json_int(e, 1, 2147483647);
    if x is null or x::integer = any (v_ids) then
      raise exception 'bad_destroyed' using errcode = 'P0001';
    end if;
    v_ids := v_ids || x::integer;
  end loop;

  -- budynki z kopii zamku jak w BattleResult: gotowe, bez wału (0) i palisady (1)
  if exists (
    select 1 from unnest(v_ids) as d(id)
    where not exists (
      select 1 from private.castle_buildings(a.castle_snapshot) b
      where b.id = d.id and b.level >= 1 and b.kind not in (0, 1))) then
    raise exception 'bad_destroyed' using errcode = 'P0001';
  end if;
  select count(*) into v_total from private.castle_buildings(a.castle_snapshot) b
  where b.level >= 1 and b.kind not in (0, 1);
  v_percent := coalesce(private.json_int(a.result -> 'percent', 0, 100), 0);
  -- dzielenie całkowite jak BattleResult.of
  if cardinality(v_ids) > 0 and cardinality(v_ids)::bigint * 100 / greatest(v_total, 1) > v_percent then
    raise exception 'destroyed_too_many' using errcode = 'P0001';
  end if;

  -- #284: zgłoszona lista trafia też do claimed_result (porównanie z wynikiem workera); w trybie enforce ruiny
  -- czekają na weryfikację
  if a.claimed_result is not null then
    update public.attacks t set claimed_result = t.claimed_result || jsonb_build_object('destroyed_ids', to_jsonb(v_ids))
    where t.id = a.id;
    perform private.verification_ready(a.id);
  end if;
  if a.outcome_applied_at is not null then
    update public.attacks t set destroyed = v_ids where t.id = a.id;
  end if;
  return v_ids;
end;
$$;

comment on function public.record_destroyed(uuid, uuid, jsonb) is
  'Zniszczone budynki obrońcy po ataku (#99): tylko własny zakończony atak na gracza, gotowe budynki z kopii zamku bez umocnień, nie więcej niż procent zniszczeń; pierwszy zapis wygrywa. W weryfikacji (#284, enforce) lista idzie tylko do claimed_result, a ruiny daje wynik workera. Tylko dla service_role (Edge Function finish_attack).';
revoke all on function public.record_destroyed(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.record_destroyed(uuid, uuid, jsonb) to service_role;

-- ---- launch_attack: wersja symulacji ----

-- nowy, opcjonalny parametr p_sim_version; wdrożona Edge Function bez niego dostaje najnowszą wspieraną wersję
drop function public.launch_attack(uuid, uuid, jsonb, integer);

create function public.launch_attack(p_attacker uuid, p_attack uuid, p_plan jsonb, p_general integer,
  p_sim_version integer default null)
returns table (
  castle jsonb,
  defense jsonb,
  plan jsonb,
  techs text[],
  general jsonb,
  ruler_perk smallint
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  a public.attacks%rowtype;
  v_data jsonb;
  v_done jsonb;
begin
  if p_general is not null and (p_general < 0 or p_general > 2) then
    raise exception 'bad_general' using errcode = 'P0001';
  end if;
  select * into a from public.attacks t
  where t.id = p_attack and t.attacker_id = p_attacker and t.defender_id is not null
  for update;
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;
  if a.status <> 'started' or a.started_at < now() - interval '10 minutes' then
    raise exception 'attack_expired' using errcode = 'P0001';
  end if;
  if a.launched_at is null then
    -- #284 §2: wersja symulacji klienta musi mieć pack na workerze (unsupported_version → aktualizacja gry)
    a.sim_version := private.checked_sim_version(p_sim_version);
    a.orders := private.check_plan(p_plan, jsonb_array_length(a.attacker_army));
    select c.data into v_data from public.castles c where c.player_id = p_attacker;
    v_done := v_data -> 'research' -> 'done';
    a.attacker_techs := array(
      select code from unnest(array['A1', 'A2', 'A7']) as code
      where jsonb_typeof(v_done) = 'array' and v_done @> jsonb_build_array(code));
    a.attacker_general := case when p_general is null then null else private.castle_general(v_data, p_general) end;
    -- perk władcy (#32) z zamku na serwerze, sprawdzony przy zapisie (castles_check_ruler_perk); epokę
    -- sprawdzamy jeszcze raz, bo zamek zapisany przed tą migracją nie przeszedł przez wyzwalacz
    a.attacker_ruler_perk := private.castle_ruler_perk(v_data);
    if a.attacker_ruler_perk in (1, 4) and greatest(
        coalesce((select p.age from public.players p where p.id = p_attacker), 0),
        private.castle_age(v_data)) < 1 then
      a.attacker_ruler_perk := -1;
    end if;
    update public.attacks t set launched_at = now(), orders = a.orders, attacker_techs = a.attacker_techs,
      attacker_general = a.attacker_general, attacker_ruler_perk = a.attacker_ruler_perk,
      sim_version = a.sim_version
    where t.id = a.id;
  end if;
  return query select a.castle_snapshot - 'scout', a.defense_snapshot, a.orders,
    coalesce(a.attacker_techs, '{}'), a.attacker_general, coalesce(a.attacker_ruler_perk, -1::smallint);
end;
$$;

comment on function public.launch_attack(uuid, uuid, jsonb, integer, integer) is
  'Atak na gracza po zatwierdzeniu planu (#28): pełne kopie zamku i obrony z chwili startu; zapisuje plan, badania, generała ataku, perk władcy (#29, #31, #32) i wersję symulacji dla weryfikacji (#284, unsupported_version bez packa). Tylko dla service_role (Edge Function launch_attack).';
revoke all on function public.launch_attack(uuid, uuid, jsonb, integer, integer) from public, anon, authenticated;
grant execute on function public.launch_attack(uuid, uuid, jsonb, integer, integer) to service_role;

-- ---- begin_attack i match_targets: cel z atakiem w weryfikacji jest zablokowany ----

create or replace function public.begin_attack(p_attacker uuid, p_defender uuid, p_bot smallint, p_army jsonb,
  p_battle_seed bigint)
returns table (
  attack_id uuid,
  map_seed bigint,
  battle_seed bigint,
  castle jsonb,
  defense jsonb
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_age smallint;
  v_rating integer;
  v_own jsonb;
  d_age smallint;
  d_rating integer;
  v_seed bigint;
  v_castle jsonb;
  v_defense jsonb;
  v_id uuid;
  e jsonb;
  u bigint;
  n bigint;
  want integer[];
  have integer[];
  v_units integer;
  v_upkeep integer;
  v_garrison bigint[];
  v_paid integer;
  d_paid integer;
begin
  if p_attacker is null or (p_defender is null) = (p_bot is null) then
    raise exception 'bad_target' using errcode = 'P0001';
  end if;
  if p_defender = p_attacker then
    raise exception 'self_attack' using errcode = 'P0001';
  end if;
  if p_battle_seed is null or p_battle_seed < 0 or p_battle_seed > 2147483647 then
    raise exception 'bad_seed' using errcode = 'P0001';
  end if;

  -- blokada wierszy graczy w stałej kolejności: równoległe starty tego samego atakującego albo na
  -- tego samego obrońcę idą po kolei, a wzajemny atak dwóch graczy się nie zakleszczy
  perform 1 from public.players p
  where p.id = p_attacker or p.id = p_defender
  order by p.id
  for update;

  select p.age, p.rating into v_age, v_rating from public.players p where p.id = p_attacker;
  if not found then
    raise exception 'attacker_not_found' using errcode = 'P0001';
  end if;
  select c.data, c.ruler_perk_paid into v_own, v_paid from public.castles c where c.player_id = p_attacker;
  if not found then
    raise exception 'attacker_no_castle' using errcode = 'P0001';
  end if;
  -- #274: zamek z surowcami spoza limitów (zapis sprzed tej migracji) nie wchodzi do PvP. Nic nie przycinamy:
  -- gracz poprawia zamek zwykłym zapisem z gry, który przechodzi przez wyzwalacz castles_resources.
  if private.castle_resources_problem(p_attacker, v_own, v_paid) is not null then
    raise exception 'castle_invalid' using errcode = 'P0001';
  end if;

  -- limit sprawdzany przed zapisem; START_LIMIT = 10
  if (select count(*) from public.attacks a
      where a.attacker_id = p_attacker and a.started_at > now() - interval '10 minutes') >= 10 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  -- armia: [[rodzaj, liczba], ...]; MAX_SQUADS_BY_AGE = [3, 4, 5, 6, 7, 8], SQUAD_SIZE = 10
  if p_army is null or jsonb_typeof(p_army) <> 'array' or jsonb_array_length(p_army) < 1
      or jsonb_array_length(p_army) > (array[3, 4, 5, 6, 7, 8])[least(greatest(v_age, 0), 5) + 1] then
    raise exception 'bad_army' using errcode = 'P0001';
  end if;
  want := array_fill(0, array[private.unit_count()]);
  have := array_fill(0, array[private.unit_count()]);
  for e in select x.value from jsonb_array_elements(p_army) as x loop
    if jsonb_typeof(e) <> 'array' or jsonb_array_length(e) <> 2 then
      raise exception 'bad_army' using errcode = 'P0001';
    end if;
    u := private.json_int(e -> 0, 0, private.unit_count() - 1);
    n := private.json_int(e -> 1, 1, 10);
    if u is null or n is null then
      raise exception 'bad_army' using errcode = 'P0001';
    end if;
    want[u + 1] := want[u + 1] + n;
  end loop;
  -- #81: garnizon Dworu nie idzie do ataku. Oddziały z zadaniem obrony GARRISON = 6 w zapisie zamku
  -- (`defense.orders` = [[id oddziału, zadanie, x, y, trasa], ...], DefensePlan.to_dict) nie liczą się
  -- do wojska, którym atakujący może zaatakować. Zły wpis to brak garnizonu (jak w DefensePlan.from_dict).
  select coalesce(array_agg(private.json_int(o.value -> 0, 1, 2147483647)), '{}'::bigint[]) into v_garrison
  from jsonb_array_elements(
      case when jsonb_typeof(v_own -> 'defense' -> 'orders') = 'array'
        then v_own -> 'defense' -> 'orders' else '[]'::jsonb end) as o
  -- `case`, bo `and` w SQL nie gwarantuje kolejności, a jsonb_array_length na skalarze rzuca błąd
  where case when jsonb_typeof(o.value) <> 'array' then false
      when jsonb_array_length(o.value) < 4 then false
      else private.json_int(o.value -> 1, 0, 100) = 6
        and private.json_int(o.value -> 0, 1, 2147483647) is not null end;
  -- oddziały w zapisie zamku: [id, rodzaj, liczba]; złe wpisy się nie liczą, garnizon też nie
  for e in select x.value from jsonb_array_elements(
      case when jsonb_typeof(v_own -> 'recruitment' -> 'squads') = 'array'
        then v_own -> 'recruitment' -> 'squads' else '[]'::jsonb end) as x loop
    if jsonb_typeof(e) = 'array' and jsonb_array_length(e) >= 3
        and coalesce(private.json_int(e -> 0, 1, 2147483647) <> all (v_garrison), true) then
      u := private.json_int(e -> 1, 0, private.unit_count() - 1);
      n := private.json_int(e -> 2, 0, 10);
      if u is not null and n is not null then
        have[u + 1] := have[u + 1] + n;
      end if;
    end if;
  end loop;
  for i in 1 .. private.unit_count() loop
    if want[i] > have[i] then
      raise exception 'army_not_owned' using errcode = 'P0001';
    end if;
  end loop;

  -- #249: limit miejsc i utrzymania z kopii zamku atakującego na serwerze (Recruitment.army_limit,
  -- Recruitment.upkeep_limit). Liczy się armia z żądania, nie cały zamek: po rozbiórce Koszar albo
  -- Rybaka zamek może chwilowo mieć więcej wojska, niż utrzyma, a do ataku idzie tylko tyle, ile się mieści.
  v_units := 0;
  v_upkeep := 0;
  for i in 1 .. private.unit_count() loop
    v_units := v_units + want[i];
    v_upkeep := v_upkeep + want[i] * private.unit_upkeep(i - 1);
  end loop;
  if v_units > private.army_limit(v_own) then
    raise exception 'army_over_limit' using errcode = 'P0001';
  end if;
  if v_upkeep > private.food_production(v_own) then
    raise exception 'army_over_upkeep' using errcode = 'P0001';
  end if;

  -- wygasłe ataki w toku zwalniają cele (ATTACK_TIMEOUT = 10 minut), a nowy start atakującego
  -- porzuca jego poprzedni atak
  update public.attacks a set status = 'abandoned'
  where a.status = 'started'
    and (a.started_at < now() - interval '10 minutes' or a.attacker_id = p_attacker);

  if p_bot is not null then
    select b.map_seed into v_seed from public.bot_castles b where b.idx = p_bot;
    if not found then
      raise exception 'target_not_found' using errcode = 'P0001';
    end if;
  else
    select p.age, p.rating into d_age, d_rating from public.players p where p.id = p_defender;
    select c.map_seed, c.data, c.ruler_perk_paid into v_seed, v_castle, d_paid from public.castles c
    where c.player_id = p_defender
      and char_length(coalesce(c.data -> 'profile' ->> 'castle_name', '')) > 0;
    if d_age is null or v_seed is null then
      raise exception 'target_not_found' using errcode = 'P0001';
    end if;
    -- #274: obrońca z nierealnym zapisem nie jest celem, a kopia zamku do bitwy ma już łup z wcześniejszych
    -- ataków, którego telefon obrońcy jeszcze nie scalił (castle_loot_pending): nie da się złupić dwa razy
    -- tych samych zapasów
    if private.castle_resources_problem(p_defender, v_castle, d_paid) is not null then
      raise exception 'target_not_found' using errcode = 'P0001';
    end if;
    v_castle := private.castle_with_pending(p_defender, v_castle);
    if exists (select 1 from public.shields s where s.player_id = p_defender and s.until > now()) then
      raise exception 'target_shielded' using errcode = 'P0001';
    end if;
    if abs(d_age - v_age) > 1 or abs(d_rating - v_rating) > 100 then
      raise exception 'target_out_of_range' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.attacks a
        where a.attacker_id = p_attacker and a.defender_id = p_defender
          and a.started_at > now() - interval '24 hours') then
      raise exception 'target_recent' using errcode = 'P0001';
    end if;
    -- #284: atak w weryfikacji (enforce) blokuje cel jak atak w toku, aż wejdą jego skutki
    if exists (select 1 from public.attacks a where a.defender_id = p_defender
        and (a.status = 'started' or (a.verification = 'pending' and a.outcome_applied_at is null))) then
      raise exception 'target_busy' using errcode = 'P0001';
    end if;
    select coalesce((select d.data from public.defense_layouts d where d.player_id = p_defender),
      '{}'::jsonb) into v_defense;
  end if;

  insert into public.attacks (attacker_id, defender_id, bot_idx, map_seed, battle_seed, attacker_army,
    defense_snapshot, castle_snapshot)
  values (p_attacker, p_defender, p_bot, v_seed, p_battle_seed, p_army, v_defense, v_castle)
  returning id into v_id;

  return query select v_id, v_seed, p_battle_seed, v_castle, v_defense;
end;
$$;

comment on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) is
  'Start ataku (#25, #249, #81, #274): limit 10 startów na 10 minut, zamek atakującego i obrońcy w limitach surowców (#274), armia z zamku atakującego bez garnizonu Dworu w limicie miejsc i utrzymania żywności, cel bez tarczy, bez innego ataku w toku i bez ataku w weryfikacji (#284); zwraca seedy, kopię zamku z czekającym łupem i obronę. Tylko dla service_role (Edge Function start_attack).';
revoke all on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) from public, anon, authenticated;
grant execute on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) to service_role;

create or replace function public.match_targets(p_attacker uuid)
returns table (
  player_id uuid,
  nickname text,
  castle_name text,
  ruler text,
  age smallint,
  rating integer,
  map_seed bigint,
  footprint jsonb,
  loot integer[]
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  w timestamptz;
  n integer;
begin
  if p_attacker is null then
    return;
  end if;
  -- limit sprawdzany przed zapisem: odrzucone szukanie niczego nie zmienia, więc nie zależy od tego,
  -- czy wyjątek cofnie transakcję (licznik zostaje na 20 do końca okna)
  select t.window_start, t.searches into w, n
  from private.target_searches t where t.player_id = p_attacker for update;
  if found and w >= now() - interval '10 minutes' and n >= 20 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  insert into private.target_searches as t (player_id, window_start, searches)
  values (p_attacker, now(), 1)
  on conflict (player_id) do update set
    window_start = case when t.window_start < now() - interval '10 minutes' then now() else t.window_start end,
    searches = case when t.window_start < now() - interval '10 minutes' then 1 else t.searches + 1 end;

  return query
  with me as (
    select p.age, p.rating from public.players p where p.id = p_attacker
  )
  select
    p.id,
    p.nickname,
    left(c.data -> 'profile' ->> 'castle_name', 16),
    left(coalesce(c.data -> 'profile' ->> 'ruler', ''), 20),
    p.age,
    -- karta celu pokazuje ranking obrony (#27): atakujący mierzy się z obroną celu
    p.defense_rating,
    c.map_seed,
    -- zarys budynków: wpis zapisu [id, rodzaj, poziom, x, y, szer., wys.] → [x, y, szer., wys.]
    coalesce((
      select jsonb_agg(jsonb_build_array(e.v -> 3, e.v -> 4, e.v -> 5, e.v -> 6) order by e.ord)
      from jsonb_array_elements(
        case when jsonb_typeof(c.data -> 'grid' -> 'buildings') = 'array'
          then c.data -> 'grid' -> 'buildings' else '[]'::jsonb end
      ) with ordinality as e(v, ord)
      -- CASE, bo SQL nie gwarantuje kolejności warunków w AND (długość skalara rzuca błąd)
      where e.ord <= 400
        and case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 7 else false end
    ), '[]'::jsonb),
    -- szacowany łup: LOOT_ESTIMATE_PERCENT = 5 procent zapasów (połowa chroniona × 20 procent łupu
    -- × co najmniej 50 procent zniszczeń po wygranej, jak BattleResult), w dół do pełnych dziesiątek,
    -- żeby karta nie zdradzała dokładnego stanu magazynu
    array(
      select (greatest(0, least(coalesce(
        case when jsonb_typeof(c.data -> 'economy' -> 'amounts' -> i) = 'number'
          then floor((c.data -> 'economy' -> 'amounts' ->> i)::numeric) end, 0), 10000000))::integer
        * 5 / 100 / 10 * 10)
      from generate_series(0, 3) as i
      order by i
    )
  from me, public.players p
  join public.castles c on c.player_id = p.id
  where p.id <> p_attacker
    and char_length(coalesce(c.data -> 'profile' ->> 'castle_name', '')) > 0
    and abs(p.age - me.age) <= 1
    and abs(p.rating - me.rating) <= 100
    and not exists (
      select 1 from public.shields s where s.player_id = p.id and s.until > now()
    )
    -- #284: cel z atakiem w weryfikacji (enforce) czeka, aż wejdą skutki tamtego ataku
    and not exists (
      select 1 from public.attacks a
      where a.defender_id = p.id and a.verification = 'pending' and a.outcome_applied_at is null
    )
    and not exists (
      select 1 from public.attacks a
      where a.attacker_id = p_attacker and a.defender_id = p.id
        and a.started_at > now() - interval '24 hours'
    )
  order by random()
  limit 3;
end;
$$;

comment on function public.match_targets(uuid) is
  'Dobór przeciwnika (#24): do 3 graczy bez tarczy i bez ataku w weryfikacji (#284), epoka ±1, ranking ±100, bez ataku od p_attacker w 24 h; najwyżej 20 wywołań na 10 minut; karta pokazuje ranking obrony (#27). Tylko dla service_role (Edge Function find_targets).';
revoke all on function public.match_targets(uuid) from public, anon, authenticated;
grant execute on function public.match_targets(uuid) to service_role;
