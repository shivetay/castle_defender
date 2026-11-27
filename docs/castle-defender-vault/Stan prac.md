# Stan prac

Aktualizacja: 27.11.2026 (Europe/Warsaw). Kod: repo `shivetay/castle_defender` (Godot 4.7, GDScript),
wersja gry **0.6.0** (HEAD `77484bd` na `main`). Tickety: issues z labelkami `mvp` / `v1.0` oraz
kamieniami milowymi.

## Wydania

| Wersja | Data | Stan | Co zawiera |
| --- | --- | --- | --- |
| 0.0.1 | 13.11.2026 | wydana | organizacja projektu, CI z debug APK, reguły agenta |
| 0.1.0 | 13.11.2026 | wydana | teren 64×64, siatka budowy, kamera, budynki epoki I z 5 poziomami |
| 0.2.0 | 15.11.2026 | wydana | stany zniszczeń, ekonomia w tle, kolejka budowy, Dwór, zapis lokalny |
| 0.3.0 | 16.11.2026 | wydana | badania, towary i wytwórcy, rekrutacja, klasy jednostek, Chłop |
| 0.4.0 | 17.11.2026 | wydana | bitwa, morale, donżon, samouczek PvE, plan ataku, obrona, pułapki |
| 0.5.x | 24–26.11.2026 | wydane | backend PvP, zwiad, ranking, historia obron, weryfikacja ataków |
| **0.6.0** | 27.11.2026 | na `main` | balans epoki II, boty 20/epoka, same-age PvP, Młyn, sim_version, wymuszenie aktualizacji |

## Co weszło od ostatniej dużej aktualizacji vaultu

### 24–26.11.2026 — serwer, UX, ADR-y

