# Otwarte pytania

Pytania projektowe do decyzji właściciela oraz braki względem planu / kodu na `main` (stan na 17.11.2026). Chronologia wdrożeń: [[Stan prac]].

## Ustalone

- Bitwą nikt nie steruje (działa plan); klany i sojusze w późniejszych wersjach; gra darmowa z dobrowolnymi reklamami.
- **Ile oddziałów w planie ataku?** 3 w epoce I, potem 4 / 5 / 6 / 7 / 8 do epoki VI (wdrożone w `AttackPlan`, 16.11.2026).
- Celem ataku jest donżon (Wieża grodowa od epoki I), nie Dwór (#120).

## Pytania otwarte

- [ ] Czy obok reklam dodać jednorazowy zakup (pakiet startowy / „wesprzyj twórcę” ze sztandarem)? Ticket sklepu: #174; model reklam: [[Model wydania]].
- [ ] Czy ranking PvP ma sezony z resetem co kilka tygodni? (Roadmapa zakłada sezony od 0.3 / #45 — potwierdzić przed backendem rankingu.)
- [ ] Koszty i czasy badań, produkcji towarów, szkolenia i stawek bitewnych są w kodzie **tymczasowe** — kiedy pierwsza passa balansu (tabele lokalne vs od razu Supabase #56)?
- [ ] Czy Gaszenie pożarów (#20) blokuje zamknięcie etapu 8, dopóki nie ma Studni (#35), czy wystarczy uproszczona wersja bez budynku?
- [ ] Samouczek PvE (#16): czy 5 fal pod Oblężenie wystarczy do zamknięcia ticketu, a prowadzenie gracza (#185) idzie osobno do etapu 1.0 / onboardingu (#57)?
- [ ] Ekran startowy, tryb offline i widoki gry (#177) — przed PvP (etap 9) czy razem z kontem Google (#63)?

## Braki (kod / tickety vs vault)

### Domknięcie bieżących etapów

| Brak | Ticket | Uwagi |
| --- | --- | --- |
| Dwór przez epoki + garnizon | #81 | czeka na epokę II i bitwę offline |
| Pełne efekty 34 technologii + blokada epoki II | #12 | drzewko i premie G1/G2 są; reszta efektów i przejście epoki otwarte |
| Dokończenie rekrutacji (konie po bitwie) | #89, #164 | szkolenie i Wojsko działają; powrót koni do zbrojowni nie |
| Część kliencka seeda OK, brak `castles.map_seed` | #97, #166 | atakujący musi dostać ten sam teren |
| Prowadzenie gracza do 5 fal | #16, #185 | fale działają; brak soft guidance budynki → badania → wojsko → umocnienia |
| Efekty bitwy bez Studni / gaszenia | #101 | strzały, pył, ogień, dym są; rozprzestrzenianie + gaszenie z #20 |
| Ustawienia obrony: komendant, pełna edycja | #19 | posterunki i część zadań są |
| Gaszenie pożarów | #20 | 4/5 zadań obrony; brakuje gaszenia |
| Tickety zbiorcze etapów 3–8 | #125–#130 | kod wyprzedza checkboxy w body issues — warto odhaczyć przy domknięciu |

### Zawartość MVP jeszcze niezaczęta

| Brak | Ticket |
| --- | --- |
| Pozostałe budynki MVP (Fosa, Kopiec, Pole i spichlerz, Studnia, Kamieniołom, Wieża sygnałowa) | #35 |
| Epoka II i przejście I → II (Dwór 5 + 2 techy; max→lvl1; bez niszczenia postępu) | #34 |
| Budynki epoki II spoza rdzenia (Pomost, Częstokół, Młyn, Kaplica; Dom zwiadowców już jest) | #102 |
| Życie w zamku (mieszkańcy, dym, flagi, pora dnia) | #36 |
| Wynik bitwy: % zniszczeń, gwiazdki, łup, odbudowa | #99 |
| Zwiad z mgłą wojny | #28 |
| Bitwa na żywo, raport, powtórka | #29 |
| Backend PvP (Supabase) | #21–#27, #131 |
| Generałowie i perki władcy | #31, #32 |
| Reklamy z nagrodą | #33 |
| Wygląd: przyklejenie do murów, polish zamku | #149, #150 |
| Obrót kamery | #151 |

### Świadomie później (po MVP / 1.0)

Epoki III–VI (#93–#96, #103+), sezony i ligi, kampania PvE, osiągnięcia, i18n, zgodność ze sklepem — [[Roadmapa do 1.0]].

Powiązane: [[Koncept gry]], [[Plan MVP]], [[Stan prac]], [[Bugs]], [[Model wydania]]
