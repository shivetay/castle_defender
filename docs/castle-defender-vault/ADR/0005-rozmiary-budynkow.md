# ADR 0005: Różne rozmiary budynków, stare budynki w zapisanym obrysie

- **Status:** przyjęty
- **Data:** 2026-11-26
- **Issue:** #340

## Kontekst

Prawie wszystkie budynki epoki I zajmowały 2×2 kratki (`BuildingTypes.SIZES`). Wyjątkami były umocnienia
i fosa (1×1) oraz brama (3×1). Koszary wyglądały tak samo duże jak Chata drwala, więc rozmiar nie mówił nic
o roli budynku. Zapis gry, kopie zamku do PvP i powtórki trzymają pełny prostokąt każdego budynku
(x, y, szerokość, wysokość), a `BuildGrid.load_data` przyjmuje go, jeśli kratki są wolne. Rysunki chat
i warsztatów miały współrzędne wpisane na sztywno pod 16×16 px.

## Decyzja

1. Rozmiary (tylko powiększenia):
   - **3×3**: Koszary;
   - **3×2** (poziomo): Dom drużyny, Strzelnica, Stajnia, Magazyn, Pole lnu, Pole i spichlerz, Kamieniołom;
   - **2×2** bez zmian: Wieża drewniana, Chata drwala, Chata myśliwego, wszyscy wytwórcy, Rybak, Studnia,
     Kopiec, Chata tropicieli, Komenda umocnień, Wieża sygnałowa;
   - bez zmian: wał, palisada, fosa sucha (1×1), brama (3×1).
2. Dwór, donżon i Strażnica zostają 2×2. Ewentualne powiększenie Dworu to osobny ticket.
3. Budynki 3×2 mają stałą orientację poziomą. Obracanie do 2×3 to osobny ticket (#368).
4. Bez migracji zapisów: budynek postawiony przed zmianą zostaje w zapisanym prostokącie. Kolizja i rysunek
   biorą się z prostokątu (`BuildGrid.cells_of`), a nowy rozmiar dotyczy tylko nowych budowli.
5. Rysunki chat, warsztatów, wojska, gospodarki i pól układają się według rozmiaru obrazu. Rysunek 2×2
   wygląda piksel w piksel jak przed zmianą (suma kontrolna w `test_building_sizes`).
6. HP, koszty i czasy budowy się nie zmieniają, zmienia się tylko rozmiar. Boty stawiają te same budynki co dotąd.

## Rozważane opcje

- **Stare budynki w zapisanym obrysie** (wybrana): żaden zamek się nie psuje, a kopie zamków na serwerze
  i powtórki dalej liczą tę samą bitwę.
- **Migracja przy wczytaniu** (powiększenie, jeśli obok jest miejsce): odrzucona, bo po aktualizacji gracz
  miałby inny układ obrony, a część budynków i tak zostałaby 2×2.
- **Zmniejszenie małych budynków** (np. Studnia 1×1): odrzucone na teraz, bo zmienia już stojące zamki
  i ich rysunki.
- **Powiększenie Dworu i donżonu**: odłożone, bo zmienia układ startowy, cel PvP i pierścień murów botów.

## Konsekwencje

- Koszary i budynki 3×2 zajmują więcej miejsca w strefie obrony, więc gęsta zabudowa wymaga więcej terenu.
  Układy botów się przesuwają (inne położenie budynków), a ich skład zostaje.
- Ten sam rodzaj może mieć dwa rozmiary (stary i nowy). Cache tekstur rozróżnia je po obrysie.
- Serwer nadal nie sprawdza rozmiarów budynków w kopii zamku. To istniejąca luka, nie skutek tej decyzji.
- Dalej: obracanie 3×2 (#368), ewentualnie Dwór większy od zwykłych budynków.

## Dotknięte notatki

- [[Progresja budowy]]: nowa zasada o rozmiarach budynków.
- [[Otwarte pytania]]: wpis w „Ustalone”.
