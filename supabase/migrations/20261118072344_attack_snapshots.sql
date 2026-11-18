-- Review #196: kopia stanu z chwili startu ataku (przed #25).
--
-- `start_attack` zapisuje w wierszu ataku kopię obrony i zamku obrońcy oraz armię atakującego.
-- `finish_attack` i powtórka (#29) liczą bitwę wyłącznie z tych kopii, więc obrońca nie zmieni
-- ustawienia obrony po rozpoczęciu ataku, a atakujący nie podmieni armii. Kolumny zapisuje tylko
-- serwer (klient nie ma uprawnień do zapisu w `attacks`).

alter table public.attacks
  -- ustawienia obrony obrońcy (defense_layouts.data) z chwili startu
  add column defense_snapshot jsonb check (defense_snapshot is null or jsonb_typeof(defense_snapshot) = 'object'),
  -- zamek obrońcy (castles.data) z chwili startu: budynki, poziomy, załoga
  add column castle_snapshot jsonb check (castle_snapshot is null or jsonb_typeof(castle_snapshot) = 'object'),
  -- armia atakującego (oddziały z planu ataku) z chwili startu
  add column attacker_army jsonb not null default '[]'::jsonb check (jsonb_typeof(attacker_army) = 'array'),
  add constraint attacks_snapshots_size check (
    coalesce(pg_column_size(defense_snapshot), 0) <= 65536
    and coalesce(pg_column_size(castle_snapshot), 0) <= 262144
    and pg_column_size(attacker_army) <= 16384),
  -- atak na gracza zawsze ma kopię jego obrony i zamku (zamek-bot generuje się z seeda)
  add constraint attacks_player_target_snapshots check (
    defender_id is null or (defense_snapshot is not null and castle_snapshot is not null));

comment on column public.attacks.defense_snapshot is 'Kopia defense_layouts.data obrońcy z chwili startu ataku; finish_attack liczy z niej, nie z bieżącego układu.';
comment on column public.attacks.castle_snapshot is 'Kopia castles.data obrońcy z chwili startu ataku.';
comment on column public.attacks.attacker_army is 'Armia atakującego z chwili startu ataku.';

-- Kopie są tylko dla serwera: obrona zawiera pułapki, których atakujący nie widzi (#100, odsłania
-- je zwiad #28), a zamek obrońcy to jego pełny stan gry. Klient czyta z `attacks` tylko kolumny
-- bez kopii (zapytanie musi wymienić kolumny; `select *` dostanie 42501).
revoke select on public.attacks from authenticated;
grant select (id, attacker_id, defender_id, bot_idx, battle_seed, orders, status, result, loot,
  started_at, finished_at, attacker_army) on public.attacks to authenticated;
