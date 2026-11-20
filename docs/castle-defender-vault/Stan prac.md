# Stan prac

Aktualizacja: 17.11.2026. Kod: repo `shivetay/castle_defender` (Godot 4.7, GDScript), wersja gry **0.3.0**. Tickety jako issues z labelkami `mvp` / `v1.0` oraz kamieniami milowymi 0.1 MVP … 1.0 Premiera.

## Wydania

| Wersja | Data | Stan | Co zawiera |
| --- | --- | --- | --- |
| 0.0.1 | 13.11.2026 | wydana | organizacja projektu, CI z debug APK, reguły agenta |
| 0.1.0 | 13.11.2026 | wydana | teren 64×64, siatka budowy, kamera, budynki epoki I z 5 poziomami |
| 0.2.0 | 15.11.2026 | wydana | stany zniszczeń, ekonomia w tle, kolejka budowy, Dwór, zapis lokalny, poprawki bramy/wału/HUD |
| 0.3.0 | 16.11.2026 | wydana | badania, towary i wytwórcy, rekrutacja, klasy jednostek, Chłop, panel budowy, zoom 0,5× |
| po 0.3.0 | 16–17.11.2026 | na `main`, bez nowego tagu | bitwa, morale, donżon, samouczek PvE, plan ataku, obrona, pułapki, efekty, Dom zwiadowców |

## Co weszło i kiedy

### 12–13.11.2026 — fundament (etapy 1–4)