- Wymuszenie aktualizacji klienta (#370 / [[ADR/0006-wymuszenie-aktualizacji-wersji-klienta|ADR 0006]]).
- Rozmiary budynków (#369 / [[ADR/0005-rozmiary-budynkow|ADR 0005]]).
- Siła celu PvP jako przedział z serwera (#367 / [[ADR/0004-sila-celu-pvp-przedzial-z-serwera|ADR 0004]]).
- Historia obron z nickiem (#365 / [[ADR/0003-historia-obron-z-nickiem-i-sila-napastnika|ADR 0003]]).
- Strefa obrony z Dworu i O25 (#373 / [[ADR/0007-strefa-obrony-z-dworu-i-technologii|ADR 0007]]);
  pułapki i zadania obrony poza strefą / klasą (#377, #380).
- Lista po wydaniu: `docs/PO-WYDANIU.md` (#353).

### 27.11.2026 — balans, boty, PvP, Młyn

- **Balans epoki II** (#384 / #262 / [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]): ciągła
  krzywa kosztu i czasu przez 10 poziomów, premie 6–10, Dwór II.1–II.5; umocnienia w II biorą
  połowę przyrostu ponad L5. Migracja `age_two_balance`; przy wydaniu klienta `min_code` od razu.
- **Wersja symulacji** (#382 / [[ADR/0008-wersja-symulacji-ataku-z-klienta|ADR 0008]]): atak z
  `sim_version` z telefonu; pack na VPS przed APK.
- **Wyprawa:** 20 zamków-botów na każdą epokę I–II (#385; test #394).
- **Dobór PvP tylko w tej samej epoce** (#395 / #383 /
  [[ADR/0010-dobor-pvp-tylko-w-tej-samej-epoce|ADR 0010]]).
- **Młyn** (#396 / #388 / [[ADR/0011-budynki-epoki-ii-od-poziomu-6|ADR 0011]]): G5, start od
  poziomu 6, premia +4…20% żywności, przy rzece. Numer ADR: po kolizji z #395 mill = **0011**,
  same-age = **0010**.
- UI: ikony surowców (#398), ekran tytułowy Dunholm + Discord (#397), lista wojska tylko
  szkolalne (#381).

Starsza chronologia (12–23.11): etapy 1–11 jak w historii git / CHANGELOG — nie powtarzana tu w całości.
Wcześniej: backend PvP, zwiad, epoka II (mechanika #261), utrzymanie Ży (#247), generałowie (#273).

## Etapy MVP

**Bieżący nacisk:** resztki etapów 10–13 (push, perki władcy, życie w zamku, reklamy) oraz ops
staging/prod ([[Serwer]]); balans #262 **zamknięty** w kodzie.

| Etap | Stan |
| --- | --- |
| 1–3 (#123–#125) | gotowe w kodzie; wygląd #150 nadal otwarty |
| 4 (#126) | kod gotowy; #81 (wygląd Dworu / garnizon) do domknięcia checklisty |
| 5 (#127) | prawie: #12 (pełne efekty badań) otwarte; rekrutacja #89 zamknięta |
| 6–8 (#128–#130) | kod gotowy |
| 9 (#131) | rdzeń PvP na `main` + same-age (#395); część checklist w issue |
| 10 (#132) | zwiad + powtórka + historia; #99 (UI wyniku) i #30 (push) otwarte |
| 11 (#133) | generałowie #31 zamknięte; perki władcy #32 otwarte |
| 12 (#134) | reklamy #33 otwarte |
| 13 (#135) | mechanika #261 + balans #262 + Młyn #388; Pomost/Częstokół/Kaplica (#102) i #36 otwarte |
| 14 (#136) | zamknięte testy — później |

Pełna lista: [[Plan MVP]]. Pytania: [[Otwarte pytania]]. Koszty: [[Balans]]. Backend: [[Serwer]].
Bugi UX: [[Bugs]].

## Decyzje (narosłe)

### 13.11.2026

- 5 klas jednostek; rekrutacja zużywa towary; Stajnia i Jeździec w epoce I; od III żelazo.
- MVP: 25+ budynków i 13 jednostek; losowy seed mapy; celem ataku jest donżon (#120).

### Od 16.11.2026 (z kodu)

- Limit oddziałów w planie ataku: **3 w epoce I … 8 w epoce VI**.
- Bitwą nikt nie steruje; plan i zadania obrony wykonują się same.

### 20–21.11.2026 — przejście epoki (#34 / #261)

- I → II: O1 + G1 + A7 oraz Dwór poziom 5 → przebudowa L6.
- Budynki: max → poziom 1 nowej epoki z zachowaniem bonusów; premie rosną z krzywą (#262).

### 21–22.11.2026 — generałowie (#31 / #273)

- Bez postaci na siatce; dowodzą całą stroną. Koszty tymczasowe (50 / 80+100 PD / 150+300 PD). PvE max poziom 2.

### 21–27.11.2026 — balans

- 21.11: „balans zrobimy później” → #262; A/B jako skrajne odniesienia w [[Balans]].
- 23.11: feedback — bez głodu, bez spamu, F2P kompletny → vault proponował **Opcję C**.
- 27.11: grillowanie → [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]] (ciągła krzywa,
  premie 6–10). Z Opcji C została tylko zasada reklam i sklepu. Kod #384; #262 zamknięte.
- 27.11: same-age PvP ([[ADR/0010-dobor-pvp-tylko-w-tej-samej-epoce|ADR 0010]]); budynki epoki II
  od poziomu 6 + Młyn ([[ADR/0011-budynki-epoki-ii-od-poziomu-6|ADR 0011]]).

## Następne kroki

1. Ops: wgrać migracje / EF Młyna i same-age na staging (jeśli jeszcze nie); pack `sim_version` +
   `min_code` przy wydaniu klienta — [[Serwer]], `docs/PO-WYDANIU.md`.
2. Pozostałe budynki #102 (Pomost, Częstokół, Kaplica, zasięg Domu zwiadowców).
3. Perki władcy (#32), push (#30), UI wyniku bitwy (#99), życie w zamku (#36), reklamy (#33).
4. Split staging/prod Supabase, gdy startują testerzy w Play.

Powiązane: [[Plan MVP]], [[Roadmapa do 1.0]], [[Otwarte pytania]], [[Balans]], [[Serwer]],
[[ADR/README|ADR]], [[00 Start]]
