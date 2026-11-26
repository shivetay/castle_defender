-- Czyszczenie nieaktywnych kont gości (#22, skill `user-data-privacy`: zbieramy tylko to, czego gra
-- potrzebuje).
--
-- Każde uruchomienie gry bez zapisanej sesji zakłada nowe konto anonimowe. Gdy gracz odinstaluje grę
-- przed onboardingiem albo telefon zgubi `session.json`, na serwerze zostaje konto „Gracz” bez zamku,
-- którego nikt już nie użyje. Raz na dobę usuwamy takie konta po 7 dniach bez aktywności.
--
-- Konto znika tylko, gdy spełnia wszystkie warunki:
-- - jest anonimowe (`auth.users.is_anonymous`), więc konta z logowaniem (Google, etap 9+) zostają;
-- - nick to domyślny „Gracz” (gracz po onboardingu ma własny nick);
-- - nie ma zamku, obrony, ataków (jako atakujący i obrońca), fal PvE, nagród PvE, zwiadu, tarczy,
--   nagród za reklamy, łupu do scalenia ani szukania przeciwnika, czyli nie rozegrało żadnej gry,
--   którą serwer zna;
-- - ostatnia aktywność (założenie, logowanie, odświeżenie tokenu, zmiana wiersza gracza) jest starsza
--   niż `p_idle`.
-- Usunięcie wiersza z `auth.users` kasuje kaskadą `players` i wszystko, co do niego należy.
-- Klient z usuniętym kontem dostaje przy odświeżeniu `refresh_token_not_found` i zakłada nowe konto
-- (SupabaseClient.refresh_token_dead); zapis gry na telefonie zostaje.

create or replace function private.purge_inactive_guests(
  p_idle interval default interval '7 days',
  p_limit integer default 1000
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count integer;
begin
  if p_idle < interval '1 day' then
    raise exception 'p_idle must be at least 1 day';
  end if;
  with doomed as (
    select u.id
    from auth.users u
    join public.players p on p.id = u.id
    where u.is_anonymous
      and p.nickname = 'Gracz'
      and greatest(
            u.created_at, u.last_sign_in_at, u.updated_at, p.updated_at,
            (select max(s.updated_at) from auth.sessions s where s.user_id = u.id),
            (select max(rt.updated_at) from auth.refresh_tokens rt where rt.user_id = u.id::text)
          ) < now() - p_idle
      and not exists (select 1 from public.castles c where c.player_id = u.id)
      and not exists (select 1 from public.defense_layouts d where d.player_id = u.id)
      and not exists (select 1 from public.attacks a where a.attacker_id = u.id or a.defender_id = u.id)
      and not exists (select 1 from public.pve_wave_runs w where w.player_id = u.id)
      and not exists (select 1 from private.pve_awards pa where pa.player_id = u.id)
      and not exists (select 1 from private.scout_missions m where m.attacker_id = u.id or m.defender_id = u.id)
      and not exists (select 1 from public.shields sh where sh.player_id = u.id)
      and not exists (select 1 from public.ad_rewards ar where ar.player_id = u.id)
      and not exists (select 1 from public.castle_loot_pending lp where lp.player_id = u.id)
      and not exists (select 1 from private.target_searches ts where ts.player_id = u.id)
    order by u.created_at
    limit greatest(p_limit, 0)
  )
  delete from auth.users u using doomed where u.id = doomed.id;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function private.purge_inactive_guests(interval, integer) from public, anon, authenticated, service_role;
comment on function private.purge_inactive_guests(interval, integer) is
  'Usuwa anonimowe konta „Gracz” bez żadnej gry po p_idle bez aktywności (pg_cron, raz na dobę). Zwraca liczbę kont.';

-- Harmonogram: codziennie o 03:23 UTC (poza godzinami szczytu). Nazwa zadania w pg_cron jest unikalna,
-- więc stare zadanie o tej nazwie najpierw znika; migrację da się wtedy bezpiecznie powtórzyć.
create extension if not exists pg_cron with schema pg_catalog;
select cron.unschedule(jobid) from cron.job where jobname = 'purge_inactive_guests';
select cron.schedule('purge_inactive_guests', '23 3 * * *', 'select private.purge_inactive_guests()');
