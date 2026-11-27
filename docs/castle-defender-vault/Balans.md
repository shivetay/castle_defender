# Balans

Stan liczb z kodu na `main` (HEAD `77484bd`, 27.11.2026, wersja **0.6.0**). **Wszystkie wartości poniżej są tymczasowe.** Model balansu epok: #262 / #384 / [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]] — ciągła krzywa kosztu i czasu przez 10 poziomów i premie 6–10 (§ 1.7). Młyn: #388 / #396 / [[ADR/0011-budynki-epoki-ii-od-poziomu-6|ADR 0011]] (§ 1.8). Opcje A/B/C z § 3 to zapis rozważań sprzed decyzji.

Źródła kodu: `scripts/world/unit_types.gd`, `recruitment_config.gd`, `build_config.gd`, `economy_config.gd`, `goods_config.gd`, `research_config.gd`, `generals.gd`, `ages.gd`. Issue: #214 (utrzymanie Ży — zamknięte przez #247), #262 (balans epoki II — **zamknięte** przez #384), #273 (generałowie), #388 (Młyn).

Powiązane: [[Jednostki]], [[Klasy jednostek i produkcja]], [[Progresja budowy]], [[Władca i generałowie]], [[Epoki]], [[Otwarte pytania]], [[Stan prac]], [[Serwer]]

---

## 1. Tabele aktualnego stanu

### 1.1 Jednostki — rekrutacja i utrzymanie

