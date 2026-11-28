-- #425 (ADR 0018): porzucony atak z zatwierdzonym planem rozstrzyga serwer.
--
-- `start_attack` oddaje telefonowi `battle_seed`, a bitwa jest deterministyczna. Spreparowany klient mógł policzyć
-- wynik przed bitwą, przegraną porzucić (nowy start porzuca poprzedni atak) i zacząć od nowa z nowym seedem.
-- Przy zamku-bocie porzucenie nic nie kosztowało. Teraz porzucony atak, którego plan serwer już zatwierdził
-- (`launched_at` i `sim_version`: PvP po `launch_attack`, bot po `begin_bot_attack`), idzie do kolejki workera,
-- a jego wynik wchodzi tak, jakby gracz dokończył bitwę: łup, ranking, tarcza, ruiny, punkty PvE i postęp kampanii.
--
-- - Wyzwalacz `attacks_abandon_verify` (BEFORE UPDATE): przejście `started` → `abandoned` takiego ataku ustawia
--   `verification = 'pending'`, gdy tryb jego rodzaju (`verification_mode` dla PvP, `bot_verification_mode`
--   dla botów) to `shadow` albo `enforce`. W `off` porzucenie zostaje po staremu.
-- - Wyzwalacz `attacks_abandon_enqueue` (AFTER UPDATE): wkłada taki atak do kolejki od razu gotowy (nie ma
--   zgłoszonych ruin, na które job by czekał).
-- - `submit_verification`: porzucony atak nie ma wyniku z telefonu, więc zgodny wynik workera to `verified`
--   (a nie `mismatch`, który zawyżałby miernik niezgodności). Atak rozstrzygnięty przez serwer poznać po
--   `claimed_result is null` przy ustawionym `verification`.
-- - `apply_attack_outcome`: przyjmuje też porzucony atak i zamyka go jako `finished` (wynik, łup, `finished_at`)
--   w tym samym update co `outcome_applied_at`. Dzięki temu ranking, punkty PvE, kampania, złoto z łupu, historia
--   obron, powtórki i ruiny działają bez zmian, bo patrzą na `finished`.
-- - Ranking PvP: porzucenie liczy się od razu jako przegrana tylko bez weryfikacji (`verification is null`).
--   Porzucony atak w kolejce dostaje ranking z wyniku workera, a gdy job skończy się `failed` (3 nieudane próby),
--   jako przegrana, jak przed tą migracją.
-- - `claim_verification`: przed wzięciem jobu porzuca ataki w toku starsze niż 10 minut (jak `begin_attack`), żeby
--   porzucony atak trafił do kolejki także wtedy, gdy nikt nie zaczyna nowego ataku.
-- - `requeue_verification` przyjmuje też porzucony atak.
--
-- Ciała funkcji są skopiowane z `20261125211238_attack_verification.sql` (submit_verification) i
-- `20261128090000_bot_verification.sql` (apply_attack_outcome, claim_verification, requeue_verification);
-- zmieniają się tylko miejsca opisane wyżej. Sygnatury i uprawnienia bez zmian. Nowych kolumn i danych o graczu nie ma.

-- ---- porzucony atak z planem do kolejki ----

create function private.attacks_abandon_verify()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status = 'started' and new.status = 'abandoned' and new.verification is null
      and new.launched_at is not null and new.sim_version is not null
      and (case when new.defender_id is not null then private.verification_mode()
        else private.bot_verification_mode() end) in ('shadow', 'enforce') then
    new.verification := 'pending';
    new.claimed_result := null;
  end if;
  return new;
end;
$$;
comment on function private.attacks_abandon_verify() is
  'Porzucony atak z zatwierdzonym planem (#425, ADR 0018) czeka na wynik workera zamiast przepadać bez skutków.';
revoke all on function private.attacks_abandon_verify() from public, anon, authenticated, service_role;

create trigger attacks_abandon_verify
  before update of status on public.attacks
  for each row
  when (old.status = 'started' and new.status = 'abandoned')
  execute function private.attacks_abandon_verify();

create function private.attacks_abandon_enqueue()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- bez zgłoszonych ruin job jest gotowy od razu
  insert into private.attack_verifications (attack_id, not_before) values (new.id, now())
  on conflict (attack_id) do nothing;
  return null;
end;
$$;
comment on function private.attacks_abandon_enqueue() is
  'Wkłada porzucony atak z planem do kolejki weryfikacji (#425, ADR 0018).';
revoke all on function private.attacks_abandon_enqueue() from public, anon, authenticated, service_role;

create trigger attacks_abandon_enqueue
  after update of status on public.attacks
  for each row
  when (old.status = 'started' and new.status = 'abandoned' and new.verification = 'pending')
  execute function private.attacks_abandon_enqueue();

-- ---- ranking PvP: porzucenie w kolejce czeka na wynik workera ----

drop trigger attacks_pvp_rating on public.attacks;
create trigger attacks_pvp_rating
  after update of status, outcome_applied_at, verification on public.attacks
  for each row
  when (new.defender_id is not null and (
    (old.status = 'started' and new.status = 'abandoned' and new.verification is null)
    -- worker nie policzył porzuconego ataku (3 próby): przegrana jak przed #425
    or (old.status = 'abandoned' and new.status = 'abandoned' and old.verification = 'pending'
      and new.verification = 'failed')
    or (old.outcome_applied_at is null and new.outcome_applied_at is not null and new.status = 'finished')))
  execute function private.apply_pvp_rating();

-- ---- wynik workera ----

