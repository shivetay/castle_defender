# Progresja budowy

Każdy typ zamku (epoka) ma 5 poziomów Dworu. Przejście do kolejnej epoki wymaga **Dworu na poziomie 5** oraz konkretnych technologii (I → II: **trzy**, po jednej z Obrony, Gospodarki i Ataku). Ticket: #34.

## Zasada projektowa
**Nie niszczymy postępu.** Gracz kontynuuje to, co już ma, i ulepsza, żeby być silniejszym. Przejście epoki nie kasuje zamku, budynków ani zebranych bonusów.

## Zasady
- Poziom zamku = poziom Dworu (siedziba władcy, administracja, garnizon). Dwór zmienia nazwę i wygląd z epoką: Dwór grodowy (I–II) → Dom kasztelana (III–IV) → Dom komendanta (V–VI).
- Osobno stoi **donżon**, ostatnia linia obrony i cel każdego ataku: Wieża grodowa (I) → Wieża na kopcu (II) → Donżon (III–V) → Cytadela (VI). Jego upadek albo zdobycie kończy bitwę zwycięstwem atakującego.
- Każdy budynek ma poziomy 1–5 w ramach bieżącej epoki i nie może mieć wyższego poziomu niż zamek.
- Każdy poziom zmienia wygląd budynku (wyższa wieża, więcej okien, lepszy materiał) i daje premię: wytrzymałość, zasięg, produkcja albo nowa jednostka.
- Koszt rośnie ok. 1,6× na poziom, czas ok. 2× na poziom. Pierwsze budowle są tanie i szybkie, żeby pierwsza sesja dała kilka widocznych zmian w ciągu minut.
- Technologie są w 5 gałęziach drzewka. Przejście epoki opiera się na konkretnych techach kluczowych ★ (I → II: O1, G1, A7). Pełna lista: [[Drzewko technologiczne]].

## Budynki a epoka
- Budynek przechodzi do kolejnej epoki dopiero po osiągnięciu **max poziomu** (5) w bieżącej epoce.
- Po przejściu epoki progresja tego budynku zaczyna się znowu od **poziomu 1**.
- Bonusy zdobyte w poprzedniej epoce **zostają** — nowa epoka dokłada kolejne ulepszenia, nie zeruje starych.

## Technologie a epoka
- Technologie następnej epoki są dostępne dopiero po odblokowaniu wcześniejszych technologii blokujących / wymaganych (prerequisites w kolumnie „Wymaga” oraz techy kluczowe przejścia).
- Nie da się badać techów z wyższej epoki przed spełnieniem warunków przejścia.

## Przykład: Palisada w epoce I

| Poziom | Koszt (drewno) | Czas budowy | Wytrzymałość |
| --- | --- | --- | --- |
| 1 | 20 | 15 s | 100 |
| 2 | 32 | 30 s | 150 |
| 3 | 51 | 1 min | 220 |
| 4 | 82 | 2 min | 320 |
| 5 | 131 | 4 min | 450 |

## Typowe czasy budowy

| Epoka | Poziom 1 | Poziom 5 |
| --- | --- | --- |
| I. Gród | 10 s | 4 min |
| II. Zamek drewniano-ziemny | 2 min | 30 min |
| III. Zamek kamienny | 15 min | 2 h |
| IV. Zamek późnogotycki | 1 h | 6 h |
| V. Fortyfikacja bastionowa | 3 h | 12 h |
| VI. Twierdza napoleońska | 6 h | 24 h |

## Wymagania przejścia

Warunki wspólne dla każdego przejścia: **Dwór poziom 5** + konkretne technologie kluczowe ★ (I → II: **trzy**, po jednej z Obrony, Gospodarki i Ataku). Dawne wymagania „rozbuduj wskazane budynki do X” nie obowiązują — budynki idą własną ścieżką max → lvl 1 w nowej epoce.

| Przejście | Dwór | Technologie | Uwagi |
| --- | --- | --- | --- |
| I → II | 5 | O1 ★ Sypanie kopców + G1 ★ Karczowanie lasu + A7 ★ Strzemię (Obrona, Gospodarka, Atak) | MVP / #34 |
| II → III | 5 | G6 ★ Zaprawa wapienna + druga tech (do dopięcia) | poza MVP |
| III → IV | 5 | A12 ★ Proch strzelniczy + druga tech (do dopięcia) | poza MVP |
| IV → V | 5 | O14 ★ Szkoła włoska + druga tech (do dopięcia) | poza MVP |
| V → VI | 5 | O19 ★ System fortów zewnętrznych + druga tech (do dopięcia) | poza MVP |

Przejście to osobna budowa / przebudowa Dworu, zakończona animacją — bez kasowania osiągnięć. Po poziomie 5 epoki VI zostaje ranking PvP i kosmetyczne warianty zamku.

Powiązane: [[Epoki]], [[Obrona]], [[Model wydania]], [[Plan MVP]]
