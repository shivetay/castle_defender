# ADR 0005: Wymuszenie aktualizacji wersji klienta

- **Status:** przyjęty
- **Data:** 2026-11-26
- **Issue:** #336

## Kontekst

Po każdym wydaniu część graczy zostaje na starej wersji APK. Stary klient rozmawia z serwerem,
który mógł się już zmienić (np. `bad_plan` po #29), i gra na zasadach, których nowa wersja już
nie ma. Właścicielka chce poinformować gracza o nowej wersji, odesłać go do sklepu i ograniczyć
grę na wersji starszej niż aktualna. Klient dotąd nie wysyłał serwerowi swojej wersji, a wersje
sprzed tej decyzji nie mają w kodzie żadnego sprawdzania.

## Decyzja

- Progi trzyma Supabase w tabeli `public.client_versions` (jeden wiersz): `min_code` (twarda
  blokada), `recommended_code` (miękki komunikat) i `store_url`. Progi są publiczne z założenia:
  RLS daje anon i authenticated tylko SELECT na tych trzech kolumnach, a klient czyta je przez
  `public.client_version_policy()` (SECURITY INVOKER). Zapisu nie ma nikt poza właścicielem tabeli,
  więc zmienia je właścicielka w SQL Editorze.
- Wersję porównujemy jako kod `MAJOR*10000 + MINOR*100 + PATCH` z `config/version`.
- Kod < `recommended_code`: okienko „Dostępna nowa wersja” z przyciskami Aktualizuj i Później,
  najwyżej raz na 24 h dla danej wersji. Gra działa dalej.
- Kod < `min_code`: pełny ekran blokady z przyciskami Aktualizuj i Sprawdź ponownie. Blokada obejmuje całą grę,
  także tryb offline.
- Gra sprawdza wersję przy starcie i po powrocie z tła, gdy od ostatniego sprawdzenia minęła godzina.
  Bez sieci działa fail-open, ale z zapamiętaną polityką w `user://version_policy.json`: jeśli ostatnia
  pobrana polityka każe blokować, gra blokuje też offline.
- Link do sklepu: `store_url` z serwera, domyślnie `market://details?id=com.shivetay.dunhold`,
  a gdy nie da się go otworzyć, strona https Google Play.
- Klient wysyła nagłówek `X-Client-Version` w każdym zapytaniu do Supabase. Edge Functions odpowiadają
  `426` z `{"error":"update_required"}`, gdy wersja < `min_code` albo nagłówka brak (brak = 0).
  Zapisy do `castles`, `defense_layouts` i `players` odrzuca wyzwalacz z tym samym błędem. Klient na
  `update_required` od razu pokazuje ekran blokady.
- Przy wydaniu `recommended_code` rośnie od razu po publikacji w Play, a `min_code` właścicielka
  podnosi, gdy wersja jest dostępna dla wszystkich (standardowo 48 h po publikacji). Wartości startowe to 0 i 0.
- Buildy zostają w istniejącym workflow `release.yml`. Nowego workflow nie ma.

## Rozważane opcje

- **Polityka w Supabase + blokada w kliencie i na serwerze** (wybrana): jedno źródło progów,
  zmiana bez nowego APK, a serwer zatrzymuje też wersje sprzed tej decyzji.
- **Plik JSON w GitHub Release**: odrzucony, bo to druga usługa w ścieżce startu, a serwer gry
  i tak musi znać próg, żeby odrzucać stare klienty.
- **Play In-App Updates (plugin Androida)**: odrzucony na teraz, bo to nowa zależność i build gradle
  z pluginem. Może wrócić osobnym ticketem jako wygodniejszy przycisk Aktualizuj.
- **Twarda blokada od chwili wydania**: odrzucona, bo Play udostępnia wersję z opóźnieniem i gracz
  utknąłby bez dostępnej aktualizacji.
- **Blokada tylko w kliencie**: odrzucona, bo nie zatrzyma APK sprzed tej decyzji.

## Konsekwencje

- Gracz ze starą wersją po podniesieniu `min_code` nie zagra ani online, ani (z nowym kodem) offline.
- Nagłówek wersji da się podrobić: to bariera dla zwykłego starego APK, a nie zabezpieczenie przed
  oszustem. Wynik ataku nadal chroni weryfikacja powtórki na serwerze.
- Klient nie wysyła nowych danych o graczu. Numer wersji gry nie jest daną osobową.
- Migracja i nowe Edge Functions muszą trafić na projekt przed nowym APK (`docs/PO-WYDANIU.md`).
- Zły próg (np. `min_code` wyższy niż wersja w sklepie) blokuje wszystkich. Rollback: obniżyć `min_code` w SQL Editorze.

## Dotknięte notatki

- [[Backend PvP]]: wiersz „Wersja klienta”.
- [[Otwarte pytania]]: ustalenie w „Ustalone”.
