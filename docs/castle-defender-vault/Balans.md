# Balans

Stan liczb z kodu na `main` (HEAD 6bb7bbe, 22–23.11.2026) oraz porównanie z vaultem. **Wszystkie wartości poniżej są tymczasowe** — właścicielka odłożyła passa balansu (#262, decyzja 21.11.2026). Ta notatka zbiera fakty i **dwie konkretne opcje** do wyboru; nic nie wdrażamy bez decyzji.

Źródła kodu: `scripts/world/unit_types.gd`, `recruitment_config.gd`, `build_config.gd`, `economy_config.gd`, `goods_config.gd`, `research_config.gd`, `generals.gd`, `ages.gd`. Issue: #214 (utrzymanie Ży — zamknięte przez #247), #262 (balans epoki II — otwarte), #273 (generałowie).

Powiązane: [[Jednostki]], [[Klasy jednostek i produkcja]], [[Progresja budowy]], [[Władca i generałowie]], [[Epoki]], [[Otwarte pytania]], [[Stan prac]]

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

**Limity armii (kod):** `ARMY_PER_MANOR_LEVEL = 10`, `ARMY_PER_BARRACKS_LEVEL = 2` (premie od `Ages.bonus_level`, max 5). Głód: 1 jednostka / `DESERT_MS` = 1 h na zerze Ży. Oddział max 10.

### 1.2 Budynki — budowa poziomu 1 (epoka I)

Kolejność surowców: Dr / Ka / Ży / Zł. Poziomy 2–5: mnożniki kosztu **100 / 150 / 250 / 400 / 600%**, czasu **1 / 3 / 10 / 30 / 90**. Epoka II: koszt ×2, czas ×2 (`AGE_COST_PERCENT` / `AGE_TIME_MULT`).

| Budynek | Koszt L1 (Dr/Ka/Ży/Zł) | Czas L1 | Tech | Vault |
| --- | --- | --- | --- | --- |
| Wał | 10 / 0 / 10 / 0 | 5 s | — | przykłady w [[Progresja budowy]] **nie zgadzają się** z kodem (tam palisada 20 Dr / 15 s vs kod 20 / 10 s) |
| Palisada | 20 / 0 / 5 / 0 | 10 s | — | rozjazd czasów „typowych” vs kod |
| Brama | 60 / 20 / 20 / 0 | 30 s | — | — |
| Wieża | 120 / 40 / 40 / 0 | 60 s | — | — |
| Fosa sucha | 5 / 0 / 15 / 0 | 5 s | — | #35 |
| Kopiec | 60 / 40 / 40 / 0 | 60 s | O1 | #35 |
| Chata drwala | 80 / 0 / 30 / 0 | 45 s | — | skala bazowa |
| Pole i spichlerz | 60 / 0 / 20 / 0 | 40 s | — | produkcja Ży zgodna z [[Gospodarka]] |
| Studnia | 40 / 30 / 10 / 0 | 30 s | — | #35 |
| Kamieniołom | 100 / 0 / 30 / 0 | 50 s | G4 | #35 |
| Magazyn | 100 / 40 / 0 / 0 | 45 s | — | pojemność +500…+2000 |
| Koszary | 100 / 20 / 40 / 0 | 60 s | — | — |
| Dom drużyny | 140 / 30 / 40 / 0 | 75 s | A45 | — |
| Strzelnica | 120 / 10 / 40 / 0 | 70 s | A44 | — |
| Stajnia | 100 / 20 / 40 / 0 | 60 s | — | — |
| Chata tropicieli | 120 / 20 / 40 / 10 | 70 s | S1 | — |
| Dom umocnień | 100 / 40 / 30 / 0 | 60 s | O2 | — |
| Wieża sygnałowa | 100 / 20 / 30 / 0 | 50 s | S2 | #35 |
| Wieża grodowa | 150 / 60 / 40 / 0 | 90 s | — | donżon |
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
| **6** | **przebudowa → epoka II** | **1000 / 1000 / 1000** | **12 h** |
| 7 | II.2 | 600 / 400 / 400 | 20 min |
| 8 | II.3 | 1000 / 700 / 700 | 2 h |
| 9 | II.4 | 1500 / 1100 / 1100 | 8 h |
| 10 | II.5 | 2000 / 1600 / 1600 | 24 h |

Przebudowa L6 wymaga techów **O1 + G1 + A7** (`Ages.TRANSITION_TECHS`). Mieści się w magazynie grodu (1000) bez Magazynu. Poziomy 8–10 wymagają Magazynu. Premie produkcji / limitu armii w epoce II nadal liczą się jak poziom 5 (`Ages.bonus_level`) — #262.

### 1.4 Produkcja surowców i badania

| Źródło | Stawka / h (poz. 1→5) |
| --- | --- |
| Baza grodu | +20 Dr, +20 Ka, +20 Ży |
| Chata drwala | 60 / 90 / 120 / 160 / 200 Dr |
| Pole i spichlerz | 60 / 90 / 120 / 160 / 200 Ży |
| Rybak | 40 / 60 / 80 / 110 / 140 Ży |
| Kamieniołom | 40 / 60 / 80 / 110 / 140 Ka |
| Start zapasu | 500 Dr, 300 Ka, 300 Ży, 50 Zł |
| Pojemność grodu | 1000 / 1000 / 1000 / ∞ (złoto) |

Badania (`ResearchConfig`): baza epoki I **100/50/50/0**, 60 s; epoka II **400/300/200/0**, 30 min; koszt stały w epoce, a ×1,6 kosztu tylko dla doktryn (A1, A2, G1, G2: sama procentowa premia) za każdą wcześniejszą doktrynę epoki; czas ×2 na każde wcześniejsze badanie w epoce.

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
| Przykład palisady / typowe czasy | [[Progresja budowy]]: 15 s L1, „II: 2 min / 30 min” | 10 s L1; mnożniki 1…90; epoka II ×2 | **rozjazd skali** (#262) |
| Premie poziomów 6–10 | „nowa epoka dokłada ulepszenia” | `bonus_level` cap 5 | **brak premii II** do decyzji |
| Koszty jednostek Ży | vault podaje towary, rzadko ilości Ży | stałe 5–20 Ży | vault uzupełniony tą notatką |
| Generałowie | zaktualizowane 22.11 | #273 | zgodne |
| Utrzymanie Ży | opisane przy Wozie | pełna tablica `UPKEEP` | ta notatka |

---

## 2. Krótka analiza problemów

Fakty z kodu i issue, nie odczucia:

1. **Armia vs żywność.** Limit utrzymania działa (#247), ale piechota kosztuje tylko **1 Ży/h** przy produkcji Pola 60–200/h + Rybak + baza 20. Dwór 5 + Koszary 5 ≈ **60 miejsc**, a jedno Pole 5 daje 200 Ży/h — spożywanie nie jest wąskim gardłem przy spamie taniej piechoty (Chłop 5 Ży rekrutacji, 1 utrzymania).
2. **Złoto prawie nie hamuje armii.** Żołnierze nie biorą Zł; 50 start + łup. Generałowie są tani (50 / 80 / 150). Tempo złota zależy od PvP/PvE, nie od produkcji.
3. **Epoka II na liczbach „na teraz”.** Przebudowa 1000/1000/1000 + 12 h; budynki ×2; premie poziomów II nie istnieją (#262). Gracz płaci za epokę, ale nie dostaje nowych bonusów budynków ponad poziom 5.
4. **Skala czasów niespójna z notatką.** Kod: Wieża L5 = 60×90 = 90 min (epoka I); notatka „typowe” 4 min. Albo skracamy kod, albo poprawiamy vault — #262 każe wybrać jedną skalę.
5. **Łańcuch towarów** jest prawdziwym kosztem armii (łuki, konie, skóry), ale tempo przepisów jest tymczasowe i łatwo zapełnia zbrojownię offline (limit catch-up 30 dni).
6. **Generałowie (#273):** XP 20+20 i cap PvE na L2 pchają w PvP — OK projektowo; liczby obniżone 22.11, nadal tymczasowe.

---

## 3. Opcje balansu

A i B to skrajne odniesienia. **Opcja C** to proponowana ścieżka środka (feedback właścicielki 23.11.2026): bez głodu, bez spamu armii, pełny postęp F2P, a reklamy i sklep dają realną korzyść bez soft-locka. Wszystkie zakładają epoki I–II MVP i te same mechaniki (miejsca + utrzymanie). Wdrożenie dopiero po OK właścicielki. Ticket: #262.

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

### Opcja C — „Spokojny rytm” (**propozycja**, pending OK)

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

## 4. Co wybrać dalej (bez decyzji agenta)

**Rekomendacja vaultu:** przyjąć **Opcję C**, ewentualnie z korektą pojedynczych wierszy. A/B zostają jako skrajne odniesienia.

Po OK właścicielki:

1. Wpisać liczby C w `*_config.gd` / `unit_types.gd` / `generals.gd` (generałowie bez zmian).
2. Zsynchronizować serwer (`bonus_level` / premie 6–10) za zgodą właścicielki.
3. Trzymać nagrady ads i sklep w limicie zasady z § Monetizacja; ticket #33 / #174.
4. Zaktualizować tę notatkę i [[Progresja budowy]]; zamknąć #262 checkboxami.

Powiązane: [[00 Start]], [[Plan MVP]], [[Bugs]], [[Model wydania]]
