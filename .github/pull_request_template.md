## Co

<!-- Co się zmienia z perspektywy gracza albo procesu. Tytuł PR to wpis w changelogu (po polsku, krótko). -->

## Jak sprawdzone

- [ ] `bash .github/scripts/run_checks.sh` zielone
<!-- Testy, zrzuty, pomiary. Czego nie dało się sprawdzić (telefon, APK, projekt w chmurze). -->

## Bezpieczeństwo

<!-- Obowiązkowe, gdy diff dotyka supabase/, kodu sieciowego, zapisu gry, logowania, CI albo
     export_presets.cfg (skill `security-review`). W pozostałych PR wystarczy „nie dotyczy”. -->

- [ ] Brak sekretów w diffie (klucze, hasła, keystore, `.env`, tokeny)
- [ ] Nowe tabele/polityki: RLS, minimalne granty, testy pgTAP (właściciel tak, obcy nie)
- [ ] Wynik, łup, ranking, tarcze i nagrody liczy albo weryfikuje serwer
- [ ] Nowe dane o graczu opisane niżej i kasowane razem z kontem; brak danych osobowych w logach
- [ ] Migracja wgrana na projekt Supabase: nie / tak, na projekt …, za zgodą właścicielki

Co klient może, a czego nie (i jak to sprawdzono):

## Powiązane

<!-- Closes #N tylko wtedy, gdy merge domyka issue. Zależność od niescalonej gałęzi. -->
