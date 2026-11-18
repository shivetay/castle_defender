---
name: supabase-security
description: >
  Zasady bezpieczeństwa bazy Supabase w Castle Defender: RLS na każdej tabeli, jawne GRANT-y (także
  na kolumnach), klucze (tylko publishable w kliencie, nigdy service_role), funkcje SECURITY DEFINER
  w schemacie private, migracje i obowiązkowe testy pgTAP. Użyj przy każdej zmianie w `supabase/`
  (tabela, kolumna, polityka, funkcja, wyzwalacz, Edge Function), przy kodzie klienta, który
  rozmawia z Supabase, i przy wgrywaniu migracji na projekt.
---

# Bezpieczeństwo Supabase

Gra trzyma w Supabase dane graczy (konta, zamki, ataki, nagrody). Klient działa na telefonie
gracza, więc każdy, kto rozpakuje APK, ma klucz publiczny i może wołać API bezpośrednio, z
pominięciem gry. Jedyną ochroną danych są uprawnienia i RLS w bazie oraz logika na serwerze.

Zanim cokolwiek zmienisz, wczytaj też skill `supabase:supabase` (aktualne zasady platformy)
i `supabase:supabase-postgres-best-practices`, jeśli są dostępne.

## Twarde zasady (bez wyjątków)

1. **RLS na każdej tabeli** w schematach wystawionych przez API (`public`). Tabela bez RLS albo
   bez polityk to błąd krytyczny, nawet jeśli „na razie nikt jej nie czyta”.
2. **Uprawnienia jawne i minimalne.** Migracja zawsze robi `revoke all ... from anon, authenticated`,
   a potem `grant` tylko tego, czego klient potrzebuje. Zapis ograniczaj do kolumn
   (`grant update (kolumna) ...`). Kolumny, które ustala serwer (ranking, epoka, `map_seed` po
   założeniu, `revision`, łup, wynik), nie mają grantu dla `authenticated`.
3. **Polityka = rola + właściciel.** `to authenticated` samo w sobie nie autoryzuje (IDOR/BOLA).
   Zawsze `using ((select auth.uid()) = <kolumna_właściciela>)`, a przy UPDATE także
   `with check (...)` z tym samym warunkiem. Pamiętaj, że UPDATE bez polityki SELECT nic nie zmienia.
4. **Konta anonimowe mają rolę `authenticated`.** Nie traktuj „zalogowany” jako „zaufany”.
   Nie używaj `auth.role()`.
5. **Autoryzacja tylko z `auth.uid()` albo `app_metadata`.** Nigdy z `user_metadata` /
   `raw_user_meta_data`, bo gracz może je sam zmienić.
6. **Klucze:** w kliencie (Godot) tylko klucz publishable/`anon`. `service_role`, hasło bazy, tokeny
   Management API i klucze AdMob SSV żyją wyłącznie w sekretach Edge Functions albo w zmiennych
   środowiska, nigdy w repo, w `project.godot`, w eksporcie APK ani w logach.
7. **SECURITY DEFINER** tylko gdy naprawdę trzeba ominąć RLS (np. wyzwalacz na `auth.users`).
   Taka funkcja leży w schemacie `private`, ma `set search_path = ''`, sprawdza `auth.uid()` (jeśli
   wołana przez klienta) i ma `revoke all ... from public, anon, authenticated`. Nigdy nie dodawaj
   SECURITY DEFINER, żeby „naprawić” błąd uprawnień.
8. **Widoki** tylko z `with (security_invoker = true)`; zwykły widok omija RLS.
9. **RPC wołane przez klienta** (`public.*`) mają `security invoker`, walidują argumenty
   i mają `grant execute` tylko dla ról, które ich potrzebują.
10. **Wgrywanie na projekt w chmurze wyłącznie za zgodą właścicielki**, za każdym razem, z nazwą
    projektu. Po wgraniu: `get_advisors` (security i performance) i testy RLS na projekcie
    w transakcji, która się cofa.

## Każda zmiana schematu

1. Nowa migracja w `supabase/migrations/` (nazwa z `supabase migration new` albo wersja z historii
   projektu, gdy migrację wgrano przez MCP). Nigdy nie edytuj migracji już wgranej na projekt;
   zmiana to nowa migracja.
2. W tej samej migracji: tabela, `enable row level security`, `revoke`, `grant`, polityki.
3. Testy w `supabase/tests/database/*.sql` (pgTAP). Dla każdej tabeli co najmniej:
   - właściciel czyta i zapisuje swoje,
   - obcy gracz nie czyta i nie zmienia cudzego (UPDATE trafia w 0 wierszy, dane nietknięte),
   - klient nie zmieni kolumn serwera (`42501`),
   - `anon` nie ma dostępu (chyba że tabela jest celowo publiczna, jak `bot_castles`).
4. Uruchom testy: `supabase test db` albo lokalnie na Postgresie z zaślepką platformy (patrz opis
   PR #196). Bez zielonych testów RLS zmiana nie jest gotowa.
5. Opisz w PR, co klient może, a czego nie, i jak to sprawdzono.

## Edge Functions (serwer)

- Każda funkcja weryfikuje JWT gracza i bierze jego id z tokenu, nigdy z treści żądania.
- Waliduj wejście (typy, zakresy, długości) i odrzucaj nadmiarowe pola.
- Zapisy idempotentne tam, gdzie klient może ponowić żądanie (np. `finish_attack` dla tego samego
  ataku zapisuje wynik raz).
- Błędy zwracaj bez szczegółów bazy; szczegóły tylko do logów serwera (bez danych osobowych).
- Klucz `service_role` tylko z `Deno.env`, nigdy w odpowiedzi.

## Czego unikać

- `grant all on ... to authenticated`, `using (true)` na tabelach z danymi graczy.
- Polityk z warunkiem na `auth.uid() is not null` zamiast na właściciela.
- Logowania tokenów, nagłówków `Authorization`, całych żądań albo danych zamku z identyfikatorem
  konta.
- Wyłączania RLS „na chwilę” w migracji.