- Etap 1–2: projekt Godot, CI, APK; generator terenu, siatka, kamera (#72, #123, #124).
- Etap 3: paleta i prymitywy (#5), autotiling (#6), 5 budynków epoki I (#7), 4 stany zniszczeń (#78 / #8).
- Etap 4: ekonomia także w tle (#79 / #10), koszty i kolejka budowy + Dwór (#80 / #11), zapis lokalny (#83 / #13), HUD z trybem Buduj (#118 / #9).
- Poprawki: brama 3×1 nad drogą (#82), łączenie wału z palisadą (#85), margines zaokrągleń (#86).
- Wydania 0.0.1 i 0.1.0.

### 14–15.11.2026 — vault, seed, badania, produkcja (etap 5)

- Vault Obsidiana w repo (#141).
- Losowy seed mapy po stronie klienta (#138; ticket #97 częściowo, backend #166 otwarty).
- Badania: drzewko 34 technologii + ekran (#139; ticket #12 nadal otwarty — braki efektów / epoki II).
- Towary i łańcuchy (#140 / #88), 9 wytwórców (#142 / #90), Pole lnu i Rybak (#143 / #122), Stajnia (#144 / #91), budynki rekrutacji (#145 / #119), klasy i 13 jednostek MVP (#146 / #87).
- Rekrutacja i ekran Wojsko (#147; ticket #89 częściowo — m.in. #164).
- Wydanie 0.2.0 (#84).

### 16.11.2026 — bitwa i UI (etapy 6–7, wydanie 0.3.0)

- Wydanie 0.3.0 (#161): Chłop (#158), panel budowy z kategoriami (#160), zoom 0,5× (#159), powiązania badań (#157).
- Symulacja bitwy (#148 / #14), donżon / Wieża grodowa (#152 / #120), jednostki w bitwie (#153 / #15), morale (#155 / #98).
- Samouczek PvE: 5 fal pod Oblężenie (#170; ticket #16 częściowo — #185).
- Efekty bitwy (#171; ticket #101 częściowo — m.in. Studnia / gaszenie).
- Zwiadowca i Dom zwiadowców (#172 / część #92).
- Polegli znikają z armii (#173).
- Manewry ataku (#175 / #18), ekran planu ataku (#176 / #17).
- UX: braki surowców na czerwono (#169), brama w linii umocnień (#168), opisy jednostek (#167).

### 17.11.2026 — obrona i pułapki (etap 8)

- Posterunki załogi wokół donżonu (#179; ticket #19 częściowo).
- Zadania obrony: odcinek, patrol, priorytet wież (#181); strzelcy na murach, Wypad, domyślne (#184); ticket #20 częściowo (brak Gaszenia pożarów).
- Wycofanie złamanego oddziału pod donżon (#180).
- Poprawki manewrów po review (#178).
- Ekran Kolejka w zakładkach (#183 / #163).
- Badania wymagają budynku gałęzi (#182 / #165).
- Pułapki: Wilczy dół, Kolczatka, Zrzucane kłody, Płonące strzały, Wrząca smoła (#186 / #100).

## Etapy MVP

**Bieżący etap: 8 (#130).** Następny po domknięciu braków etapu 8: etap 9 Backend Supabase (#131).

| Etap | Stan |
| --- | --- |
| 1. Projekt, APK, CI (#123) | gotowy |
| 2. Teren, siatka, kamera (#124) | gotowy |
| 3. Grafika i budynki epoki I (#125) | kod gotowy (#5–#8); otwarte #149, #150 (wygląd) |
| 4. Ekonomia, progresja, zapis, HUD (#126) | prawie: otwarte #81 (Dwór przez epoki), #97 (reszta / backend seeda → #166) |
| 5. Klasy, produkcja, rekrutacja, badania (#127) | prawie: otwarte #12 (pełne efekty / epoka II), #89 (dokończenie, #164) |
| 6. Bitwa, jednostki, PvE (#128) | prawie: otwarte #16 (+ #185), #101 (dokończenie efektów) |
| 7. Plan ataku i manewry (#129) | gotowy w kodzie (#17, #18) — ticket zbiorczy jeszcze otwarty |
| 8. Obrona, zadania, pułapki (#130) | w toku: #100 gotowe; #19 i #20 częściowo |
| 9–14 (#131–#136) | do zrobienia |

Pełna lista etapów: [[Plan MVP]]. Pytania i braki: [[Otwarte pytania]]. Niedawne bugi UX: [[Bugs]].

## Decyzje (narosłe)

### 13.11.2026

- 5 klas jednostek; rekrutacja zużywa towary; Stajnia i Jeździec w epoce I; od III żelazo.
- MVP: 25+ budynków i 13 jednostek; losowy seed mapy; celem ataku jest donżon (#120).
- Drzewko: 131 technologii łącznie, 34 w MVP; praca w 14 etapach.

### Od 16.11.2026 (z kodu)

- Limit oddziałów w planie ataku: **3 w epoce I … 8 w epoce VI** (`AttackPlan.MAX_SQUADS_BY_AGE`) — zamyka pytanie z [[Otwarte pytania]].
- Bitwą nikt nie steruje; plan i zadania obrony wykonują się same.

### 20.11.2026 — przejście epoki (#34)

- Wejście w kolejną epokę: preferencyjnie **dwie** konkretne technologie **oraz** Dwór **poziom 5** (bez starych wymagań Wał/Palisada jako warunku przejścia).
- Techy następnej epoki tylko po odblokowaniu prerequisite / blokujących.
- Budynki: max poziom → w nowej epoce od poziomu 1, z zachowaniem bonusów; **nie niszczymy postępu**.
- Vault: [[Epoki]], [[Progresja budowy]]; issue: #34.

## Następne kroki

1. Domknąć etap 8: komendant i pełne ustawienia obrony (#19), Gaszenie pożarów + Studnia (#20 / #35).
2. Domknąć resztki 4–6: #81, #12, #89/#164, #16/#185, #101.
3. Etap 9: Supabase i PvP (#131, #21–#27); seed mapy po stronie serwera (#166).
4. Potem zwiad, wynik bitwy, generałowie, reklamy, epoka II (#132–#135).

Powiązane: [[Plan MVP]], [[Roadmapa do 1.0]], [[Otwarte pytania]], [[Klasy jednostek i produkcja]]
