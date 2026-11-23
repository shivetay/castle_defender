-- #288 (follow-up z review #287): nagroda fali PvE tylko za falę, którą zna serwer.
--
-- Po #282 bilans surowców wliczał nagrody fal PvE z `pve.cleared` w zapisie telefonu (raz na falę,
-- `castles.pve_rewarded`). Zmodyfikowany klient mógł podnieść licznik z 0 do 5 i dostać jednorazowo pełne
-- nagrody (1250 drewna, 800 kamienia, 1250 żywności, 125 złota) bez żadnej bitwy. Teraz fala idzie przez serwer
-- jak wyprawa na zamek-bota (#242, #282): Edge Function `pve_wave` woła `begin_wave` przy starcie fali
-- i `end_wave` z wynikiem po niej. Nagrodę za wygraną falę dopisuje serwer do `castle_loot_pending`,
-- a zapis zamku scala ją po bilansie i zwraca w `loot_applied` (telefon dolicza ją z odpowiedzi).
-- Bilans surowców (`private.check_castle_resources`) nie liczy już żadnych nagród fal z zapisu.
--
-- Zasady (liczby tymczasowe, jak skład fal i nagrody w grze):
-- - fal jest PveWaves.COUNT = 5, a nagroda za falę to PveWaves.REWARDS = [[100, 50, 100, 10], [150, 100, 150, 15], [200, 150, 200, 20], [300, 200, 300, 30], [500, 300, 500, 50]]
--   (drewno, kamień, żywność, złoto), za każdą falę najwyżej raz na konto;
-- - postęp serwera (`private.pve_progress`) to numer pierwszej fali, której serwer jeszcze nie nagrodził:
--   wyższy z `castles.pve_rewarded` (fale wliczone przed tą migracją, kolumny nie zmienia już nic) i ostatniej
--   wygranej fali + 1. Start fali poniżej postępu jest odrzucany (`wave_done`), więc tej samej nagrody nie da
--   się wziąć drugi raz;
-- - fale mogą iść z przerwą: fala wygrana bez sieci odblokowuje w grze następną (decyzja do potwierdzenia przez
--   właścicielkę, #288), ale nagrody za nią nie ma i serwer jej nie zna, więc kolejna fala z siecią startuje
--   z numerem wyższym niż postęp. Pominiętej fali serwer później już nie nagrodzi;
-- - naraz trwa jedna fala gracza: nowy start porzuca poprzednią niezakończoną. Startów jest najwyżej
--   WAVE_START_LIMIT = 10 na 10 minut (`rate_limited`);
-- - wynik przyjmuje serwer najwyżej WAVE_DEADLINE_S = 600 sekund od startu (potem fala jest porzucona) i nie
--   wcześniej niż WAVE_MIN_S = 5 sekund od startu dla wygranej (`wave_too_fast`): fala nie kończy się, zanim
--   wróg dojdzie pod zamek, nawet w tempie x4. Ponowienie dla zakończonej fali zwraca zapisany wynik.
-- Wyniku bitwy serwer nie odtwarza (jak przy zamkach-botach), ale nagroda ma twardą górną granicę: suma
-- PveWaves.REWARDS raz na konto, każda fala po prawdziwym starcie i co najmniej WAVE_MIN_S sekund bitwy.
-- Liczby pilnuje test gry (`tests/test_pve_wave.gd`) po znacznikach w komentarzach.

-- ---------------------------------------------------------------------------------------------
-- Przebiegi fal
-- ---------------------------------------------------------------------------------------------

create table public.pve_wave_runs (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.players (id) on delete cascade,
  wave smallint not null check (wave between 0 and 4),
  status text not null default 'started' check (status in ('started', 'won', 'lost', 'abandoned')),
  -- nagroda dopisana do zamku (drewno, kamień, żywność, złoto); zera przy przegranej
  reward integer[] check (reward is null or (cardinality(reward) = 4 and 0 <= all (reward))),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint pve_wave_runs_finished check ((status = 'started') = (finished_at is null)),
  constraint pve_wave_runs_result check (status not in ('won', 'lost') or reward is not null)
);
comment on table public.pve_wave_runs is
  'Fale PvE przyjęte przez serwer (#288). Piszą je tylko begin_wave i end_wave (Edge Function pve_wave).';

create index pve_wave_runs_player_started_idx on public.pve_wave_runs (player_id, started_at desc);

-- Klient nie czyta ani nie pisze przebiegów: postęp i nagroda przychodzą z odpowiedzi `pve_wave`
-- i z `castles.loot_applied`. RLS włączone bez polityk, uprawnienia tylko dla service_role.
alter table public.pve_wave_runs enable row level security;
revoke all on public.pve_wave_runs from public, anon, authenticated;
grant select, insert, update, delete on public.pve_wave_runs to service_role;

-- ---------------------------------------------------------------------------------------------
-- Postęp i nagrody
-- ---------------------------------------------------------------------------------------------

-- Pierwsza fala, której serwer jeszcze nie nagrodził (0..5).
create function private.pve_progress(p_player uuid)
returns integer
language sql
stable
set search_path = ''
as $$
  select greatest(
    coalesce((select c.pve_rewarded::integer from public.castles c where c.player_id = p_player), 0),
    coalesce((select max(r.wave)::integer + 1 from public.pve_wave_runs r
      where r.player_id = p_player and r.status = 'won'), 0))
$$;

-- Nagroda za falę `p_wave` (PveWaves.REWARDS).
create function private.pve_wave_reward(p_wave integer)
returns integer[]
language sql
immutable
set search_path = ''
as $$
  select array(select ((('[[100, 50, 100, 10], [150, 100, 150, 15], [200, 150, 200, 20], [300, 200, 300, 30], [500, 300, 500, 50]]'::jsonb
      -> p_wave) ->> r)::integer)
    from generate_series(0, 3) r order by r)
$$;

revoke all on function private.pve_progress(uuid) from public, anon, authenticated;
revoke all on function private.pve_wave_reward(integer) from public, anon, authenticated;
grant execute on function private.pve_progress(uuid) to service_role;
grant execute on function private.pve_wave_reward(integer) to service_role;

comment on column public.castles.pve_rewarded is
  'Fale PvE wliczone do bilansu przed #288 (z pve.cleared). Od #288 nie zmienia jej nic; postęp liczy private.pve_progress.';

-- ---------------------------------------------------------------------------------------------
-- Start i koniec fali (Edge Function `pve_wave`, rola service_role; id gracza wyłącznie z tokenu)
-- ---------------------------------------------------------------------------------------------

create function public.begin_wave(p_player uuid, p_wave integer)
returns table (
  run_id uuid,
  wave smallint
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  -- jeden start naraz na gracza: blokada wiersza gracza
  perform 1 from public.players p where p.id = p_player for update;
  if not found then
    raise exception 'player_not_found' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.castles c where c.player_id = p_player) then
    raise exception 'no_castle' using errcode = 'P0001';
  end if;
  if p_wave is null or p_wave < 0 or p_wave > 4 then
    raise exception 'bad_wave' using errcode = 'P0001';
  end if;
  if p_wave < private.pve_progress(p_player) then
    raise exception 'wave_done' using errcode = 'P0001';
  end if;
  -- WAVE_START_LIMIT = 10 startów na 10 minut
  if (select count(*) from public.pve_wave_runs r
      where r.player_id = p_player and r.started_at > now() - interval '10 minutes') >= 10 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  update public.pve_wave_runs r set status = 'abandoned', finished_at = now()
  where r.player_id = p_player and r.status = 'started';
  insert into public.pve_wave_runs (player_id, wave) values (p_player, p_wave::smallint)
  returning id into v_id;
  return query select v_id, p_wave::smallint;
end;
$$;

comment on function public.begin_wave(uuid, integer) is
  'Start fali PvE (#288): fala od postępu serwera w górę, jedna naraz, 10 startów na 10 minut.';

create function public.end_wave(p_player uuid, p_run uuid, p_won boolean)
returns table (
  status text,
  wave smallint,
  reward integer[]
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  r public.pve_wave_runs%rowtype;
  v_reward integer[] := array[0, 0, 0, 0];
begin
  -- blokada gracza przed falą: ta sama kolejność co w begin_wave
  perform 1 from public.players p where p.id = p_player for update;
  select * into r from public.pve_wave_runs t
  where t.id = p_run and t.player_id = p_player
  for update;
  if not found then
    raise exception 'wave_not_found' using errcode = 'P0001';
  end if;
  -- ponowienie po błędzie sieci: zapisany wynik
  if r.status <> 'started' then
    return query select r.status, r.wave, r.reward;
    return;
  end if;
  -- WAVE_DEADLINE_S = 600
  if now() - r.started_at > interval '600 seconds' then
    update public.pve_wave_runs t set status = 'abandoned', finished_at = now() where t.id = r.id;
    return query select 'abandoned'::text, r.wave, null::integer[];
    return;
  end if;
  if p_won is null then
    raise exception 'bad_result' using errcode = 'P0001';
  end if;
  if p_won then
    -- WAVE_MIN_S = 5
    if now() - r.started_at < interval '5 seconds' then
      raise exception 'wave_too_fast' using errcode = 'P0001';
    end if;
    -- fala poniżej postępu (nagrodzona w międzyczasie) wygrywa bez nagrody
    if r.wave >= private.pve_progress(p_player) then
      v_reward := private.pve_wave_reward(r.wave);
      perform private.add_loot_pending(p_player, v_reward::bigint[]);
    end if;
  end if;
  update public.pve_wave_runs t
  set status = case when p_won then 'won' else 'lost' end, reward = v_reward, finished_at = now()
  where t.id = r.id;
  return query select case when p_won then 'won' else 'lost' end::text, r.wave, v_reward;
end;
$$;

comment on function public.end_wave(uuid, uuid, boolean) is
  'Koniec fali PvE (#288): nagroda za wygraną falę raz na konto, do castle_loot_pending; ponowienie zwraca zapisany wynik.';

revoke all on function public.begin_wave(uuid, integer) from public, anon, authenticated;
revoke all on function public.end_wave(uuid, uuid, boolean) from public, anon, authenticated;
grant execute on function public.begin_wave(uuid, integer) to service_role;
grant execute on function public.end_wave(uuid, uuid, boolean) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Wyzwalacz zapisu zamku: jak w `*_economy_growth.sql`, bez nagród fal PvE z zapisu telefonu
-- ---------------------------------------------------------------------------------------------

create or replace function private.check_castle_resources()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_problem text;
  v_pending bigint[];
  v_before jsonb;
  v_after jsonb;
  v_applied integer[] := array[0, 0, 0, 0];
  v_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
  v_old jsonb;
  v_elapsed numeric;
  v_new_amounts bigint[];
  v_old_amounts bigint[];
  v_credit bigint[] := array[0, 0, 0, 0];
  v_hide bigint[] := array[0, 0, 0, 0];
  v_prod bigint[];
  v_use bigint[];
  v_build record;
  v_other bigint[];
  v_cap bigint;
  v_spend numeric;
  v_tol numeric;
  v_slack numeric;
  v_hide_tol numeric;
  v_base numeric;
  v_out_credit bigint[] := array[0, 0, 0, 0];
  v_out_hide bigint[] := array[0, 0, 0, 0];
  v_has_old boolean := false;
begin
  -- PUSH_LIMIT = 90 zapisów w 10 minut; odrzucony zapis cofa też licznik
  if tg_op = 'UPDATE' then
    if old.push_window_at is null or old.push_window_at <= now() - interval '10 minutes' then
      new.push_window_at := now();
      new.push_count := 1;
    else
      new.push_window_at := old.push_window_at;
      new.push_count := old.push_count + 1;
      if new.push_count > 90 then
        raise exception 'castle_rate_limited' using errcode = 'PT429';
      end if;
    end if;
  end if;

  -- zapasy z telefonu: kształt i pojemność; złoto sprawdzamy dopiero po scaleniu łupu
  v_problem := private.castle_resources_problem(new.player_id, new.data, new.ruler_perk_paid);
  if v_problem in ('bad_economy', 'over_capacity') then
    raise exception '%', v_problem using errcode = 'PT422';
  end if;

  -- #282: bilans surowców od poprzedniego zapisu, tylko zapisy gracza (serwer pisze stan zaufany).
  -- #288: bez nagród fal PvE: nagrodę za wygraną falę dopisuje `end_wave` do `castle_loot_pending`,
  -- a ta wchodzi niżej, po bilansie, jak łup z ataku. `pve.cleared` z telefonu nic tu nie daje.
  if v_role in ('authenticated', 'anon') then
    v_new_amounts := private.economy_amounts(new.data);
    -- INSERT: kredyt z nowego wiersza, czyli domyślne 0 (klient wstawia tylko player_id, map_seed, save_version i data)
    v_credit := new.economy_credit;
    if tg_op = 'UPDATE' then
      v_old_amounts := private.economy_amounts(old.data);
      v_credit := old.economy_credit;
      v_hide := old.hide_credit;
    end if;
    -- gra zawsze zapisuje `economy`; zamek gracza, który traci zapasy w kolejnym zapisie, nie dałby łupu w PvP.
    -- Pierwszy zapis (INSERT) bez `economy` przechodzi bez bilansu: liczy się od pierwszego zapisu z zapasami.
    if v_new_amounts is null and tg_op = 'UPDATE' then
      raise exception 'economy_missing' using errcode = 'PT422';
    end if;
    if v_new_amounts is not null then
      if v_old_amounts is null then
        -- pierwszy zapis z zapasami: od nowej gry (EconomyConfig.START) i czasu od założenia konta; INSERT_GRACE = 6 godzin
        v_old := private.start_buildings(new.data);
        v_old_amounts := array[500, 300, 300, 50];
        select extract(epoch from now() - p.created_at) * 1000 + 6 * 3600 * 1000 into v_elapsed
        from public.players p where p.id = new.player_id;
        v_elapsed := coalesce(v_elapsed, 6 * 3600 * 1000);
      else
        v_has_old := true;
        v_old := old.data;
        v_elapsed := greatest(extract(epoch from now() - old.updated_at) * 1000, 0);
      end if;
      v_prod := private.production_max(v_old, new.data);
      v_use := private.consumption_max(v_old, new.data);
      select * into v_build from private.build_flow(v_old, new.data);
      v_other := private.other_spend(v_old, new.data);
      v_cap := private.castle_capacity(new.data);
      for i in 1 .. 4 loop
        v_spend := v_build.spend[i] + v_other[i] + case when i = 4 and tg_op = 'UPDATE'
          then 50 * greatest(new.ruler_perk_paid - old.ruler_perk_paid, 0) else 0 end;
        -- przyrost: TOLERANCE = 5 minut produkcji plus ROUND_SLACK = 2 łącznie
        v_tol := v_prod[i] * 5 * 60 * 1000 / 3600000.0 + 2;
        v_slack := v_credit[i] + v_prod[i] * v_elapsed / 3600000.0 + v_build.refund[i]
          - (v_new_amounts[i] - v_old_amounts[i]) - v_spend;
        if v_slack < -v_tol then
          raise exception 'economy_too_fast' using errcode = 'PT422';
        end if;
        v_out_credit[i] := floor(least(v_slack, v_tol))::bigint;
        -- spadek (bez pierwszego zapisu): HIDE_SLACK = [100, 100, 100, 20] plus 5 minut produkcji i zużycia,
        -- odnawiane w godzinę
        if v_has_old then
          v_hide_tol := (v_prod[i] + v_use[i]) * 5 * 60 * 1000 / 3600000.0 + (array[100, 100, 100, 20])[i];
          v_base := case when i < 4 then least(v_old_amounts[i], v_cap) else v_old_amounts[i] end;
          v_slack := v_hide[i] + least(v_hide_tol * v_elapsed / 3600000.0, v_hide_tol)
            + v_new_amounts[i] - (v_base - v_spend - v_use[i] * v_elapsed / 3600000.0);
          if v_slack < -v_hide_tol then
            raise exception 'economy_hidden' using errcode = 'PT422';
          end if;
          v_out_hide[i] := ceil(least(v_slack, 0))::bigint;
        end if;
      end loop;
      new.economy_credit := v_out_credit;
      new.hide_credit := v_out_hide;
    end if;
  end if;

  if new.data ? 'economy' then
    delete from public.castle_loot_pending l where l.player_id = new.player_id returning l.amounts into v_pending;
    if v_pending is not null then
      v_before := new.data -> 'economy' -> 'amounts';
      v_after := private.amounts_with_delta(new.data, v_pending);
      new.data := jsonb_set(new.data, '{economy,amounts}', v_after);
      for i in 0 .. 3 loop
        v_applied[i + 1] := ((v_after ->> i)::numeric - (v_before ->> i)::numeric)::integer;
      end loop;
    end if;
    v_problem := private.castle_resources_problem(new.player_id, new.data, new.ruler_perk_paid);
    if v_problem is not null then
      raise exception '%', v_problem using errcode = 'PT422';
    end if;
  end if;
  new.loot_applied := v_applied;
  return new;
end;
$$;

revoke all on function private.check_castle_resources() from public, anon, authenticated;
