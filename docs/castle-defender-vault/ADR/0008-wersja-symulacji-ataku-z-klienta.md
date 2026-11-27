# ADR 0008: Atak PvP tylko z wersją symulacji wspieraną na serwerze

- **Status:** przyjęty
- **Data:** 2026-11-27
- **Issue:** #354

## Kontekst

Worker weryfikacji ataków (#284) liczy każdy atak packiem `verify_<sim_version>.pck`. `sim_version`
ataku ustawia `public.launch_attack` przez `private.checked_sim_version(p_sim_version)`. Klient
i Edge Function `launch_attack` tego parametru nie podawały, więc serwer przypisywał każdemu atakowi
najwyższą wersję z `private.sim_versions`, a nie wersję gry na telefonie. Nowy klient przed wpisem
wersji był liczony starym packiem, a stary klient po wpisie nowym. W trybie `shadow` daje to fałszywe
`mismatch`, a w `enforce` niesłuszny wynik. Na VPS przy 0.6.0 skończyło się to `FileNotFoundError`
(#306).

## Decyzja

- Klient wysyła w treści żądania `launch_attack` pole `sim_version` =
  `VerifyJob.project_sim_version()` (`MAJOR*10000 + MINOR*100 + PATCH` z `project.godot`).
- Edge Function przyjmuje `sim_version` jako liczbę całkowitą `1..999999`, inaczej odpowiada
  400 `bad_sim_version`, i przekazuje ją jako `p_sim_version`. Brak pola działa jak dotąd: serwer
  bierze najwyższą wspieraną wersję (starsze klienty).
- Wersja spoza `private.sim_versions` albo z `supported = false` blokuje atak: 409
  `unsupported_version`. Klient pokazuje komunikat, że trzeba zaktualizować grę. Reszta gry działa,
  to nie jest ekran blokady z ADR 0006.
- Starsze wspierane wersje mogą atakować. Odcina się je wpisem `supported = false` w
  `private.sim_versions` albo podniesieniem `min_code` ([[ADR/0006-wymuszenie-aktualizacji-wersji-klienta|ADR 0006]]).
  Nowego mechanizmu „ostatnich N wydań” nie ma.

## Rozważane opcje

- **Pole `sim_version` w treści żądania** (wybrana): jawne, sprawdzane przez `ALLOWED_KEYS`
  i widoczne w teście klienta.
- **Wersja z nagłówka `X-Client-Version`**: odrzucona, bo miesza wersję aplikacji z wyborem packa.
- **Puszczanie ataku z wersją null (bez weryfikacji)**: odrzucone, bo to furtka do ataków bez
  sprawdzenia wyniku.
- **Ograniczenie do ostatnich N wydań**: odrzucone na teraz, bo `supported = false` i `min_code`
  już na to pozwalają.
- **Porównanie `sim_version` z nagłówkiem wersji**: odrzucone, bo oba da się podrobić.

## Konsekwencje

- Wpis wersji w `private.sim_versions` decyduje, które wersje klienta mogą atakować. Przy wydaniu
  pack i wpis muszą być na serwerze przed APK (`docs/PO-WYDANIU.md`, krok 3.3).
- Oszust może wybrać starszą wspieraną wersję. Wynik nadal liczy worker tym packiem, więc wybiera
  tylko zasady symulacji spośród wersji, które właścicielka zostawiła włączone.
- Bez nowej migracji i bez nowych danych o graczu.

## Dotknięte notatki

- [[Backend PvP]]: wersja symulacji ataku z klienta.
- [[Otwarte pytania]]: wpis w „Ustalone”.
