# ADR: decyzje projektowe

Każda decyzja trudna do odwrócenia albo zmieniająca projekt gry ma tu swój plik
`NNNN-krotki-opis.md`. Zapisuje go i aktualizuje dotknięte notatki skill `adr`
(`.claude/skills/adr/SKILL.md`). Przyjętego ADR-a się nie przepisuje: nowa decyzja dostaje nowy
numer, a stary zmienia tylko status na „zastąpiony przez”.

| Nr | Decyzja | Status | Issue |
|---|---|---|---|
| [[ADR/0001-grillowanie-i-adr-w-pracy-z-ai\|0001]] | Grillowanie i ADR w pracy z AI | przyjęty | brak |
| [[ADR/0002-perki-wladcy-z-technologii\|0002]] | Perki władcy z technologii zamiast wyboru z listy | przyjęty | #308 |
| [[ADR/0003-historia-obron-z-nickiem-i-sila-napastnika\|0003]] | Historia obron z nickiem atakującego i siłą jego armii | przyjęty | #328 |
| [[ADR/0004-sila-celu-pvp-przedzial-z-serwera\|0004]] | Siła celu PvP jako przedział liczony przez serwer | przyjęty | #293 |
| [[ADR/0005-rozmiary-budynkow\|0005]] | Różne rozmiary budynków, stare budynki w zapisanym obrysie | przyjęty | #340 |
| [[ADR/0006-wymuszenie-aktualizacji-wersji-klienta\|0006]] | Wymuszenie aktualizacji wersji klienta | przyjęty | #336 |
| [[ADR/0007-strefa-obrony-z-dworu-i-technologii\|0007]] | Strefa obrony rośnie z Dworem i technologią O25 | przyjęty | #342 |
| [[ADR/0008-wersja-symulacji-ataku-z-klienta\|0008]] | Atak PvP tylko z wersją symulacji wspieraną na serwerze | przyjęty | #354 |
| [[ADR/0009-model-balansu-epok-ciagla-krzywa\|0009]] | Model balansu epok: ciągła krzywa kosztu i czasu, premie do poziomu 10 | przyjęty | #262 |
| [[ADR/0010-dobor-pvp-tylko-w-tej-samej-epoce\|0010]] | Dobór PvP, zwiad i atak tylko w tej samej epoce | przyjęty | #383 |
| [[ADR/0011-budynki-epoki-ii-od-poziomu-6\|0011]] | Budynki epoki II startują od poziomu 6, pierwszy Młyn | przyjęty | #102 |
| [[ADR/0012-premie-szkolenia-fosy-i-kopca-w-epoce-ii\|0012]] | Premie szkolenia, kolców w fosie i Kopca w epoce II | przyjęty | #387 |

Numeracja: przy merge #395 i #396 oba PR-y chciały **0010**. Na `main` zostało: **0010** = same-age PvP (#395), **0011** = Młyn / budynki od poz. 6 (#396).
