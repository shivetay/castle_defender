# Stan prac

Aktualizacja: 18.11.2026. Kod: repo `shivetay/castle_defender` (Godot 4.7, GDScript), wersja gry **0.4.0**. Tickety jako issues z labelkami `mvp` / `v1.0` oraz kamieniami milowymi 0.1 MVP … 1.0 Premiera.

## Wydania

| Wersja | Data | Stan | Co zawiera |
| --- | --- | --- | --- |
| 0.0.1 | 13.11.2026 | wydana | organizacja projektu, CI z debug APK, reguły agenta |
| 0.1.0 | 13.11.2026 | wydana | teren 64×64, siatka budowy, kamera, budynki epoki I z 5 poziomami |
| 0.2.0 | 15.11.2026 | wydana | stany zniszczeń, ekonomia w tle, kolejka budowy, Dwór, zapis lokalny, poprawki bramy/wału/HUD |
| 0.3.0 | 16.11.2026 | wydana | badania, towary i wytwórcy, rekrutacja, klasy jednostek, Chłop, panel budowy, zoom 0,5× |
| 0.4.0 | 17.11.2026 | wydana | bitwa, morale, donżon, Oblężenie i Wyprawa (Strażnica), plan ataku, obrona, pułapki, wynik z gwiazdkami, polish zamku |

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
- Samouczek PvE: 5 fal pod Oblężenie (#170; ticket #16).
- Efekty bitwy (#171; ticket #101 częściowo — m.in. Studnia / gaszenie).
- Zwiadowca i Dom zwiadowców (#172 / część #92).
- Polegli znikają z armii (#173).
- Manewry ataku (#175 / #18), ekran planu ataku (#176 / #17).
- UX: braki surowców na czerwono (#169), brama w linii umocnień (#168), opisy jednostek (#167).

### 17.11.2026 — obrona, PvE i wydanie 0.4.0 (etap 8 + domknięcie 6–7)

- Posterunki załogi wokół donżonu (#179; ticket #19 częściowo).
- Zadania obrony: odcinek, patrol, priorytet wież (#181); strzelcy na murach, Wypad, domyślne (#184); ticket #20 częściowo (brak Gaszenia pożarów).
- Wycofanie złamanego oddziału pod donżon (#180).
- Poprawki manewrów po review (#178).
- Ekran Kolejka w zakładkach (#183 / #163).
- Badania wymagają budynku gałęzi (#182 / #165); badania działają w bitwie, manewry wymagają technologii (#187).
- Pułapki: Wilczy dół, Kolczatka, Zrzucane kłody, Płonące strzały, Wrząca smoła (#186 / #100).
- Prowadzenie gracza przez 5 fal samouczka (#189 / #185).
- Budynki przyklejają się do murów (#190 / #149); żywszy zamek: zbocza, ozdoby, cienie, dym, wąska kolumna HUD (#191 / #150).
- Strażnica: Oblężenie i Wyprawa oraz Ustawienia pod zębatką (#192 / #177).
- 20 zamków-botów z wyborem celu Wyprawy (#193 / #26).
- Wynik ataku: gwiazdki, % zniszczeń, łup (#194 / #99).
- Wydanie 0.4.0 (#195).

### 18.11.2026 — po 0.4.0 na `main` (start etapu 9)

- Schemat PvP w Supabase z RLS (#196 / #21); seed mapy w `castles.map_seed`, lista 20 botów.
- Skille bezpieczeństwa, zasady review i reguły Cursora (#197).

## Etapy MVP

**Bieżący etap: 9 (#131) — zaczęty schemat bazy.** Etap 8 prawie domknięty (braki: komendant / pełna edycja #19, Gaszenie #20).

| Etap | Stan |
| --- | --- |
| 1. Projekt, APK, CI (#123) | gotowy |
| 2. Teren, siatka, kamera (#124) | gotowy |
| 3. Grafika i budynki epoki I (#125) | kod gotowy (#5–#8); #149 i #150 w dużej mierze w 0.4.0 |
| 4. Ekonomia, progresja, zapis, HUD (#126) | prawie: otwarte #81 (Dwór przez epoki), #97 (reszta / backend seeda → #166) |
| 5. Klasy, produkcja, rekrutacja, badania (#127) | prawie: otwarte #12 (pełne efekty / epoka II), #89 (dokończenie, #164) |
| 6. Bitwa, jednostki, PvE (#128) | prawie: fale + prowadzenie (#170, #189); otwarte #101 (dokończenie efektów / gaszenie) |
| 7. Plan ataku i manewry (#129) | gotowy w kodzie (#17, #18) — ticket zbiorczy jeszcze otwarty |
| 8. Obrona, zadania, pułapki (#130) | prawie: #100 gotowe; #19 i #20 częściowo |
| 9. Backend Supabase (#131) | w toku: schemat (#196 / #21); brak Auth, Edge Functions, doboru, ataku |
| 10–14 (#132–#136) | do zrobienia; wynik Wyprawy (#99) już lokalnie, PvP raport/powtórka (#29) później |

Pełna lista etapów: [[Plan MVP]]. Pytania i braki: [[Otwarte pytania]].

## Decyzje (narosłe)

### 13.11.2026

- 5 klas jednostek; rekrutacja zużywa towary; Stajnia i Jeździec w epoce I; od III żelazo.
- MVP: 25+ budynków i 13 jednostek; losowy seed mapy; celem ataku jest donżon (#120).
- Drzewko: 131 technologii łącznie, 34 w MVP; praca w 14 etapach.

### Od 16.11.2026 (z kodu)

- Limit oddziałów w planie ataku: **3 w epoce I … 8 w epoce VI** (`AttackPlan.MAX_SQUADS_BY_AGE`) — zamyka pytanie z [[Otwarte pytania]].
- Bitwą nikt nie steruje; plan i zadania obrony wykonują się same.

### Od 17.11.2026 (z kodu)

- Oblężenie i Wyprawa są na karcie **Strażnicy** (nie osobnym przyciskiem HUD); Strażnica ma jeden poziom i nie da się jej rozebrać.
- 20 wspólnych zamków-botów do Wyprawy; wynik lokalny z gwiazdkami i łupem przed prawdziwym PvP.

## Następne kroki

1. Domknąć etap 8: komendant i pełne ustawienia obrony (#19), Gaszenie pożarów + Studnia (#20 / #35).
2. Domknąć resztki 4–6: #81, #12, #89/#164, #101.
3. Etap 9: Auth anonimowe (#22), zapis zamku (#23), dobór (#24), `start_attack` / `finish_attack` (#25), tarcze (#27); seed mapy po stronie serwera (#166).
4. Potem zwiad z mgłą (#28), raport i powtórka PvP (#29), generałowie, reklamy, epoka II (#132–#135).

Powiązane: [[Plan MVP]], [[Roadmapa do 1.0]], [[Otwarte pytania]], [[Klasy jednostek i produkcja]], [[Interfejs]]
