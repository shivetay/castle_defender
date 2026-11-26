-- #328: historia obron gracza z nickiem napastnika.
--
-- `public.defense_history(p_player)` zwraca do 10 ostatnich zakończonych ataków na zamek `p_player`,
-- od najnowszego: id ataku, koniec, wynik z serwera, armię napastnika z chwili startu (z niej klient
-- liczy wskaźnik siły, `Strength.unit_power`), czy atak ma powtórkę (zapisany plan, #29) i nick
-- napastnika. Tabela `players` ma RLS „tylko własny wiersz”, więc nicku nie da się przeczytać przez REST;
-- nick jest i tak publiczny w rankingu i na kartach celów, a funkcja nie oddaje id napastnika
-- ani nazwy jego zamku.
--
-- Funkcję woła wyłącznie serwer: Edge Function `defense_history` z rolą `service_role` i id gracza
-- z jego tokenu. Klient (`anon`, `authenticated`) nie ma prawa jej wykonać, więc nie podstawi cudzego
-- `p_player`. Niczego nie zapisuje.

create function public.defense_history(p_player uuid)
returns table (
  id uuid,
  finished_at timestamptz,
  result jsonb,
  attacker_army jsonb,
  has_replay boolean,
  nickname text
)
language sql
stable
security invoker
set search_path = ''
as $$
  -- HISTORY_LIMIT = 10
  select a.id, a.finished_at, a.result, a.attacker_army, a.orders <> '[]'::jsonb, p.nickname
  from public.attacks a
  left join public.players p on p.id = a.attacker_id
  where p_player is not null
    and a.defender_id = p_player
    and a.status = 'finished'
  order by a.finished_at desc, a.id
  limit 10
$$;

comment on function public.defense_history(uuid) is
  'Historia obron (#328): 10 ostatnich zakończonych ataków na p_player z nickiem napastnika i jego armią. Tylko dla service_role (Edge Function defense_history).';

revoke all on function public.defense_history(uuid) from public, anon, authenticated;
grant execute on function public.defense_history(uuid) to service_role;