Koszt rekrutacji = surowce + towary ze zbrojowni. **Nie ma osobnego złota za żołnierza** (złoto idzie na generałów). Utrzymanie (#214 / #247): Ży/h na jednostkę; suma ≤ produkcja żywności zamku. Limit miejsc (Dwór + Koszary) działa osobno.

| Jednostka | Epoka | Surowce | Towary | Utrzym. Ży/h | Czas szkol. poz.1 | Vault vs kod |
| --- | --- | --- | --- | --- | --- | --- |
| Chłop | I* | 5 Ży | — | 1 | 10 s | tylko w kodzie (epoka I only); vault bez osobnej tabeli kosztów |
| Wojownik z toporem | I | 10 Ży | 1 topór kamienny | 1 | 20 s | zgodne z [[Klasy jednostek i produkcja]] (towary); ilości Ży tymczasowe w kodzie |
| Oszczepnik | I | 10 Ży | 2 oszczepy | 1 | 20 s | j.w. |
| Łucznik | I | 10 Ży | 1 łuk + 20 strzał | 1 | 25 s | vault: „10 Ży + 1 łuk + 20 strzał” — **zgodne** |
| Tarczownik | I | 10 Ży | 1 tarcza + 1 zbroja skórzana | 1 | 40 s | zgodne (A21) |
| Podpalacz | I | 10 Ży | 2 smoła | 1 | 30 s | zgodne |
| Tropiciel | I | 15 Ży | 2 surowe skóry | 1 | 30 s | zgodne (S1, Chata tropicieli) |
| Jeździec | I | 15 Ży | 1 koń + 1 siodło | 2 | 45 s | zgodne |
| Kopacz | I | 10 Ży | — | 1 | 15 s | zgodne |
| Wóz | I | 40 Dr | 1 koń + 1 uprząż | 2 | 45 s | vault [[Jednostki]] ma carry/utrzymanie — **zgodne** |
| Włócznik | II | 10 Ży | 1 włócznia | 1 | 25 s | zgodne |
| Drużynnik w przeszywanicy | II | 15 Ży | przeszywanica + zbroja sk. + tarcza | 1 | 50 s | zgodne |
| Strzelec z łukiem refleksyjnym | II | 10 Ży | łuk refl. + 20 strzał | 1 | 35 s | zgodne |
| Kopijnik | II | 20 Ży | koń + siodło + kopia | 2 | 60 s | zgodne |
| Taran | II | 60 Dr | 2 mokre skóry | 0 | 90 s | zgodne (jawnie 0 Ży) |
| Zwiadowca | II | 15 Ży | koń + siodło | 2 | 40 s | zgodne (S3) |

\*Chłop: tylko epoka I (`ERA_I_ONLY`). Carry łupu: piechota 5, konnica/zwiadowca 10, taran 0, wóz 50.

**Limity armii (kod):** `ARMY_PER_MANOR_LEVEL = 10`, `ARMY_PER_BARRACKS_LEVEL = 2` (premie od `Ages.bonus_level`); od #262 Dwór w epoce II +8 za poziom (do 90), Koszary 2 za każdy z 10 poziomów ([[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]). Głód: 1 jednostka / `DESERT_MS` = 1 h na zerze Ży. Oddział max 10.

### 1.2 Budynki — budowa poziomu 1 (epoka I)

Kolejność surowców: Dr / Ka / Ży / Zł. Poziomy 2–5: mnożniki kosztu **100 / 150 / 250 / 400 / 600%**, czasu **1 / 3 / 10 / 30 / 90**. Epoka II (#262, [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]): krzywa ciągnie się dalej, koszt **850 / 1150 / 1500 / 1950 / 2500%**, czas **130 / 180 / 240 / 320 / 420** (umocnienia: połowa przyrostu ponad poziom 5, ×110 … ×255); mnożnik epoki ×2 usunięty.

| Budynek | Koszt L1 (Dr/Ka/Ży/Zł) | Czas L1 | Tech | Vault |
| --- | --- | --- | --- | --- |
| Wał | 10 / 0 / 10 / 0 | 5 s | — | [[Progresja budowy]] zgodna z kodem |
| Palisada | 20 / 0 / 5 / 0 | 10 s | — | przykład L1–II.5 w [[Progresja budowy]] |
| Brama | 60 / 20 / 20 / 0 | 30 s | — | — |
| Wieża | 120 / 40 / 40 / 0 | 60 s | — | — |
| Fosa sucha | 5 / 0 / 15 / 0 | 5 s | — | #35 |
| Kopiec | 60 / 40 / 40 / 0 | 60 s | O1 | #35 |
| Chata drwala | 80 / 0 / 30 / 0 | 45 s | — | skala bazowa |
| Pole i spichlerz | 60 / 0 / 20 / 0 | 40 s | — | produkcja Ży § 1.4 / 1.7 |
| Studnia | 40 / 30 / 10 / 0 | 30 s | — | #35 |
| Kamieniołom | 100 / 0 / 30 / 0 | 50 s | G4 | #35; epoka I od #315 |
| Magazyn | 100 / 40 / 0 / 0 | 45 s | — | pojemność +500…+6000 (L1–10) |
| Koszary | 100 / 20 / 40 / 0 | 60 s | — | — |
| Dom drużyny | 140 / 30 / 40 / 0 | 75 s | A45 | — |
| Strzelnica | 120 / 10 / 40 / 0 | 70 s | A44 | — |
| Stajnia | 100 / 20 / 40 / 0 | 60 s | — | — |
| Chata tropicieli | 120 / 20 / 40 / 10 | 70 s | S1 | — |
| Dom umocnień | 100 / 40 / 30 / 0 | 60 s | O2 | — |
| Wieża sygnałowa | 100 / 20 / 30 / 0 | 50 s | S2 | #35 |
| Wieża grodowa | 150 / 60 / 40 / 0 | 90 s | — | donżon |
| Młyn | 120 / 60 / 20 / 0 | 50 s | G5 | epoka II, start od poz. 6 (§ 1.8) |
| Wytwórcy (myśliwy…smolarnia, len, rybak) | 60–100 Dr (+ Ka/Ży wg `BASE_COST`) | 30–60 s | G18–G24 / A38–A43 | koszty tylko w kodzie |

Pełna lista w `BuildConfig.BASE_COST`.

### 1.3 Dwór — ulepszenia i przebudowa (restrukturyzacja epoki)

| Poziom (narastająco) | Znaczenie | Koszt Dr/Ka/Ży | Czas |
| --- | --- | --- | --- |
| 1 | start | 0 | 0 |
| 2 | I.2 | 300 / 200 / 200 | 10 min |
| 3 | I.3 | 500 / 350 / 350 | 1 h |
| 4 | I.4 | 750 / 550 / 550 | 4 h |
| 5 | I.5 | 1000 / 800 / 800 | 12 h |
| **6** | **przebudowa → epoka II** | **1000 / 1000 / 1000** | **14 h** |
| 7 | II.2 | 1300 / 1100 / 1100 | 18 h |
| 8 | II.3 | 1700 / 1400 / 1400 | 24 h |
| 9 | II.4 | 2200 / 1800 / 1800 | 30 h |
| 10 | II.5 | 2800 / 2300 / 2300 | 40 h |

Przebudowa L6 wymaga techów **O1 + G1 + A7** (`Ages.TRANSITION_TECHS`). Mieści się w magazynie grodu (1000) bez Magazynu. Poziomy 7–10 wymagają Magazynu. Poziomy 6–10 z ustaleń #262 ([[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]); premie poziomów epoki II rosną dalej (§ 1.7).

### 1.4 Produkcja surowców i badania

| Źródło | Stawka / h (poz. 1→5) | Epoka II (poz. 6→10) |
| --- | --- | --- |
| Baza grodu | +20 Dr, +20 Ka, +20 Ży | bez zmian |
| Chata drwala | 60 / 90 / 120 / 160 / 200 Dr | 240 / 280 / 330 / 380 / 440 |
| Pole i spichlerz | 60 / 90 / 120 / 160 / 200 Ży | 240 / 280 / 330 / 380 / 440 |
| Rybak | 40 / 60 / 80 / 110 / 140 Ży | 170 / 200 / 230 / 270 / 310 |
| Kamieniołom | 40 / 60 / 80 / 110 / 140 Ka | 170 / 200 / 230 / 270 / 310 |
| Start zapasu | 500 Dr, 300 Ka, 300 Ży, 50 Zł | — |
| Pojemność grodu | 1000 / 1000 / 1000 / ∞ (złoto) | Magazyn +500…+6000 (sumuje się) |
| Młyn | — | +4 / 8 / 12 / 16 / 20% całej produkcji Ży (§ 1.8) |

Badania (`ResearchConfig`): baza epoki I **100/50/50/0**, 60 s; epoka II **400/300/200/0**, 30 min; koszt stały w epoce, a ×1,6 kosztu tylko dla doktryn (A1, A2, G1, G2: sama procentowa premia) za każdą wcześniejszą doktrynę epoki; czas stały w epoce. Doktryny A1, A2, G1 i G2 mają poziomy (A1 115 → 120 → 125% obrażeń toporów w drewno, A2 120 → 125 → 130% zasięgu łuków, w całych kratkach w dół): +5 pkt proc. premii za poziom, najwyżej 3 w epoce I i 5 w epoce II, każdy poziom kosztuje jak kolejna doktryna epoki. G5 Młyn wodny: epoka II, wymaga G2.

### 1.5 Generałowie

| Akcja | Koszt | PD |
| --- | --- | --- |
| Rekrutacja | 50 Zł | — |
| Awans → 2 | 80 Zł | 100 |
| Awans → 3 | 150 Zł (z puli PvP) | 300 |
| PD za bitwę / wygraną | — | 20 / +20 |

PvE wystarcza najwyżej do poziomu 2 (`PVE_LEVEL`). Vault [[Władca i generałowie]] — **zgodny** z kodem po #273.

### 1.6 Rozjazdy vault ↔ kod (skrót)

| Temat | Vault | Kod | Status |
| --- | --- | --- | --- |
| Przykład palisady / typowe czasy | [[Progresja budowy]] = kod | 10 s L1; ciągła krzywa 1…420 | zgodne (#262 / #384) |
| Premie poziomów 6–10 | tablice w § 1.7 | `EconomyConfig` / `Ages.bonus_level` do 10 | zgodne |
| Młyn | [[Gospodarka]] + § 1.8 | `MILL_FOOD_PERCENT`, start 6 | zgodne (#396) |
| Koszty jednostek Ży | ta notatka § 1.1 | 5–20 Ży | zgodne |
| Generałowie | [[Władca i generałowie]] | #273 | zgodne |
| Utrzymanie Ży | § 1.1 | `UPKEEP` | zgodne |

### 1.7 Premie poziomów epoki II (#262 / #384)

Tymczasowe liczby z ustaleń 27.11.2026 ([[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]). Poziomy 1–5 bez zmian.

| Premia | II.1 | II.2 | II.3 | II.4 | II.5 |
| --- | --- | --- | --- | --- | --- |
| Chata drwala, Pole i spichlerz (na godzinę) | 240 | 280 | 330 | 380 | 440 |
| Rybak, Kamieniołom (na godzinę) | 170 | 200 | 230 | 270 | 310 |
| Wytwórcy, także żywność Chaty myśliwego (% tempa poz. 1) | 425 | 500 | 575 | 650 | 750 |
| Wytrzymałość w bitwie (% poz. 1) | 560 | 680 | 810 | 950 | 1100 |
| Magazyn (pojemność) | 2500 | 3000 | 3500 | 4500 | 6000 |
| Limit armii z Dworu | 58 | 66 | 74 | 82 | 90 |
| Garnizon Dworu | 24 | 28 | 32 | 36 | 40 |
| Limit pułapek | 12 | 14 | 16 | 18 | 20 |
| Miejsca w kolejce szkolenia ([[ADR/0013-premie-szkolenia-fosy-i-kopca-w-epoce-ii\|ADR 0013]]) | 7 | 8 | 9 | 10 | 11 |
| Tempo szkolenia (% poz. 1, ADR 0013) | 230 | 260 | 300 | 340 | 400 |
| Kolce w Fosie suchej (HP/s, ADR 0013) | 7 | 8 | 9 | 10 | 11 |
| Zasięg z Kopca (kratki, ADR 0013) | +2 | +2 | +2 | +3 | +3 |

Koszary dają 2 miejsca za każdy poziom 1–10. Strefa obrony rośnie z Dworem i O25 ([[ADR/0007-strefa-obrony-z-dworu-i-technologii|ADR 0007]]); wzór bierze `bonus_level` do 10. Badania epoki II i rok na pasku bez zmian względem ADR 0009. Szkolenie, kolce w fosie i Kopiec rosną dalej od #387 ([[ADR/0013-premie-szkolenia-fosy-i-kopca-w-epoce-ii|ADR 0013]]).

### 1.8 Młyn (#388 / #396)

Budynek epoki II: technologia G5, 2×2 przy rzece, stawia się od poziomu narastającego **6**
([[ADR/0011-budynki-epoki-ii-od-poziomu-6|ADR 0011]]). Koszt L1 = 120/60/20/0, czas L1 = 50 s;
płaci się od razu krzywą od poziomu 6 (1020/510/170 przy ×130). Premia żywności z jednego
najwyższego Młyna: +4 / 8 / 12 / 16 / 20% (`EconomyConfig.MILL_FOOD_PERCENT`); w ruinie ×75%.
Serwer: migracja `*_mill.sql` — parity kosztów, `mill_food_percent`, odrzut poziomów 1–5.

Wyprawa / PvP (kontekst balansu): 20 botów na epokę (#385); dobór graczy tylko w tej samej epoce
([[ADR/0010-dobor-pvp-tylko-w-tej-samej-epoce|ADR 0010]] / #395).

---

## 2. Krótka analiza problemów

Fakty z kodu — stan po #384 / #396:

1. **Armia vs żywność.** Limit utrzymania działa (#247), ale piechota kosztuje tylko **1 Ży/h** przy produkcji Pola 60–200/h (i 240–440 w epoce II) + Rybak + baza 20 + opcjonalnie Młyn. Dwór 5 + Koszary 5 ≈ **60 miejsc** — spożywanie nadal nie jest wąskim gardłem przy spamie taniej piechoty.
2. **Złoto prawie nie hamuje armii.** Żołnierze nie biorą Zł; 50 start + łup. Generałowie są tani (50 / 80 / 150). Tempo złota zależy od PvP/PvE, nie od produkcji.
3. **Epoka II ma ciągłą krzywą i premie** (#262 / #384). Przebudowa 1000/1000/1000 + 14 h; budynki droższe i dłuższe niż I.5; premie 6–10 rosną. Liczby nadal tymczasowe — kolejna passa po playteście.
4. **Skala czasów = kod.** Vault ([[Progresja budowy]]) idzie za `TIME_MULT` / umocnieniami II (×110…255). Wieża L5 = 90 min; Wieża II.1 = 2 h 10 min.
5. **Łańcuch towarów** jest prawdziwym kosztem armii (łuki, konie, skóry), ale tempo przepisów jest tymczasowe i łatwo zapełnia zbrojownię offline (limit catch-up 30 dni).
6. **Generałowie (#273):** XP 20+20 i cap PvE na L2 pchają w PvP — OK projektowo; liczby nadal tymczasowe.
7. **Deploy bilansu** wymaga migracji + EF + `min_code` od razu ([[Serwer]]); stary klient inaczej dostaje `economy_too_fast` / `build_too_fast`.

---

## 3. Opcje balansu (zapis rozważań 21–23.11)

A i B to skrajne odniesienia. **Opcja C** była propozycją środka (feedback 23.11.2026). **27.11 właścicielka wybrała ciągłą krzywą** ([[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]] / #384): z C została tylko zasada monetyzacji; liczby C (m.in. Dwór 800/8 h, `TIME_MULT` [1,2,6,20,55], premie lokalne L6→1) **odrzucone**. Poniższe tabele zostają jako historia grillowania.

### Opcja A — „Szybki gród” (łatwiejszy early, miększa epoka II) — odniesienie

Cel: pierwsza sesja daje armię i umocnienia w minutach; epoka II nie wymaga Magazynu na pierwsze ulepszenia; żywność nadal limituje, ale nie dusi.

| Parametr | Teraz | Opcja A |
| --- | --- | --- |
| Utrzymanie piechoty / konnicy / wozu | 1 / 2 / 2 | **1 / 2 / 2** (bez zmian) |
| Koszt Ży rekrutacji (Topornik…Łucznik) | 10 | **8** |
| Chłop | 5 Ży | **4 Ży** |
| `ARMY_PER_MANOR_LEVEL` | 10 | **12** |
| Przebudowa Dworu L6 | 1000/1000/1000, 12 h | **600/600/600, 4 h** |
| `AGE_COST_PERCENT` / `AGE_TIME_MULT` ep. II | 200 / 2 | **150 / 1,5** |
| Premie poziomów 6–10 | jak 5 | **jak lokalny poziom epoki** (L6→1 … L10→5) — klient + serwer |
| Czas szkolenia (mnożnik) | 100% | **80%** (`TRAIN_TIME_S` ×0,8) |
| Generał: rekrutacja / L2 / L3 | 50 / 80+100PD / 150+300PD | **40 / 60+80PD / 120+250PD** |
| Typowe czasy budowy w notatce | rozjazd | **dostosować vault do kodu** (kod zostaje skalą) |

**Tradeoffy:** szybszy onboarding i mniej frustracji Magazynem; ryzyko spamu armii i krótszego „głodzenia” przeciwnika; PvP early mocniejsze; mniej presji na budowę żywności.

### Opcja B — „Głód i złoto” (twardszy anti-spam, epoka II jako próg) — odniesienie

Cel: żywność i złoto realnie ograniczają armię; epoka II zostaje droga i wymusza Magazyn; premie II nagradzają przebudowę.

| Parametr | Teraz | Opcja B |
| --- | --- | --- |
| Utrzymanie piechoty / konnicy / wozu | 1 / 2 / 2 | **2 / 4 / 3** |
| Koszt Ży rekrutacji bazowej piechoty | 10 | **15** |
| Chłop | 5 Ży, utrzym. 1 | **8 Ży, utrzym. 2** (albo usunąć Chłopa z MVP) |
| `ARMY_PER_MANOR_LEVEL` | 10 | **8** |
| Produkcja Pola L1 | 60 Ży/h | **40 Ży/h** (L5: 140 zamiast 200) |
| Przebudowa Dworu L6 | 1000/1000/1000, 12 h | **pozostaje**; dodać **200 Zł** |
| `AGE_COST_*` ep. II | ×2 / ×2 | **pozostaje**; Magazyn wymagany świadomie |
| Premie poziomów 6–10 | jak 5 | **tablica `per_level` do 10** (+produkcja / limit armii / HP murów rosną co poziom) |
| Generał: rekrutacja / L2 / L3 | 50 / 80 / 150 | **100 / 150+150PD / 300+400PD** |
| Czas szkolenia | 100% | **120%** |
| Skala czasów budowy | kod długi vs notatka krótka | **skrócić `TIME_MULT` do [1,2,5,15,40]** i zsynchronizować [[Progresja budowy]] |

**Tradeoffy:** mniejszy spam, większa waga Pol / Rybaka / Magazynu; wolniejszy early i trudniejszy samouczek (#251); wymaga migracji serwera dla premii i limitów (`army_limit`, `food_production`); wyższe koszty generałów mocniej wiążą z PvP.

### Opcja C — „Spokojny rytm” (propozycja z 23.11, rozstrzygnięta 27.11)

> **Rozstrzygnięcie (#262, [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]):** z Opcji C przyjęto tylko zasadę monetyzacji (reklamy i sklep przyspieszają, nie odblokowują). Odrzucono: `AGE_COST_PERCENT = 175`, `TIME_MULT = [1, 2, 6, 20, 55]`, przebudowę Dworu 800/800/800 w 8 h i premie „L6→1 … L10→5” (lokalny poziom epoki), bo premie i koszty spadałyby na przejściu. Zmiany jednostek z C (Chłop 8 Ży, dłuższe szkolenie tanich jednostek) nie weszły: epoka I zostaje bez zmian.

Cel: komfortowy F2P bez poczucia głodu i bez spamu taniej piechoty; wąskie gardło to **towary + miejsca + czas**, nie Ży/h. Reklamy i sklep przyspieszają / upiększają — nigdy nie odblokowują tego, czego nie da się dostać za darmo czekając.

| Parametr | Teraz | Opcja A | Opcja B | **Opcja C** |
| --- | --- | --- | --- | --- |
| Utrzymanie piechoty / konnicy / wozu | 1 / 2 / 2 | 1 / 2 / 2 | 2 / 4 / 3 | **1 / 2 / 2** (bez zmian — zero „głodówki”) |
| Koszt Ży rekrutacji (Topornik…Łucznik) | 10 | 8 | 15 | **10** (bez zmian) |
| Chłop | 5 Ży, utrzym. 1 | 4 Ży | 8 Ży / utrzym. 2 | **8 Ży, utrzym. 1** (anti-spam startu, bez karania Ży/h) |
| Kopacz / Taran Ży | 10 / 0 Dr60 | — | — | **bez zmian** |
| Jeździec / Kopijnik Ży | 15 / 20 | — | — | **bez zmian** (konnica już droga w towarach) |
| `ARMY_PER_MANOR_LEVEL` | 10 | 12 | 8 | **10** |
| `ARMY_PER_BARRACKS_LEVEL` | 2 | 2 | 2 | **2** |
| Produkcja Pola L1→L5 | 60…200 | bez zmian | 40…140 | **60…200** (bez cięcia Ży) |
| Przebudowa Dworu L6 | 1000/1000/1000, 12 h | 600/600/600, 4 h | 1000+200 Zł, 12 h | **800/800/800, 8 h**, **0 Zł** |
| `AGE_COST_PERCENT` / `AGE_TIME_MULT` ep. II | 200 / 2 | 150 / 1,5 | 200 / 2 | **175 / 2** (koszt −12,5% vs teraz; czas ×2 zostaje) |
| Premie poziomów 6–10 | jak 5 | lokalny 1…5 | pełna tablica do 10 | **lokalny poziom epoki** (L6→1 … L10→5), klient + serwer |
| `TIME_MULT` budowy L1…L5 | [1, 3, 10, 30, 90] | zostaje (vault→kod) | [1, 2, 5, 15, 40] | **[1, 2, 6, 20, 55]** (Wieża L5 ≈ 55 min zamiast 90; sesja offline wystarcza) |
| Czas szkolenia (mnożnik) | 100% | 80% | 120% | **100%**; Chłop / Topornik / Oszczepnik **×1,25** (`TRAIN_TIME_S` tylko tych trzech) |
| Generał: rekrutacja / L2 / L3 | 50 / 80+100PD / 150+300PD | taniej | drożej | **50 / 80+100PD / 150+300PD** (bez zmian) |
| `DESERT_MS` (głód) | 1 h | — | — | **1 h** (zostaje jako awaryjny zawór, nie główny balans) |

**Anti-spam bez głodu (reguły C):**

1. Utrzymanie Ży/h **nie rośnie** — gracz z Polem L3+ komfortowo trzyma pełny limit miejsc.
2. Spam Chłopami / tanią piechotą hamują: wyższy koszt Ży Chłopa (8), dłuższe szkolenie tanich trzech, oraz **łańcuch towarów** dla reszty (bez zmian przepisów).
3. Limit miejsc (Dwór 10 + Koszary 2/poziom) zostaje — nie dokręcamy slotów jak w B.
4. Epoka II: przebudowa osiągalna z magazynu grodu (800 < 1000); Magazyn nadal potrzebny na L8–L10 (1500+).

#### Monetizacja w Opcji C (zasada)

**Zasada:** postęp bez reklam i bez sklepu jest **kompletny** (epoka II, pełna armia w limicie, generał L3 z PvP). Reklamy i sklep **przyspieszają albo upiększają** — nigdy nie są jedyną drogą przez próg (tech, Dwór 5, O1/G1/A7, miejsca armii).

| Warstwa | Co dostaje F2P w wygodnym tempie | Czego nie wymaga |
| --- | --- | --- |
| Budowa / badania | L1–L3 w sesji; L4–L5 i L6 Dworu przez offline (`TIME_MULT` C + catch-up) | oglądania reklamy, żeby dokończyć |
| Armia | pełny limit miejsc przy 1–2 źródłach Ży; jakość przez towary | płacenia Ży/h „pod korek” ani złota za żołnierza |
| Epoka II | L6 za 800/800/800 w 8 h offline + techy | Zł z sklepu / reklamy |
| Generałowie | L1–L2 z PvE; L3 z PvP (jak #273) | reklamy na PD |

| Reklama z nagrodą ([[Model wydania]], #33) | Efekt w C | Soft-lock? |
| --- | --- | --- |
| Przyspieszenie budowy / badania | −25% pozostałego czasu (min. −15 min), max 6/dzień | **nie** — bez ads czeka się dłużej na L4–L6 |
| ×2 produkcji surowca 1 h | max 3/dzień; przyśpiesza zapełnienie Magazynu pod L8+ | **nie** — produkcja bazowa wystarcza na L6 |
| (później) skrócenie do ataku / wywiad / sabotaż / ochrona magazynu | wygoda PvP, nie siła stała | **nie** — zwiad i atak działają bez ads |

| Sklep (#174) | Propozycja pod C | Soft-lock? |
| --- | --- | --- |
| Pakiet startowy / „wesprzyj twórcę” | złoto startowe + kosmetyczny sztandar / flaga (nie mnożnik obrażeń) | **nie** |
| Wygoda | np. +1 miejsce w kolejce budowy **albo** jeden jednorazowy −50% czasu na wybrane zlecenie / dzień (limit serwerowy) | **nie** — kolejka 1+3 działa bez zakupu |
| Kosmetyka | skóry Dworu / baner rankingu / portret | **nie** |
| Zakazane w C | permanentny +% obrażeń, pomijanie techów przejścia, kupowanie miejsc armii ponad Dwór, „odblokuj epokę” | — |

**Tradeoffy C:** wolniejszy early niż A (Chłop droższy, tania piechota dłużej się szkoli); łagodniejszy niż B (Ży/h i Pole bez nerfu). Reklamy mają sens głównie na długich timerach L4–L6 i Magazynie — gracz **widzi** korzyść, ale F2P kończy to samo wieczorem / rano. Wymaga tej samej migracji premii 6–10 co A (klient + serwer).

---

## 4. Stan po decyzji (27.11.2026)

**Przyjęte:** [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]] w kodzie (#384) i na serwerze
(migracja `age_two_balance`); Młyn (#396); same-age PvP (#395). #262 zamknięte.

**Dalej (bez nowej decyzji o modelu):**

1. Playtest liczb epoki II na telefonie; ewentualna druga passa liczb (nadal tymczasowe).
2. Ops przy wydaniu klienta: pack `sim_version`, `min_code` od razu — [[Serwer]].
3. Trzymać nagrady ads i sklep w limicie zasady z § Monetizacja C; ticket #33 / #174.
4. Pozostałe budynki #102 (Pomost, Częstokół, Kaplica) na tej samej krzywej od poziomu 6.

Powiązane: [[00 Start]], [[Plan MVP]], [[Bugs]], [[Model wydania]], [[Serwer]], [[ADR/README|ADR]]
