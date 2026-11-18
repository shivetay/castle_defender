# Otwarte pytania

Pytania projektowe do decyzji właściciela oraz braki względem planu / kodu na `main` (stan na 18.11.2026, gra **0.4.0**). Chronologia wdrożeń: [[Stan prac]].

## Ustalone

- Bitwą nikt nie steruje (działa plan); klany i sojusze w późniejszych wersjach; gra darmowa z dobrowolnymi reklamami.
- **Ile oddziałów w planie ataku?** 3 w epoce I, potem 4 / 5 / 6 / 7 / 8 do epoki VI (wdrożone w `AttackPlan`, 16.11.2026).
- Celem ataku jest donżon (Wieża grodowa od epoki I), nie Dwór (#120).
- Oblężenie i Wyprawa są na karcie Strażnicy; wynik Wyprawy lokalnie z gwiazdkami i łupem (0.4.0).
- Prowadzenie gracza przez 5 fal (#185 / #189) weszło wraz z samouczkiem — ticket #16 można domknąć osobno od onboardingu 1.0 (#57).

## Pytania otwarte

- [ ] Czy obok reklam dodać jednorazowy zakup (pakiet startowy / „wesprzyj twórcę” ze sztandarem)? Ticket sklepu: #174; model reklam: [[Model wydania]].
- [ ] Czy ranking PvP ma sezony z resetem co kilka tygodni? (Roadmapa zakłada sezony od 0.3 / #45 — potwierdzić przed backendem rankingu.)
- [ ] Koszty i czasy badań, produkcji towarów, szkolenia i stawek bitewnych są w kodzie **tymczasowe** — kiedy pierwsza passa balansu (tabele lokalne vs od razu Supabase #56)?
- [ ] Czy Gaszenie pożarów (#20) blokuje zamknięcie etapu 8, dopóki nie ma Studni (#35), czy wystarczy uproszczona wersja bez budynku?
- [ ] Ekran startowy / tryb offline (#177 częściowo: Ustawienia są) — przed pełnym PvP (etap 9) czy razem z kontem Google (#63)?

## Braki (kod / tickety vs vault)

### Domknięcie bieżących etapów

| Brak | Ticket | Uwagi |
| --- | --- | --- |
| Dwór przez epoki + garnizon | #81 | czeka na epokę II i bitwę offline |
| Pełne efekty 34 technologii + blokada epoki II | #12 | drzewko i premie G1/G2 są; reszta efektów i przejście epoki otwarte |
| Dokończenie rekrutacji (konie po bitwie) | #89, #164 | szkolenie i Wojsko działają; powrót koni do zbrojowni nie |
| Część kliencka seeda OK; `castles.map_seed` w schemacie (#196), brak pełnego flow serwera | #97, #166 | atakujący musi dostać ten sam teren z `start_attack` |
| Efekty bitwy bez Studni / gaszenia | #101 | strzały, pył, ogień, dym są; rozprzestrzenianie + gaszenie z #20 |
| Ustawienia obrony: komendant, pełna edycja | #19 | posterunki i część zadań są |
| Gaszenie pożarów | #20 | 4/5 zadań obrony; brakuje gaszenia |
| Backend PvP poza schematem | #21–#27, #131 | migracja + RLS (#196); brak Auth, Edge Functions, doboru, ataku, tarcz |
| Tickety zbiorcze etapów 3–8 | #125–#130 | kod wyprzedza checkboxy w body issues — warto odhaczyć przy domknięciu |

### Zawartość MVP jeszcze niezaczęta / niepełna

| Brak | Ticket | Uwagi |
| --- | --- | --- |
| Pozostałe budynki MVP (Fosa, Kopiec, Pole i spichlerz, Studnia, Kamieniołom, Wieża sygnałowa) | #35 | Dom zwiadowców i Strażnica już są |
| Epoka II i przejście I → II | #34 | |
| Budynki epoki II spoza rdzenia (Pomost, Częstokół, Młyn, Kaplica) | #102 | Dom zwiadowców już w grze |
| Życie w zamku (mieszkańcy, pora dnia) | #36 | dym / ozdoby / cienie weszły w #191 |
| Zwiad z mgłą wojny | #28 | Dom zwiadowców i jednostka są; mgła i PvP-zwiad nie |
| Bitwa PvP na żywo, raport, powtórka | #29 | lokalny wynik Wyprawy (#194 / #99) jest; pełny raport PvP nie |
| Generałowie i perki władcy | #31, #32 | |
| Reklamy z nagrodą | #33 | |
| Obrót kamery | #151 | |

### Świadomie później (po MVP / 1.0)

Epoki III–VI (#93–#96, #103+), sezony i ligi, kampania PvE, osiągnięcia, i18n, zgodność ze sklepem — [[Roadmapa do 1.0]].

Powiązane: [[Koncept gry]], [[Plan MVP]], [[Stan prac]], [[Model wydania]]
