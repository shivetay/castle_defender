# Stan prac

Aktualizacja: 23.11.2026. Kod: repo `shivetay/castle_defender` (Godot 4.7, GDScript), wersja gry **0.4.0** (+ scalenia na `main` bez nowego tagu). Tickety: issues z labelkami `mvp` / `v1.0` oraz kamieniami milowymi.

## Wydania

| Wersja | Data | Stan | Co zawiera |
| --- | --- | --- | --- |
| 0.0.1 | 13.11.2026 | wydana | organizacja projektu, CI z debug APK, reguły agenta |
| 0.1.0 | 13.11.2026 | wydana | teren 64×64, siatka budowy, kamera, budynki epoki I z 5 poziomami |
| 0.2.0 | 15.11.2026 | wydana | stany zniszczeń, ekonomia w tle, kolejka budowy, Dwór, zapis lokalny |
| 0.3.0 | 16.11.2026 | wydana | badania, towary i wytwórcy, rekrutacja, klasy jednostek, Chłop |
| 0.4.0 | 17.11.2026 | wydana | bitwa, morale, donżon, samouczek PvE, plan ataku, obrona, pułapki |
| po 0.4.0 | 18–22.11.2026 | na `main` | backend PvP, zwiad, ranking, epoka II (mechanika), utrzymanie Ży, generałowie, powtórka |

## Co weszło od ostatniej dużej aktualizacji vaultu

### 18–20.11.2026 — backend, limity, budynki MVP

- Klient Supabase, atak, tarcze, seed mapy na serwerze (#166).
- Limit armii od produkcji żywności (#214 → #247); serwer odrzuca armię ponad limit (#254).
- Budynki MVP #35: Fosa, Kopiec, Pole i spichlerz, Studnia, Kamieniołom, Wieża sygnałowa (#256).
- Odbudowa zamku po ataku / ruiny (#255); wóz łupowy (#252); donżon strzela (#244).
- Ranking PvP (#243–#245).

### 20–21.11.2026 — epoka II, zwiad, ranking PvE

- Zasady przejścia epoki w vault i kodzie (#34 / #246 / #261): Dwór L6 = przebudowa, techy O1+G1+A7; budynki wchodzą w epokę II z poziomu 5; premie na razie jak L5.
- **Balans liczb epoki II odłożony** → #262, decyzje w [[Balans]].
- Zwiad z mgłą wojny (#28 / #258–#259).
- Ranking PvE (#264–#265; ticket zbiorczy #242 jeszcze otwarty).

### 21–22.11.2026 — powtórka i generałowie

- Obrońca ogląda powtórkę i poprawia obronę (#266–#267; część #29 / #132).
- Generałowie: Wódz, Łowczy, Budowniczy kopców; rekrutacja 50 Zł; L2/L3 w Dworze; PvE max L2; anti-cheat budżetu (#31 / #273). Perki władcy nadal #32.

Starsza chronologia (12–17.11): etapy 1–8 jak w historii git / CHANGELOG — nie powtarzana tu w całości.

## Etapy MVP

**Bieżący nacisk:** domknięcie resztek etapów 10–13 (powiadomienia, perki władcy, balans #262, życie w zamku #36, reklamy #33) oraz otwarte tickety zbiorcze.

| Etap | Stan |
| --- | --- |
| 1–3 (#123–#125) | gotowe w kodzie; wygląd #150 nadal otwarty |
| 4 (#126) | kod gotowy: #81 (wygląd Dworu w epokach I–II, garnizon) w PR; migracja `garrison` czeka na wgranie |
| 5 (#127) | prawie: #12 (pełne efekty badań) otwarte; rekrutacja #89 zamknięta |
| 6–8 (#128–#130) | kod gotowy (#19, #20, #101, #185 zamknięte) |
| 9 (#131) | rdzeń PvP na `main`; część checklist w issue może być do odhaczenia |
| 10 (#132) | zwiad + powtórka na `main`; #99 (gwiazdki/łup UI) i #30 (push) otwarte |
| 11 (#133) | generałowie #31 zamknięte (#273); perki władcy #32 otwarte |
| 12 (#134) | reklamy #33 otwarte |
| 13 (#135) | mechanika epoki II #261; balans #262; budynki #35 zamknięte; #36 życie w zamku otwarte |
| 14 (#136) | zamknięte testy — później |

Pełna lista: [[Plan MVP]]. Pytania: [[Otwarte pytania]]. Koszty: [[Balans]]. Bugi UX: [[Bugs]].

## Decyzje (narosłe)

### 13.11.2026

- 5 klas jednostek; rekrutacja zużywa towary; Stajnia i Jeździec w epoce I; od III żelazo.
- MVP: 25+ budynków i 13 jednostek; losowy seed mapy; celem ataku jest donżon (#120).

### Od 16.11.2026 (z kodu)

- Limit oddziałów w planie ataku: **3 w epoce I … 8 w epoce VI**.
- Bitwą nikt nie steruje; plan i zadania obrony wykonują się same.

### 20–21.11.2026 — przejście epoki (#34 / #261)

- I → II: O1 + G1 + A7 oraz Dwór poziom 5 → przebudowa L6.
- Budynki: max → poziom 1 nowej epoki z zachowaniem bonusów; premie II do ustalenia (#262).
- `players.age` na serwerze — do dopięcia.

### 21–22.11.2026 — generałowie (#31 / #273)

- Bez postaci na siatce; dowodzą całą stroną. Koszty tymczasowe (50 / 80+100 PD / 150+300 PD). PvE max poziom 2.

### 21–23.11.2026 — balans

- 21.11: „balans zrobimy później” → #262; A/B jako skrajne odniesienia w [[Balans]].
- 23.11: feedback — bez głodu, bez spamu, F2P kompletny, ads/sklep z realną korzyścią bez soft-locka → vault proponuje **Opcję C „Spokojny rytm”** (pending OK).
- 27.11: grillowanie #262 → model balansu epok: ciągła krzywa kosztu i czasu przez 10 poziomów, premie poziomów 6–10, Dwór II.1–II.5 ([[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]). Z Opcji C została tylko zasada reklam i sklepu. Kod w PR (#262); migracja `age_two_balance` wgrana na projekt 27.11 przed wydaniem (w epoce II nie było graczy). Przy wydaniu klienta `min_code` podnosimy od razu, bez zwykłych 48 h (decyzja właścicielki, wyjątek od `docs/PO-WYDANIU.md` §6).

## Następne kroki

1. Domknąć #262: merge PR z [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]], nowy `sim_version` i pack przed APK, wydanie klienta i od razu podniesienie `min_code` (bez 48 h; migracja `age_two_balance` już jest na projekcie); test liczb na telefonie.
2. Perki władcy (#32), push (#30), resztki wyniku bitwy (#99), życie w zamku (#36).
3. Reklamy (#33), zamknięte testy (#37 / #136).
4. Odhaczyć zbiorcze body etapów 9–13, jeśli kod już wyprzedza checklisty.

Powiązane: [[Plan MVP]], [[Roadmapa do 1.0]], [[Otwarte pytania]], [[Balans]], [[Klasy jednostek i produkcja]], [[00 Start]]
