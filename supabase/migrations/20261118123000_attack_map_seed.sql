-- #166: seed terenu obrońcy w ataku, osobny od seeda bitwy.
--
-- `start_attack` (#25) zapisuje tu `map_seed` z `castles` albo `bot_castles` i zwraca go
-- atakującemu, żeby odtworzył ten sam teren. Kolumna jest czytelna dla gracza (w przeciwieństwie
-- do kopii obrony z pułapkami). Klient nadal nie zapisuje ataków.

alter table public.attacks
  add column map_seed bigint
    check (map_seed is null or map_seed between 0 and 2147483647);

comment on column public.attacks.map_seed is
  'Seed terenu obrońcy (#166 / #97), osobny od battle_seed; ustawia start_attack.';

-- Po migracji snapshots grant select jest kolumnowy — dopisz map_seed.
revoke select on public.attacks from authenticated;
grant select (id, attacker_id, defender_id, bot_idx, map_seed, battle_seed, orders, status, result, loot,
  started_at, finished_at, attacker_army) on public.attacks to authenticated;
