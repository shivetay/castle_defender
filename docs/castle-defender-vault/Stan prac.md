# Stan prac

Aktualizacja: 13.11.2026. Kod: repo `shivetay/castle_defender` (Godot 4.7, GDScript), tickety jako issues w repo z labelkami `mvp` i `v1.0` oraz kamieniami milowymi 0.1 MVP … 1.0 Premiera.

## Wydania

| Wersja | Stan | Co zawiera |
| --- | --- | --- |
| 0.0.1 | wydana | organizacja projektu, CI z debug APK przy każdym pushu, reguły agenta |
| 0.1.0 | wydana | generator terenu 64×64, siatka budowy, kamera z gestami, budynki epoki I (wał, palisada, brama, wieża, chata drwala) z 5 poziomami |
| 0.2.0 | PR #84 czeka na merge | stany zniszczeń, produkcja surowców także w tle, koszty i kolejka budowy, Dwór jako poziom zamku, zapis gry, poprawki bramy, wału i HUD |

## Etapy MVP

**Bieżący etap: 4 (#126), aktualne zadanie: #9 (HUD).**

| Etap | Stan |
| --- | --- |
| 1. Projekt, APK, CI (#123) | gotowy |
| 2. Teren, siatka, kamera (#124) | gotowy |
| 3. Grafika proceduralna i budynki epoki I (#125) | prawie gotowy: otwarte #5 (paleta i prymitywy) |
| 4. Ekonomia, progresja, zapis, HUD (#126) | w toku: gotowe #10, #11, #13; otwarte #9 (teraz), #81, #97 |
| 5. Klasy, produkcja, rekrutacja, badania (#127) | do zrobienia (w tym #12) |
| 6. Symulacja bitwy, donżon, PvE (#128) | do zrobienia |
| 7–14 (#129–#136) | do zrobienia |

Tickety MVP (bez ticketów etapów): 10 zamkniętych z 51. Wersje 0.2–1.0 mają tickety zbiorcze #38, #43, #46, #51, #137. Pełna lista etapów i zadań: [[Plan MVP]].

## Decyzje z 13.11.2026

- Każda epoka ma jednostki w 5 klasach: lekka, ciężka, strzelecka, szybka, specjalna. Rekrutacja zużywa towary z budynków produkcyjnych (Garbarnia dla ciężkich, Łukmistrz i Strzałmistrz dla łuczników, Stajnia dla konnicy). Szczegóły: [[Klasy jednostek i produkcja]].
- Stajnia i Jeździec przechodzą do epoki I (zatwierdzone). Każda klasa ma własny budynek rekrutacji (Koszary, Dom drużyny, Strzelnica, Stajnia) i osobnych wytwórców (Wytwórca zbroi skórzanych, Drzewcarz, Cięciwiarz, Łukmistrz, Strzałmistrz, Rymarz; kowal tylko od epoki III).
- Epoki I–II bez metalu, od III żelazo z Kopalni rudy to główny koszt ciężkich jednostek. Jednostki specjalne mają własne surowce (smoła, zioła, bęben, proch).
- MVP rośnie do 25 budynków i 13 jednostek.
- Każdy gracz ma losowy seed mapy (dziś w kodzie stały seed 1337).
- Tickety odpowiadają całemu vaultowi: każda notatka ma swoje tickety.
- Celem ataku jest zniszczenie albo zdobycie donżonu (od epoki I Wieża grodowa), nie Dworu (#120).
- Drzewko ma 131 technologii: doszły technologie klas, wytwórców i budynków gospodarczych (Chata myśliwego, Pole lnu, Rybak, Węglarz) (#121, #122).
- Praca jest podzielona na 14 etapów MVP z ticketami Etap 1–14.

## Następne kroki

1. Scalić wydanie 0.2.0 (#84).
2. Etap 4: HUD (#9), Dwór przez epoki (#81), losowy seed mapy (#97); z etapu 3 domknąć #5.
3. Etap 5: badania (#12), klasy, towary, wytwórcy i rekrutacja (#87–#91, #119, #122).
4. Etap 6: symulacja bitwy z donżonem jako celem (#14, #120).

Powiązane: [[Plan MVP]], [[Roadmapa do 1.0]], [[Klasy jednostek i produkcja]]
