-- Poziomy doktryn ataku A1 i A2.
--
-- A1 Hartowane topory i A2 Łuk kompozytowy dołączają do doktryn z poziomami (TechTree.LEVELED_DOCTRINES):
--   LEVELED = ["A1", "A2", "G1", "G2"].
-- Walidacja zapisu, koszt i czas poziomów działają jak dla G1 i G2 (`*_doctrine_levels.sql`). W bitwie każdy
-- poziom ponad pierwszy dodaje 5 punktów procentowych (Battle.doctrine_percent): A1 115 → 120 → 125 procent
-- obrażeń toporów w drewno, A2 120 → 125 → 130 procent zasięgu łuków.
--
-- Poziom atakującego bierze serwer z jego zamku przy zatwierdzeniu planu (`launch_attack`), jak samo
-- zbadanie, i zapisuje go w `attacks.attacker_techs` jako dodatkowy wpis „A1:3” (tylko poziomy od 2).
-- Kształt kolumny i odpowiedzi (`text[]`) się nie zmienia, więc Edge Functions, `attack_replay`
-- i kolejka weryfikacji (`claim_verification`) oddają poziomy bez zmian. Klient starszej wersji
-- pomija nieznane wpisy (AttackLaunch.parse_techs) i liczy bitwę po swojej wersji symulacji
-- (`sim_version`), więc weryfikacja tej wersji dalej się zgadza.
-- Liczby pilnuje test gry (`tests/test_doctrine_levels_server.gd`) po znacznikach w komentarzach.

-- Doktryny z poziomami (TechTree.LEVELED_DOCTRINES).
create or replace function private.research_leveled()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['A1', 'A2', 'G1', 'G2']::text[]
$$;

-- Badania atakującego w bitwie: kody A1, A2, A7 i poziomy A1/A2 od 2 do 5, najwyżej 5 wpisów (3 kody i 2 poziomy).
alter table public.attacks drop constraint attacks_attacker_techs_check;
alter table public.attacks add constraint attacks_attacker_techs_check
  check (attacker_techs is null or (cardinality(attacker_techs) <= 5
    and attacker_techs <@ array['A1', 'A2', 'A7', 'A1:2', 'A1:3', 'A1:4', 'A1:5',
      'A2:2', 'A2:3', 'A2:4', 'A2:5']::text[]));

comment on column public.attacks.attacker_techs is
  'Badania atakującego działające w bitwie (A1, A2, A7) i poziomy doktryn ataku od 2 („A1:3”) z jego zamku na serwerze w chwili zatwierdzenia planu (#29). Tylko dla serwera.';

-- launch_attack jak w `*_attack_verification.sql`, z poziomami doktryn ataku w `techs`.
create or replace function public.launch_attack(p_attacker uuid, p_attack uuid, p_plan jsonb, p_general integer,
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
      where jsonb_typeof(v_done) = 'array' and v_done @> jsonb_build_array(code))
      -- poziomy doktryn ataku od 2 jako „A1:3” (sprawdzone przy zapisie zamku, castle_research_problem)
      || array(
        select code || ':' || private.tech_level(v_data, code) from unnest(array['A1', 'A2']) as code
        where private.tech_level(v_data, code) >= 2);
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
revoke all on function private.research_leveled() from public, anon, authenticated;
