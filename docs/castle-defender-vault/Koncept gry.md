# Koncept gry

Gra to asynchroniczne PvP. Gracze rozbudowują własne zamki i atakują zamki innych graczy. Gdy jesteś offline, Twój zamek broni się sam według wcześniej ustawionej taktyki. Każdy budynek zmienia wygląd zamku i odblokowuje nowe funkcje, jednostki albo kolejne budynki obronne.

## Pętla rozgrywki
1. **Rozbudowa.** Stawiasz i ulepszasz budynki na siatce. Każdy jest widoczny na zamku ([[Widok zamku]]) i odblokowuje funkcje, [[Jednostki]] albo nowe budynki.
2. **Taktyka obrony.** Na tej samej siatce ustawiasz załogę, pułapki i strefy patroli, priorytety celów wież (np. najpierw taran) oraz zachowanie bramy (zamknięta albo wypad konnicy). Układ zapisuje się na serwerze i broni zamku, gdy jesteś offline.
3. **Wybór celu.** Gra proponuje 3 przeciwników z tej samej epoki i podobnego rankingu ([[ADR/0010-dobor-pvp-tylko-w-tej-samej-epoce|ADR 0010]]); gdy graczy brak, karty uzupełniają zamki-boty. Zamki z aktywną tarczą są pomijane.
4. **Zwiad (opcjonalny).** Przed atakiem wysyłasz zwiadowcę za opłatą. Odsłania część mgły wojny: typy i poziomy budynków w swoim zasięgu, pozycje załogi i część pułapek. Bez zwiadu widzisz tylko zarys murów. Obrońca osłabia zwiad budynkami z [[Zwiad i kontrwywiad]].
5. **Planowanie ataku.** Na siatce wokół zamku ustawiasz oddziały w strefach rozstawienia przy krawędzi mapy. Każdemu oddziałowi przypisujesz manewr z listy zapisanych zadań ([[Manewry i zadania]], np. oskrzydlenie, szturm z drabinami) i ustawiasz jego parametry:
    - **cel:** konkretny budynek, odcinek muru albo strefa,
    - **trasa:** 0–3 punkty pośrednie,
    - **start:** od razu, po X sekundach albo gdy inny oddział wykona swoje zadanie (np. po wybiciu wyłomu),
    - **odwrót:** warunek odwrotu, np. przy 50% strat.
6. **Bitwa (60–180 s).** Symulacja przebiega sama według rozkazów i taktyki obrońcy. Nikt nie steruje bitwą: atak i obrona działają wyłącznie według ustawionych planów, a gracz może ją tylko oglądać. O wyniku decyduje jakość planu i zwiadu.
7. **Wynik.** Celem ataku jest zniszczenie albo zdobycie donżonu (w epoce I Wieży grodowej, w VI Cytadeli), nie Dworu. Zdobycie = piechota atakującego utrzyma wnętrze donżonu przez 10 s bez obrońców. Procent zniszczeń i 0–3 gwiazdki (zdobycie bramy, zniszczenie 50%, zniszczenie lub zdobycie donżonu). Atakujący dostaje łup, do 20% niechronionych surowców, oraz punkty rankingu. Obrońca dostaje powiadomienie, powtórkę bitwy i tarczę na 8–12 h. Budynki odbudowują się same, nie są tracone na stałe.

Oblężenia PvE z falami komputerowych wrogów zostają jako samouczek i dodatkowe źródło surowców.

Klany i sojusze dochodzą dopiero w późniejszych wersjach gry.

Postęp w budowie: [[Progresja budowy]]. Zarabianie: [[Model wydania]].

## Surowce
Drewno, kamień, żywność, złoto; od epoki III żelazo (Kopalnia rudy), od IV proch. Wyposażenie wojska to towary z budynków produkcyjnych: [[Klasy jednostek i produkcja]].

## Kluczowa zasada
Nowe zagrożenia epoki sprawiają, że stara obrona przestaje wystarczać — trzeba ulepszać i przebudowywać, żeby być silniejszym. **Nie niszczymy postępu gracza:** Dwór 5 + wymagane technologie (I → II: trzy, z Obrony, Gospodarki i Ataku) otwierają kolejną epokę; budynki po max poziomie startują w niej od poziomu 1 z zachowanymi bonusami ([[Progresja budowy]], #34).

Powiązane: [[Epoki]], [[Obrona]], [[Backend PvP]]
