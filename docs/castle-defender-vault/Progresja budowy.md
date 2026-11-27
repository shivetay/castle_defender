# Progresja budowy

Każdy typ zamku (epoka) ma 5 poziomów Dworu. Przejście do kolejnej epoki wymaga **Dworu na poziomie 5** oraz konkretnych technologii (I → II: **trzy**, po jednej z Obrony, Gospodarki i Ataku). Ticket: #34.

## Zasada projektowa
**Nie niszczymy postępu.** Gracz kontynuuje to, co już ma, i ulepsza, żeby być silniejszym. Przejście epoki nie kasuje zamku, budynków ani zebranych bonusów.

## Zasady
- Poziom zamku = poziom Dworu (siedziba władcy, administracja, garnizon). Dwór zmienia nazwę i wygląd z epoką: Dwór grodowy (I–II) → Dom kasztelana (III–IV) → Dom komendanta (V–VI).
- Osobno stoi **donżon**, ostatnia linia obrony i cel każdego ataku: Wieża grodowa (I) → Wieża na kopcu (II) → Donżon (III–V) → Cytadela (VI). Jego upadek albo zdobycie kończy bitwę zwycięstwem atakującego.
- Każdy budynek ma poziomy 1–5 w ramach bieżącej epoki i nie może mieć wyższego poziomu niż zamek.
- Każdy poziom zmienia wygląd budynku (wyższa wieża, więcej okien, lepszy materiał) i daje premię: wytrzymałość, zasięg, produkcja albo nowa jednostka.
- Koszt i czas to **jedna ciągła krzywa przez poziomy narastająco** (`BuildConfig`, [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]], #262): koszt 100 / 150 / 250 / 400 / 600% kosztu poziomu 1 w epoce I i dalej 850 / 1150 / 1500 / 1950 / 2500% w epoce II; czas ×1 / 3 / 10 / 30 / 90 i dalej ×130 / 180 / 240 / 320 / 420. Na przejściu epoki nic nie tanieje. Umocnienia (wał, palisada, fosa, brama) w epoce II biorą połowę przyrostu krzywej ponad poziom 5 (×110, 135, 165, 205, 255). Kolejne epoki przedłużą krzywą. Liczby epoki II są tymczasowe; szczegóły: [[Balans]].
- Rozmiar mówi o roli budynku: Koszary 3×3; Dom drużyny, Strzelnica, Stajnia, Magazyn, Pole lnu, Pole i spichlerz i Kamieniołom 3×2; reszta 2×2, umocnienia i fosa 1×1, brama 3×1. Budynek postawiony wcześniej zostaje w starym rozmiarze ([[ADR/0005-rozmiary-budynkow|ADR 0005]], #340).
- Technologie są w 5 gałęziach drzewka. Przejście epoki opiera się na konkretnych techach kluczowych ★ (I → II: O1, G1, A7). Pełna lista: [[Drzewko technologiczne]].

## Budynki a epoka
- Budynek przechodzi do kolejnej epoki dopiero po osiągnięciu **max poziomu** (5) w bieżącej epoce.
- Po przejściu epoki progresja tego budynku zaczyna się znowu od **poziomu 1**.
- Bonusy zdobyte w poprzedniej epoce **zostają** — nowa epoka dokłada kolejne ulepszenia, nie zeruje starych. Premie (produkcja, Magazyn, limit armii, wytrzymałość) liczą się z poziomu narastająco do 10 i rosną dalej w epoce II ([[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]).

## Technologie a epoka
- Technologie następnej epoki są dostępne dopiero po odblokowaniu wcześniejszych technologii blokujących / wymaganych (prerequisites w kolumnie „Wymaga” oraz techy kluczowe przejścia).
- Nie da się badać techów z wyższej epoki przed spełnieniem warunków przejścia.

## Przykład: Palisada w epokach I i II (liczby z kodu)

Koszt poziomu 1: 20 Dr i 5 Ży, czas 10 s. W epoce II czas umocnień to połowa przyrostu krzywej ponad poziom 5.

| Poziom | Koszt (drewno) | Czas budowy | Wytrzymałość |
| --- | --- | --- | --- |
| 1 | 20 | 10 s | 100 |
| 2 | 30 | 30 s | 150 |
| 3 | 50 | 1 min 40 s | 220 |
| 4 | 80 | 5 min | 320 |
| 5 | 120 | 15 min | 450 |
| II.1 | 170 | 18 min 20 s | 560 |
| II.2 | 230 | 22 min 30 s | 680 |
| II.3 | 300 | 27 min 30 s | 810 |
| II.4 | 390 | 34 min 10 s | 950 |
| II.5 | 500 | 42 min 30 s | 1100 |

## Typowe czasy budowy (z kodu)

Zwykłe budynki mają czas poziomu 1 od 30 s (Studnia, Pole lnu) do 90 s (Wieża grodowa); Wieża 60 s,
Chata drwala 45 s. Dwór ma własną tabelę.

| Epoka | Poziom 1 | Poziom 5 | Dwór (przejście i poziom 5) |
| --- | --- | --- | --- |
| I. Gród | 30 s – 1 min 30 s | 45 min – 2 h 15 min | Dwór 5: 12 h |
| II. Zamek drewniano-ziemny | 1 h 5 min – 3 h 15 min | 3 h 30 min – 10 h 30 min | przebudowa 14 h, II.5: 40 h |
| III–VI | przedłużenie krzywej, do ustalenia | — | — |

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

Powiązane: [[Epoki]], [[Obrona]], [[Model wydania]], [[Plan MVP]], [[Balans]]