create or replace function private.submit_verification(p_attack uuid, p_result jsonb)
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
    -- #425: porzucony atak nie ma wyniku z telefonu, więc nie ma z czym się nie zgadzać
    when c is null and a.status = 'abandoned' then 'verified'
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
  -- tryb enforce i porzucony atak: skutki dopiero teraz; w trybie shadow już weszły w end_attack i to nic nie robi
  perform private.apply_attack_outcome(p_attack);
  return v_status;
end;
$$;

create or replace function private.apply_attack_outcome(p_attack uuid)
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
      or a.verification not in ('verified', 'mismatch') or a.status not in ('finished', 'abandoned') then
    return false;
  end if;
  v := a.verified_result;
  v_percent := (v ->> 'percent')::bigint;
  -- łup przed zmianą ataku: wyzwalacz kampanii (#413) podbija bots_beaten dopiero po niej, a powtórka
  -- zdobytego zamku-bota daje mniej łupu
  v_loot := private.attack_loot(a, (v ->> 'won')::boolean, v_percent, v -> 'survivors');

  update public.attacks t set
    -- #425: porzucony atak kończy się wynikiem workera, jakby gracz dokończył bitwę
    status = 'finished',
    finished_at = coalesce(t.finished_at, now()),
    result = jsonb_build_object('won', v -> 'won', 'percent', v -> 'percent', 'stars', v -> 'stars'),
    loot = v_loot,
    -- ruiny ma tylko obrońca-gracz; zamek-bot powstaje z seeda (#99)
    destroyed = case when a.defender_id is null then t.destroyed
      else array(select (x.value #>> '{}')::integer from jsonb_array_elements(v -> 'destroyed_ids') as x) end,
    outcome_applied_at = now()
  where t.id = a.id;

  if v_loot[1] + v_loot[2] + v_loot[3] + v_loot[4] > 0 then
    perform private.add_loot_pending(a.attacker_id,
      array[v_loot[1], v_loot[2], v_loot[3], v_loot[4]]::bigint[]);
    if a.defender_id is not null then
      perform private.add_loot_pending(a.defender_id,
        array[-v_loot[1], -v_loot[2], -v_loot[3], -v_loot[4]]::bigint[]);
    end if;
  end if;
  if a.defender_id is not null and v_percent >= 30 then
    insert into public.shields as s (player_id, until) values (a.defender_id, now() + interval '8 hours')
    on conflict (player_id) do update set until = greatest(s.until, excluded.until);
  end if;
  return true;
end;
$$;

-- ---- kolejka ----

create or replace function private.claim_verification(p_worker text)
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

  -- #425: wygasłe ataki w toku (jak w begin_attack); te z planem trafiają przy tym do kolejki
  update public.attacks t set status = 'abandoned'
  where t.status = 'started' and t.started_at < now() - interval '10 minutes';

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

  -- #413 (ADR 0016): najpierw PvP (w enforce atak blokuje cel), potem zamki-boty; w każdej grupie FIFO
  select v.* into q from private.attack_verifications v
  join public.attacks t on t.id = v.attack_id
  where v.attempts < 3 and (v.leased_until is null or v.leased_until <= now()) and v.not_before <= now()
  order by (t.defender_id is null), v.created_at, v.attack_id
  limit 1
  for update of v skip locked;
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
    'attack_id', a.id, 'id', a.id, 'sim_version', a.sim_version, 'bot_idx', a.bot_idx,
    'map_seed', a.map_seed, 'battle_seed', a.battle_seed,
    'castle', coalesce(a.castle_snapshot - 'scout', '{}'::jsonb), 'defense', coalesce(a.defense_snapshot, '{}'::jsonb),
    'army', a.attacker_army, 'plan', a.orders, 'techs', to_jsonb(coalesce(a.attacker_techs, '{}')),
    'general', a.attacker_general, 'ruler_perk', coalesce(a.attacker_ruler_perk, -1::smallint));
end;
$$;

create or replace function private.requeue_verification(p_attack uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.attacks t set verification = 'pending', verified_result = null, verified_at = null
  -- porzucony atak na gracza po `failed` ma już ranking za przegraną; drugi raz by się zdublował
  where t.id = p_attack and t.verification in ('failed', 'pending')
    and (t.status = 'finished' or (t.status = 'abandoned'
      and (t.defender_id is null or t.verification = 'pending')));
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;
  insert into private.attack_verifications (attack_id) values (p_attack)
  on conflict (attack_id) do update set attempts = 0, leased_until = null, leased_by = null, last_error = null,
    not_before = now();
  update private.attack_verifications v set not_before = now() where v.attack_id = p_attack;
end;
$$;

comment on function private.apply_attack_outcome(uuid) is
  'Skutki ataku z wyniku workera (#284, #413): łup, ranking, tarcza i ruiny (gracz) albo łup, punkty PvE i postęp kampanii (zamek-bot) tylko z verified_result; porzucony atak z planem zamyka jako finished (#425); idempotentna.';
comment on function private.claim_verification(text) is
  'Worker weryfikacji (#284, #413, #425): porzuca wygasłe ataki w toku, potem bierze jeden job z kolejki, najpierw PvP, potem zamki-boty (SKIP LOCKED, lease 5 min, max 3 próby). Tylko dla roli verifier.';
comment on function private.submit_verification(uuid, jsonb) is
  'Worker weryfikacji (#284, #425): wynik przeliczonej bitwy, porównanie z wynikiem telefonu (porzucony atak bez wyniku z telefonu: verified) i skutki ataku. Tylko dla roli verifier.';
