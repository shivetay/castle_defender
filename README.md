# Castle Defender

Mobilna gra 2D pixelart (Android) z asynchronicznym PvP. Gracze rozbudowują zamki od wałów ziemnych do twierdzy z końca wojen napoleońskich i atakują zamki innych graczy. Cała grafika jest rysowana kodem, bez zewnętrznych assetów.

**Stack:** Godot 4.7 (GDScript), renderer GL Compatibility, eksport na Androida. Backend PvP: Supabase (etap 9, #131; schemat w `supabase/`).

## Stan: etap 9 z planu MVP

Numeracja etapów i zadań idzie za issues na GitHubie (ticket zbiorczy etapu ma etykietę `etap`).
Etapy 1 (szkielet, viewport 320×180, testowy APK) i 2 (teren 64×64 z seeda, siatka budowy, kamera
z gestami) są zamknięte. Etap 3 (#125: paleta epoki I w 16 kolorach #5, autotiling umocnień #6, pięć
budynków z poziomami 1–5 #7, 4 stany zniszczeń #8) jest zrobiony; z #5 zostaje pomiar startu na telefonie.
Etap 4 (#126): HUD z trybami oglądania i budowy (#9), ekonomia (#10), progresja z kolejką budowy
i Dworem jako poziomem zamku (#11), zapis lokalny (#13) i losowy seed mapy dla każdego gracza (#97,
część kliencka). Z etapu 4 zostaje Dwór zmieniający się z epokami i garnizon (#81), który czeka
na jednostki, bitwę i epokę II z późniejszych etapów.
Etap 5 (#127) zaczyna badania z #12: 34 technologie z notatki Drzewko technologiczne z epokami,
zależnościami, efektami i ekranem drzewka. Działają premie G1 i G2 oraz w bitwie A1, A2 i O2, a manewry
wymagają A3–A6; reszta efektów włączy się razem
z budynkami, jednostkami i bitwą. Bazowe koszty badań są tymczasowe (notatka ich nie podaje).
Do tego mechanizm towarów i łańcuchów produkcji z #88 (zbrojownia, przepisy wytwórców według notatki
Klasy jednostek i produkcja) oraz 9 budynków wytwórców z #90, które produkują towary
i wymagają zbadania swojej technologii. Doszły też budynki gospodarcze z #122: Pole lnu i Rybak,
oraz Stajnia z #91 i budynki rekrutacji z #119 (Koszary, Dom drużyny, Strzelnica). Klasy jednostek
z #87: 13 jednostek MVP z klasą, statystykami i kosztem w towarach oraz tabela przewag klas.
Rekrutacja z #89: kolejki szkolenia w budynkach klas, koszt w żywności i towarach, armia z limitem
i ekran Wojsko (globalny z HUD albo z karty budynku rekrutacji).
Etap 6 (#128) zaczyna deterministyczna symulacja bitwy z #14 (logika bez renderu) i donżon jako cel
ataku z #120 (Wieża grodowa obok Dworu; wygrana po jej upadku albo zdobyciu).
Etap 7 (#129) to plan ataku z manewrami (#18) i ekranem planu (#17), a etap 8 (#130) ustawienia obrony
z #19 (posterunki załogi wokół donżonu), zadania obrony (#20) i pułapki (#100). Trwa etap 9 (#131): backend
Supabase i PvP, czyli schemat bazy z RLS (#21), anonimowe konto gracza (#22), synchronizacja zamku
z obroną (#23), dobór przeciwnika z ekranem 3 celów (#24) oraz start i koniec ataku z łupem i tarczami (#25) i atak na gracza w kliencie (#240); stan i kolejne kroki są
w sekcji „Następny etap”.

- `scripts/gfx/palette.gd` (`Palette`): 16 kolorów epoki I w `AGE_I`. Rampy `GRASS`, `WOOD`, `EARTH`,
  `THATCH`, `WATER` to widoki na nią (ziemia i drewno dzielą ciemne brązy). Kolory UI są osobno w `UI`.

- `scripts/gfx/pixel_canvas.gd` (`PixelCanvas`): prymitywy rysowania w rzucie z góry: dach dwuspadowy,
  jednospadowy, namiotowy i czterospadowy (stóg), pomost z desek, stos bali, komin, proporzec, obwódka
  i dithering 2×2.
  Faktura idzie przez `hash2`, a światło pada z lewej góry (połacie od północy i zachodu są jasne).
- `scripts/gfx/building_art.gd` (`BuildingArt`): budynki w rzucie z góry, każdy z 5 poziomami o różnym
  wyglądzie, i 4 stany zniszczeń: cały, pęknięcia, wyrwa, gruz. Obraz ma dokładnie rozmiar kratek
  budynku, więc nic nie zasłania sąsiadów, a wysokość oddaje cień na południowy wschód (dłuższy
  za wieżą, donżonem i Strażnicą, krótki za murem i polem lnu).
  - **Dachy:** chaty, Dwór i warsztaty wytwórców mają strzechę z kalenicą wzdłuż dłuższego boku, warsztaty
    wojska płaski pomost z desek w ramie z belek, a rybak stóg czterospadowy. Wieża i donżon mają dach
    namiotowy, wieża niżej pomost z desek. Rodzaj warsztatu rozpoznaje się po rekwizycie z prawej (kadź,
    tarcza, rama ze skórą, koń przy żłobie...).
  - **Umocnienia:** korona wału (z darnią, fosą, palikami albo płotem) i wierzchy pali palisady z jasną
    stroną od północy. Wał i palisada mają autotiling: odcinek 1×1 to środek plus ramię do każdego sąsiada
    z maski N/E/S/W (16 wariantów), a ramiona dochodzą do krawędzi kratki, więc dowolny kształt łączy się
    bez dziur. Wyrwa wybija bloki 2×2, a gruz leży na kształcie odcinka.
  - **Przybudówki (`Lean`):** chata i warsztaty przy murze dochodzą do niego korpusem i mają dach
    jednospadowy z kalenicą przy murze (wariant wschodni to lustro zachodniego z poprawionym światłem).
    Dwór, wieża, brama, mury i pole lnu zostają bez zmian.
- `scripts/gfx/terrain_renderer.gd` (`TerrainRenderer`, ożywiony w #150): trawa w 4 odcieniach wysokości
  z ziarnem i źdźbłami. Na styku wysokości odcień liczy się z interpolacji środków kratek z szumem,
  więc wzgórze ma miękkie, poszarpane zbocza zamiast schodków. Na trawie są ozdoby z seeda: kępki,
  kwiatki (czerwone, żółte), kamienie i krzaki (`decor_at`). Przy wodzie rośnie trzcina, a ścieżki
  i rzeka mają poszarpane brzegi i zaokrąglone narożniki. Cała mapa liczy się raz, ok. 40 ms (komputer).
- `scripts/gfx/ambient_view.gd` (`AmbientView`, #150): dym z kominów (Dwór i smolarnia zawsze, chaty
  i warsztaty co drugi) i błyski na wodzie. Rysuje się 8 razy na sekundę, nie co klatkę, i nie wpływa
  na symulację.
- Budynki (#150) mają ciemny obrys i światło z lewej góry (bez umocnień, bramy i wieży, które łączą się
  z murem), a pod nimi półprzezroczysty cień na trawie (`BuildingTextures.shadow`).
- `scripts/gfx/building_textures.gd` (`BuildingTextures`): `draw_building(rodzaj, poziom, stan, maska,
  pionowo)` zwraca `ImageTexture` z cache. `warm_up()` rysuje przy starcie 222 całe warianty i place budowy
  (ok. 19 ms na komputerze, headless).
- `scripts/world/building_types.gd` (`BuildingTypes`): Wał ziemny i Palisada (1×1), Brama drewniana (3×1),
  Wieża drewniana, Chata drwala i Dwór (2×2). Wał i palisada łączą się ze sobą nawzajem
  oraz z bramą i wieżą, więc mieszana linia nie ma szpar. Przy wybranym wale lub palisadzie dotknięcie
  kratki obok luki w linii (np. nad nią, gdzie widać wierzch palisady) albo sąsiedniego odcinka do 3 px od
  krawędzi luki stawia odcinek w luce zamiast zaznaczać sąsiada.
  Brama może też stanąć na ciągłej linii wału albo palisady: zastępuje odcinki pod sobą (bez zwrotu
  kosztu), a linia łączy się z nią po obu stronach. Luka w linii ma pierwszeństwo, a odcinki w budowie
  i inne budynki zostają.
  Wieża drewniana też może stanąć na linii wału albo palisady (po teście na telefonie): dotknięty odcinek
  wybiera położenie wieży, które przykrywa najwięcej odcinków, i zastępuje je tak samo jak brama.
  Dwór stoi od startu na środku mapy, jest jeden, nie ma go na pasku budowy i nie da się go rozebrać.
  `state_for_hp(hp, max_hp)` wybiera stan z procentu wytrzymałości: od 76% cały, od 41% pęknięcia,
  od 1% wyrwa, 0 to gruz.
- `scripts/world/build_grid.gd` (`BuildGrid`): rodzaj i poziom budynku (0 = plac budowy), poziom Dworu,
  maski sąsiadów i stała kolejność rysowania (od tyłu do przodu).
  Budynki stoją na trawie. Wyjątkiem jest brama (3 kratki): może stać nad drogą, ale tylko w poprzek niej
  i z drogą pośrodku (pozioma na drodze północ–południe, pionowa na drodze wschód–zachód).
  Budynek stawiany przez gracza do 1 kratki od wału lub palisady dosuwa się do linii bokiem
  (`placement_candidates(..., stick)`, najwięcej kratek styku, potem najbliżej palca). Generator zamku
  bota i wieża tego nie robią. `CastleView.attach_offset` dosuwa teksturę do muru o maks. 6 px, żeby
  na styku nie było szpary.
- `scripts/world/build_config.gd` (`BuildConfig`): koszty i czasy budowy w jednym pliku. Poziom 1:
  Wał 10 Dr 10 Ży 5 s, Palisada 20 Dr 5 Ży 10 s, Brama 60 Dr 20 Ka 20 Ży 30 s, Wieża 120 Dr 40 Ka 40 Ży 60 s,
  Chata 80 Dr 30 Ży 45 s. Poziomy 1–5 mnożą koszt ×1/×1,5/×2,5/×4/×6, a czas ×1/×3/×10/×30/×90.
  Dwór 2–5: 300/200/200 10 min, 500/350/350 1 h, 750/550/550 4 h, 1000/800/800 12 h. Budynek nie może
  mieć wyższego poziomu niż Dwór.
- `scripts/world/build_queue.gd` (`BuildQueue`): jeden budowniczy i do 3 czekających zleceń. Koszt schodzi
  przy zleceniu, nowy budynek od razu zajmuje kratki jako plac budowy, anulowanie oddaje cały koszt
  (do pojemności magazynu), a rozbiórka gotowego budynku nic nie zwraca. Zlecenia kończą się po kolei
  według zegara, także w tle, a ekonomia liczy się odcinkami między ukończeniami.
- `scripts/world/world_seed.gd` (`WorldSeed`), `scripts/world/player_profile.gd` (`PlayerProfile`): seed
  zamku na stałe przypisany do gracza. Seed gracza losuje się raz z `Crypto` (31 bitów, nie z czasu)
  i zostaje w `user://player.json`, osobno od zapisu zamku, więc nowa gra po utracie zapisu daje ten sam
  zamek. Seed zamku wynika z seeda gracza i jest też w `world_seed` zapisu; stare zapisy przekazują swój
  seed do profilu. Od etapu 8 seed gracza przejdzie na konto. Mapa z seeda przechodzi
  walidację: Dwór mieści się do 6 kratek od środka wzgórza, a od Dworu biegnie droga do krawędzi mapy
  z miejscem na bramę. Gdy nie, kolejne seedy wynikają deterministycznie z pierwszego (do 32 prób,
  potem seed zapasowy 1337). W wersji debug seed wymusza `godot --path . -- --seed=42`; wymuszony seed omija walidację,
  więc da się nim odtworzyć także mapę niegrywalną.
- Onboarding (#228, `scripts/ui/onboarding_panel.gd`, `OnboardingPanel`): przy pierwszym uruchomieniu
  zamek przykrywa najpierw ekran Wybierz władcę: 5 portretów w rzędzie (`Rulers.SLOTS`), z których na razie
  tylko pierwszy to władca (Kasztelan), a 4 to szare, puste miejsca na postacie z #31 i #32. Dotknięcie
  portretu pokazuje pod nim nazwę i premie (Kasztelan: Brak premii, puste: Wkrótce), a Wybierz (wyszarzone
  przed dotknięciem i na pustym miejscu) przechodzi do ekranu z polami Imię i Zamek. Linia „Władca: … · zmień”
  wraca do wyboru. Tekst wpisuje się klawiaturą systemową (ukryty `LineEdit`
  odbiera klawiaturę ekranową, tekst rysuje `PixelFont`), Enter przechodzi do następnego pola, a Zacznij
  sprawdza nazwy: imię 3–12 znaków, nazwa zamku 3–16, tylko litery z fontu (także polskie), cyfry,
  spacja i łącznik. Tożsamość (imię, nazwa zamku i władca) leży w profilu `user://player.json` (wersja 2)
  obok seeda gracza; Zacznij od nowa jej nie kasuje. Władca to na razie tylko domyślny Kasztelan bez
  premii (`scripts/world/rulers.gd`, `Rulers`); generałowie (#31) i perki (#32) dojdą jako kolejne wpisy.
  Po onboardingu w lewym górnym rogu HUD-u (pod paskiem celu) stoi portret władcy w okręgu 22×22 px
  (`scripts/gfx/portrait_art.gd`, `PortraitArt`: wzór w kodzie, złoty pierścień, tekstura w cache).
  Dotknięcie portretu otwiera okienko z graczem, zamkiem i premiami władcy. Skóra portretu to
  `Palette.SKIN` w kolorach UI.
  Bez tożsamości zamek nie idzie na serwer. Z synchronizacją (#23) imię trafia do `players.nickname`,
  a cała tożsamość do `castles.data.profile`, więc wraca razem z zamkiem.
- `scripts/world/tech_tree.gd` (`TechTree`): 34 technologie MVP z notatki Drzewko technologiczne
  (`docs/castle-defender-vault/`) w gałęziach Atak (19), Obrona (3), Gospodarka (9), Użyteczne (1)
  i Specjalne (2). Każda ma epokę, efekt, znacznik technologii kluczowej ★ (O1 dla I → II, G6 dla II → III)
  i zależności z notatki. Epoka II: A5, A6, A22, A46, A47, G4, G6. Działają premie G1 +20% drewna
  i G2 +15% żywności (`PRODUCTION_BONUS`). W bitwie (`Battle.apply_research`, osobno dla każdej strony)
  działają A1 (wojownik z toporem +15% w drewno), A2 (łuki +20% zasięgu: łucznik 6 → 7, łuk refleksyjny
  7 → 8) i O2 (palisady obrońcy +20% wytrzymałości). Manewry wymagają technologii: Podpalenie A3,
  Oskrzydlenie A4, Drabiny A5, Taranowanie A6 (na liście Manewr są wyszarzone z tym, czego brakuje).
  Jednostki i budynki wymagają swoich technologii już wcześniej. Bez efektu zostają technologie, których
  rzecz jeszcze nie istnieje: O1 Kopiec, O3 fosa, G4 Kamieniołom, S2 Wieża sygnałowa (#35), S1 zwiad (#28),
  G6 przejście do epoki III.
- `scripts/world/research_config.gd` (`ResearchConfig`): koszt i czas badań. Każda kolejna technologia
  w epoce ×1,6 kosztu i ×2 czasu (#12). Bazowe liczby (epoka I: 100 Dr 50 Ka 50 Ży, 1 min) są tymczasowe.
- `scripts/world/research.gd` (`Research`): zbadane technologie i jedno badanie naraz. Badanie wymaga
  epoki i zbadanych zależności, koszt schodzi przy starcie, a koniec liczy się z zegara, także w tle.
  Kolejka budowy kończy budowy i badanie w porządku czasu, więc premia liczy się od chwili zbadania.
  Badanie wymaga też gotowego budynku badań swojej gałęzi (#165, `ResearchConfig.BRANCH_BUILDINGS`):
  Atak bada się w Koszarach, Obronę, Gospodarkę, Użyteczne i Specjalne w Dworze, bo Targu, Kaplicy,
  Szpitala, Arsenału, Wieży sygnałowej i Sztabu jeszcze nie ma. Dom zwiadowców przejmie Specjalne
  od epoki II, ale nie S3, które go odblokowuje. Ekran badań pokazuje brakujący budynek na czerwono.
- `scripts/world/goods_config.gd` (`GoodsConfig`): 22 towary epok I–II (skóry, kość, ścięgna, pióra, len,
  zbroje, przeszywanice, tarcze, mokre skóry na Taran, broń drzewcowa, cięciwy, łuki, strzały, siodła,
  uprząż, smoła, konie) i przepisy 11 wytwórców według notatki Klasy jednostek i produkcja. Bez metalu.
  Zbrojownia ma limit jak magazyn surowców (1000). Ilości w przepisach i tempa są tymczasowe (notatka
  zostawia je balansowi); budynki przypisze do wytwórców #90 (`PRODUCER_KINDS`).
- `scripts/world/goods.gd` (`Goods`): zbrojownia i produkcja w czasie, także offline. Cykl przepisu
  zużywa surowce i towary; brak wejścia albo pełna zbrojownia go zatrzymuje. Wyższy poziom budynku
  przyspiesza i odblokowuje lepszy towar (Łukmistrz 3 → łuk refleksyjny). Pusta zbrojownia strzał
  to −50% tempa strzelania (dla bitwy, #14).
- Wytwórcy (#90): Chata myśliwego, Garbarnia, Wytwórca zbroi skórzanych, Drzewcarz, Cięciwiarz, Łukmistrz,
  Strzałmistrz, Rymarz i Smolarnia (2×2, za Dworem w `BuildingTypes.Kind`, żeby numery w zapisach się nie
  zmieniły). Na pasku budowy (`BUILD_BAR`) są wyszarzone, dopóki nie zbadasz technologii z
  `BuildConfig.REQUIRED_TECH` (G18, G19, A38–A43, G24). Grafika: wspólny warsztat (wiata na poziomie 1,
  potem izba z bali albo desek, szersza od poziomu 4, z flagą na 5) i rekwizyt rozpoznawczy z prawej:
  skóra na ramie, kadź, tarcza, drzewca, sznury cięciw, łuk, beczka strzał, siodło, mielerz.
  Koszty i czasy są tymczasowe, w skali Chaty drwala.
- Budynki gospodarcze (#122): Pole lnu (G20) daje len do zbrojowni dla Cięciwiarza i przeszywanic;
  Rybak (G21) daje żywność i staje tylko tak, żeby bokiem stykał się z rzeką (`BuildGrid.touches_water`).
  Pole to płaska grządka: siewki, rzędy, kwitnący len, snopki, strach na wróble. Rybak to warsztat z siecią,
  rybami i łódką. Stawki są tymczasowe.
- Stajnia (#91): od początku epoki I (bez technologii), z żywności hoduje konie do zbrojowni; z siodłem
  od Rymarza to wyposażenie klasy szybkiej. Rekrutacja konnicy dojdzie w #89. Grafika: warsztat z koniem
  przy żłobie, od poziomu 4 dwa konie. Koszt i tempo tymczasowe.
- Budynki rekrutacji (#119): Koszary (klasa lekka, od początku epoki I), Dom drużyny (ciężka, A45)
  i Strzelnica (strzelecka, A44); szybką szkoli Stajnia. `RecruitmentConfig` trzyma klasę każdego budynku
  oraz limit i tempo szkolenia od poziomu (tymczasowe); Dwór nie rekrutuje. Samo szkolenie dojdzie w #89.
  Grafika: warsztat z manekinem do ćwiczeń, tarczami drużyny albo słomianą tarczą strzelniczą.
- Dom zwiadowców (#92): budynek epoki II w zakładce Wojsko, odblokowuje go S3 (po S1 Tropiciele).
  Szkoli tylko Zwiadowcę. Grafika: warsztat z czatownią (żerdź z pomostem i rogiem sygnałowym),
  a od poziomu 4 z proporcem. Koszt i czas są tymczasowe.
- `scripts/world/unit_types.gd` (`UnitTypes`): 15 jednostek, czyli 13 jednostek MVP oraz Chłop i Zwiadowca
  (opisani niżej), z notatek Jednostki oraz Klasy jednostek
  i produkcja: klasa (lekka, ciężka, strzelecka, szybka, specjalna; Taran i Kopacz to inżynieria), HP, atak,
  zasięg, szybkość, technologia, budynek rekrutacji i koszt w towarach (np. Łucznik: łuk i 20 strzał).
  Tabela przewag klas (`ADVANTAGE`, procenty) i ×2 drzewca przeciw konnicy; `duel()` to pojedynek w turach
  na liczbach całkowitych do testów, pełna bitwa to #14. Ikony klas 5×5 w `PixelIcons.CLASSES`.
  Do tego Chłop (pospolite ruszenie, jednostka poziomu 0): lekka piechota z Koszar bez technologii
  i bez towarów, za 5 żywności, tylko w epoce I (`ERA_I_ONLY`); stoi pierwszy na ekranie Wojsko.
  Statystyki tymczasowe.
  Do tego Zwiadowca (#92): konny zwiad epoki II, klasa specjalna, 35 HP, atak 2, szybkość 5, wymaga S3.
  Kosztuje konia ze Stajni, siodło od Rymarza i 15 żywności (ilość żywności tymczasowa). Sam zwiad przed
  atakiem dojdzie w #28.
  Każda jednostka ma krótki opis roli (`ROLES`) i linię przewag liczoną z tabeli klas
  (`counters_text`: przeciw komu jest silna i kto ją kontruje); na ekranie Wojsko pokazuje je przycisk Opis.
- `scripts/world/recruitment.gd` (`Recruitment`): armia w oddziałach i kolejki szkolenia (#89). Oddział ma
  jeden rodzaj jednostek i najwyżej 10 jednostek (tymczasowe); nowa jednostka idzie do wskazanego oddziału
  tego rodzaju albo do nowego. Globalny limit armii to tyle, ile zamek może teraz utrzymać: 10 za poziom
  Dworu i 2 za poziom Koszar (tymczasowe); limit i miejsca w oddziale liczą też szkolonych. Każdy budynek
  szkoli po kolei jednostki ze swojej kolejki (długość i tempo rosną z poziomem), także offline. Koszt
  w surowcach i towarach schodzi przy zleceniu; bez towaru szkolenie nie rusza. Jednostka szkoli się
  tylko w budynku swojej klasy. `start_any()` dla widoku globalnego wybiera budynek z najkrótszą kolejką.
- `scripts/ui/recruit_panel.gd` (`RecruitPanel`): ekran Wojsko. Przycisk Wojsko w HUD (obok Oblężenia)
  pokazuje wszystkie jednostki; Szkol na karcie budynku rekrutacji tylko jednostki tego budynku.
  Nagłówek: zajęte miejsca, limit i wolne miejsca w armii. Kafelki z ikoną klasy, liczbą w armii
  i w szkoleniu; zablokowane przygaszone z powodem (technologia, epoka, brak budynku); brakujące towary
  na czerwono z budynkiem, który je robi. Długie teksty (nazwa, koszt, braki) zawijają się po słowach
  (`PixelFont.wrap`) w 4 liniach szczegółów; braki towarów, pogrupowane według budynku, który je robi,
  mają do 2 linii. Przycisk Opis przełącza szczegóły: koszt → opis jednostki (rola, przewagi) →
  produkcja cywilna postawionych wytwórców (np. Chata drwala +Dr/h, Drzewcarz z tempem towarów z
  `EconomyConfig` / `GoodsConfig`) → zapas zbrojowni (towary używane przez jednostki, ilości z
  `goods.amounts`) → z powrotem koszt. Pod nimi rząd wyboru oddziału na całej szerokości treści:
  Nowy albo oddziały tego rodzaju („2: 7/10”), pełne przygaszone; domyślnie pierwszy oddział
  z wolnym miejscem.
- `scripts/battle/battle.gd` (`Battle`): deterministyczna symulacja bitwy (#14). Stały krok 30 Hz, pozycje
  w podjednostkach kratki (256 na kratkę), tylko liczby całkowite, własny RNG (`BattleRng`, xorshift32)
  i ścieżki z AStarGrid2D, w którym budynki są drogie, ale przechodnie: atakujący burzą najsłabsze miejsce
  linii umocnień. Atakujący idą do celu i walczą z obrońcami po drodze, obrońcy trzymają pozycję przy celu,
  wieże strzelają (wolniej bez strzał w zbrojowni). Koniec: cel zniszczony, atakujący wybici albo limit
  180 s. `checksum()` daje sumę kontrolną stanu do testów i przyszłej weryfikacji na serwerze. Liczby
  w `BattleConfig` (poza palisadą) tymczasowe.
- Donżon (#120): Wieża grodowa stoi od startu obok Dworu (starsze zapisy dostają ją przy wczytaniu), nie ma
  jej na pasku, nie da się jej rozebrać ani ulepszyć (#232; karta ma sam przycisk Zamknij, a donżon
  ulepszony w starszym zapisie zostaje na swoim poziomie). Z załogą strzelców strzela w bitwie jak wieża
  drewniana (#232): gdy najwyżej 2 kratki od niego stoi żywy, niewycofany strzelec obrońcy, ma ten sam
  zasięg, obrażenia, priorytet celów i wolniejsze tempo bez strzał w zbrojowni. Sama piechota go nie
  obsadza, więc fale samouczka na Chłopach się nie zmieniają. Promień załogi jest tymczasowy. `Battle.for_castle()` bierze ją
  za cel: atakujący wygrywa po jej upadku albo zdobyciu (piechota lekka lub ciężka trzyma się przy niej
  10 s bez obrońców w pobliżu). Zniszczenie Dworu bitwy nie kończy. Walidacja seeda mapy (#97) sprawdza
  też miejsce na donżon. Grafika: wieża z bali na ziemnej podmurówce, z gankiem od poziomu 3.
- Jednostki w bitwie (#15, #92): bitwa przyjmuje oddziały z rekrutacji (`Battle.create_squads`,
  `Recruitment.battle_squads()`); symulacja liczy każdą jednostkę osobno, ale zna jej oddział. Cechy
  z notatki Jednostki: Tarczownik (−40% od strzał dla siebie i sąsiadów), Drużynnik w przeszywanicy
  (−25% wręcz), Kopijnik (szarża ×2 w pierwszym uderzeniu), Wojownik z toporem (×1,5 w drewno),
  Taran (bije tylko bramy, jedzie do najbliższej), Jeździec (omija wolne cele), Oszczepnik (rzut
  z 3 kratek), Podpalacz (podpala drewniane budynki na 10 s). Wartości w `BattleConfig`, część
  tymczasowa. `BattleView`: jednostki nie są ludzikami, oddział to ikona klasy w ramce koloru strony,
  liczba żywych i pasek zdrowia; odznaka stoi na jednej z jednostek oddziału (nie w jego średniej), a każda
  jednostka ma kropkę 2×2 w kolorze strony. Odznaki nie nachodzą na siebie, a zepchnięta niżej trzyma wiersz
  (bez skakania co klatkę). Mapa w bitwie rysuje stan zniszczeń budynków (pęknięcia, wyłomy, gruz). Podgląd w wersji debug:
  `godot --path . -- --battle-preview`; w grze bitwę uruchamia samouczek (#16) i Wyprawa (#26).
- Samouczek PvE (#16, `scripts/battle/pve_waves.gd`): Oblężenie startuje kolejną z 5 fal o rosnącej
  trudności (od 3 Chłopów do armii z konnicą). Fala idzie z drogi przy krawędzi mapy na
  donżon, a bronią go wyszkolone oddziały (`Battle.for_castle_squads`, premia U1). Bez wojska fala nie
  rusza. W trakcie fali kolumna ma tylko Tempo (×1, ×2, ×4), a górny pasek pokazuje czas do limitu. Wygrana
  daje surowce i odblokowuje następną falę; postęp jest w zapisie (wersja 5). Polegli obrońcy
  znikają z armii razem z wyposażeniem (Jeździec z koniem), a ocalali, także wycofani, wracają do swoich
  oddziałów (#164). Budynki nie niszczą się na stałe. Skład fal i nagrody są tymczasowe.
- Prowadzenie do 5 fal (#185, `scripts/world/tutorial_goals.gd`): pod górnym paskiem HUD-u pasek „Cel:”
  z kolejnym krokiem, liczonym z gry (bez zapisu): Koszary i 6 żołnierzy, np. Chłopów (fala 1), 10 żołnierzy (fala 2),
  A39 i Drzewcarz z toporami (fala 3), łańcuch łuczników (G18, Chata myśliwego, A40, Cięciwiarz, A41,
  Łukmistrz, A42, Strzałmistrz, A44, Strzelnica), brama na drodze i 4 odcinki palisady (fala 4), Dwór 2
  i armia 10 toporników, 6 łuczników, 6 oszczepników (fala 5). Gdy kroki danej fali są zrobione, celem
  jest Oblężenie. Cele tylko podpowiadają, Oblężenia nie blokują. Po 5. fali komunikat sukcesu z nagrodą i koniec
  prowadzenia. Test sprawdza, że obrona z tej ścieżki z bramą, palisadą i zadaniami domyślnymi wygrywa
  każdą falę na kilku mapach.
- Morale (#98): każdy oddział ma morale 0–100 (liczby całkowite, start 70). Poległy zabiera
  oddziałowi 80 / początkowa liczebność, więc oddział łamie się po stracie ponad połowy ludzi.
  Poniżej 30 oddział sam się wycofuje na swoją kratkę startową i już nie walczy; gdy wycofają się
  wszyscy atakujący, bitwa kończy się wygraną obrońcy (`ATTACKERS_ROUTED`). Powyżej 80 oddział
  zadaje +10% obrażeń (co najmniej +1). Wycofani omijają żywe budynki. U1 Wiec grodowy daje załodze +5
  (`Battle.for_castle(..., research)` dolicza to samo),
  a `add_squad_morale` jest gotowe na śmierć generała (−20, #31/#32). W widoku bitwy nad ikoną
  oddziału jest złoty pasek morale (czerwony poniżej progu). Start i strata za poległego są tymczasowe.
- Plan ataku i manewry (#18, `scripts/battle/attack_plan.gd`, notatka Manewry i zadania): każdy oddział
  atakującego dostaje przed bitwą rozkaz i wykonuje go sam.
  - **Manewry:** Szturm frontalny, Ostrzał z dystansu, Podpalenie, Oskrzydlenie, Szturm z drabinami
    i Taranowanie bramy (dwa ostatnie od epoki II).
  - **Jednostki:** manewr musi pasować do jednostek oddziału (`AttackPlan.unit_can`): Ostrzał tylko
    z zasięgiem 3+ kratek, Podpalenie tylko Podpalacze, Drabiny piechota lekka i ciężka, Taranowanie
    Taran i piechota w osłonie, Oskrzydlenie wszyscy poza Taranem. Zmiana składu armii cofa niepasujący
    rozkaz do Szturmu, a Atakuj odrzuca plan z takim rozkazem.
  - **Parametry:** cel (kratka budynku), trasa (0–3 punkty), start (od razu, po X s, po zadaniu innego
    oddziału) i odwrót (przy X% strat).
  - **Limit:** plan mieści 3 oddziały w epoce I, do 8 w epoce VI.
  - `Battle.set_plan()` przyjmuje plan; bez planu wszyscy idą jak dotąd, czyli Szturmem frontalnym
    na donżon. Plan to liczby całkowite z zapisem do słownika, więc przebieg jest powtarzalny.
  - Czas wspinaczki po drabinie, odsunięcie obejścia i promień osłony taranu są tymczasowe.
- Ekran planowania ataku (#17, `scripts/ui/attack_planner.gd` i `attack_panel.gd`): Wyprawa na karcie
  Strażnicy otwiera wybór zamku-bota (najpierw zwarta lista, Planuj rozwija, kolejne Planuj
  otwiera mapę zamku-celu).
  - **20 zamków-botów (#26, `scripts/battle/bot_roster.gd`):** lista wspólna dla wszystkich graczy
    (seed z numeru zamku; w etapie 9 przejdzie do bazy), z nazwami. Trudność rośnie: poziom budynków
    1–5 (co 4 zamki), do 4 wież, budynki rekrutacji (Koszary od 4., Strzelnica od 7., Dom drużyny
    od 10., Stajnia od 13.), gród na wale zamiast palisady w zamkach 2, 4, 6, 8 i 10, zewnętrzny wał od 11.
    i załoga z coraz większej liczby klas (od 4 Chłopów
    do 77 obrońców). Zamki 16–20 to epoka II: bronią ich też Włócznicy, Drużynnicy, Strzelcy z łukiem
    refleksyjnym i Kopijnicy. Liczby tymczasowe.
  - **Trzy cele (#24, `scripts/ui/target_picker.gd`):** Wyprawa otwiera najpierw 3 karty celów. Karta ma
    portret władcy, imię gracza, epokę, nazwę zamku, miniaturę zamku 32×32 (teren z seeda i zarys
    budynków jednym kolorem, bez rodzajów, wojska i pułapek, które odsłoni zwiad z #28), ranking
    (u bota trudność) i szacowany łup. Graczy dobiera serwer; brakujące karty, a bez sieci wszystkie,
    zajmują boty: bieżący cel kampanii, potem zdobyte zamki, a nowy gracz dostaje kolejne z listy.
    Boty otwiera pełną listę 20 zamków (niżej), Planuj plan ataku na bocie. Planuj na karcie gracza
    (#240, `scripts/battle/player_castle.gd`) zaczyna atak na serwerze (`start_attack`) i otwiera plan
    na kopii jego zamku i obrony z chwili startu; bitwa idzie z seedem z serwera, a łup trafia do magazynu
    dopiero z odpowiedzi `finish_attack` (przy odrzuceniu albo braku sieci po 4 próbach wynik jest bez łupu).
    Zajęty cel, tarcza, limit startów i brak sieci kończą się komunikatem, a armia zostaje nietknięta.
    Plan ma 7 minut od startu (serwer przyjmuje wynik do 10 minut), a armia musi być ta sama co przy starcie.
  - **Lista botów (`scripts/ui/bot_picker.gd`):** najpierw zwarta lista odblokowanych zamków (mniej
    ekranu); Planuj rozwija siatkę 5×4 z numerami (zdobyte na zielono, epoka II z czerwonym znacznikiem)
    i opisem, kolejne Planuj otwiera plan ataku. Zamek odblokowuje się po zdobyciu poprzedniego.
    Zdobyte można atakować znowu, bo po ataku zamek wraca do pełnego stanu, więc gracz zawsze ma cel.
    Wybrany cel jest w zapisie (`attack.target`).
  - **Zamek-cel:** `BotCastle` buduje zamek z listy: Dwór i donżon w palisadzie (albo wale) z bramą
    od strony drogi, chaty, wieże i budynki rekrutacji poza pierścieniem oraz załogę. Pierścień jest
    szczelny: tam, gdzie przecina go droga, stoi odcinek muru (bez drugiej bramy).
  - **Ekran:** strefa rozstawienia przy wejściu, strzałki planu i pasek oddziałów (w ataku pierwsze
    3 oddziały armii, limit epoki I). Przyciski: Manewr, Start (od razu, po 10/20/30 s, po oddziale),
    Odwrót (nigdy, 30/50/70% strat), Wyczyść, Atakuj i Wróć. Manewr otwiera listę 6 manewrów:
    dostępne z krótkim opisem, niedostępne wyszarzone z tym, czego brakuje (jednostka, epoka, badanie).
  - **Dotyk mapy:** budynek to cel, trawa to punkt trasy (do 3).
  - **Zapis:** plan jest w save'ie (wersja 6 z migracją). Po ataku polegli znikają z armii.
  - **Łup:** wygrany atak daje łup z zamku-bota (#99, opis w „Wynik ataku” niżej). Strefa rozstawienia
    jest jedna, przy drodze.
- Ustawienia obrony (#19, `scripts/battle/defense_plan.gd` i `scripts/ui/defense_panel.gd`): przycisk
  Obrona w kolumnie otwiera własny zamek w trybie edycji.
  - **Posterunki:** oddział załogi z rekrutacji dostaje kratkę w strefie 10 kratek wokół donżonu (na trawie,
    nie w wodzie i nie na budynku). W bitwie staje wokół niej i wraca tam, gdy nie ma wroga w zasięgu
    wzroku. Oddział bez posterunku stoi jak dotąd przy donżonie. Złamany oddział (#98) wycofuje się
    pod donżon, także z wysuniętego posterunku. Promień strefy jest tymczasowy.
  - **Ekran:** strefa obrony na mapie, znaczniki posterunków z ikoną klasy, pasek oddziałów (Dalej
    przewija, gdy oddziałów jest więcej niż 6) i opis wybranego oddziału. Dotknięcie trawy ustawia
    posterunek wybranego oddziału, dotknięcie cudzego posterunku wybiera jego oddział. Przyciski: Zdejmij
    (oddział wraca pod donżon) i Gotowe.
  - **Bitwa:** posterunki działają w falach samouczka i w podglądzie bitwy (`Battle.create_squads(...,
    defender_orders)`). Bez posterunków przebieg jest identyczny jak przed #19.
  - **Zapis:** układ jest w save'ie (wersja 7 z migracją), przypisany do id oddziału, więc nowy oddział
    nie przejmuje cudzego posterunku, a posterunek rozwiązanego oddziału znika.
- Zadania obrony (#20, krok A planu zatwierdzonego przez właściciela; notatka Manewry i zadania):
  przycisk Zadanie na ekranie Obrona daje oddziałowi zadanie z listy predefiniowanej, jak manewry ataku.
  - **Obrona odcinka:** oddział stoi na swoim miejscu (trawa albo kratka tuż przy dotkniętym odcinku wału,
    palisady, bramy czy wieży, od strony donżonu). Bije wrogów w zasięgu, ściga tylko tych, którzy podeszli
    na 4 kratki (`BattleConfig.HOLD_RADIUS`, tymczasowe), i wraca na miejsce. Posterunki z #19 to właśnie
    to zadanie.
  - **Patrol:** oddział krąży między 2–3 punktami (kolejne dotknięcia mapy; czwarte zaczyna trasę od
    nowa), bije wroga w zasięgu wzroku i wraca na trasę. Trasa jest na mapie jako pętla.
  - **Priorytet celów wież:** przycisk Wieże (najbliższy, taran, strzelcy, konnica). Wieża bije
    najbliższego z wybranej grupy, a bez takiego w zasięgu najbliższego.
  - **Zapis:** wersja 8 z migracją; posterunki z wersji 7 stają się Obroną odcinka.
  - **Na murze:** strzelec z Obroną odcinka na wale albo palisadzie (dotknięcie muru) stoi na samym
    murze, a kolejni z oddziału na sąsiednich odcinkach tej linii (reszta pod murem). Ma +1 kratkę zasięgu
    i 60% obrażeń od strzał, a wręcz dosięgnie go tylko atakujący po drabinie. Gdy odcinek padnie, zostaje
    na gruzie i walczy z ziemi; złamany schodzi z muru i wycofuje się pod donżon. Liczby tymczasowe.
  - **Wypad konnicy** (od epoki II, jak w notatce): konnica czeka tuż za wskazaną bramą. Gdy atakujący
    podejdzie na 2 kratki do bramy albo brama padnie, wychodzi przez nią (własna brama to dla niej
    przejście), bije wrogów do 6 kratek od bramy i wraca. Liczby tymczasowe.
  - **Przed murami** (konnica, od epoki I, prośba właściciela): oddział stoi na wskazanej trawie, także
    na zewnątrz murów, bije wrogów do 6 kratek od miejsca i wraca; przez własne bramy przejeżdża, przez
    mury nie. Liczba tymczasowa.
  - **Przy donżonie:** jawne zadanie dla oddziału, który ma stać jak przed #19.
  - **Zadania domyślne** (oddział bez ustawionego zadania, plan zatwierdzony przez właściciela):
    strzelcy na odcinek muru najbliżej bramy, piechota lekka i ciężka przy bramie od środka, konnica na
    wypad (w epoce I trzyma bramę jak piechota), specjalni przy donżonie. Bez bramy i murów w strefie
    wszyscy stoją przy donżonie, więc wczesne fale samouczka się nie zmieniają. Ekran Obrona pokazuje
    zadanie domyślne w opisie i miejsce na mapie w przygaszonej ramce; Zdejmij wraca do domyślnego.
    Zamki-cele (`BotCastle`) nie dostają jeszcze zadań domyślnych.
  - **Dalej:** Gaszenie pożarów przeszło do Studni (#35), komendant do generałów (#31).
- Pułapki (#100, `scripts/battle/trap_config.gd`, lista w notatce Budynki/Obrona, zatwierdzona przez
  właściciela): Wilczy dół, Kolczatka, Zrzucane kłody, Płonące strzały i Wrząca smoła (epoka II). Każda
  wymaga technologii, a większość budynku (np. Wilczy dół: G18 i Chata myśliwego). Przycisk Pułapki na
  ekranie Obrona przełącza pasek na rodzaje: dotknięcie kratki stawia wybraną (koszt w surowcach i towarach
  schodzi od razu), dotknięcie pułapki ją usuwa (bez zwrotu), Załoga wraca do oddziałów. Miejsce zależy od
  rodzaju (trawa, przed murem, przy murze albo wieży, przed bramą), a limit to 2 na poziom Dworu. W bitwie
  (`Battle.arm_traps`) każda działa raz, a po bitwie odnawia się za darmo, bo układ się nie zmienia.
  Atakujący jej nie widzi; pole `revealed` czeka na zwiad (#28). Zamki-cele nie mają jeszcze pułapek.
  Liczby tymczasowe.
- Baza PvP (#21, `supabase/migrations`): Supabase (Postgres) z RLS na każdej tabeli i jawnymi uprawnieniami.
  - **Tabele:** `players` (konto, także anonimowe; ranking i epoka), `castles` (stan gry w JSON z wersją formatu,
    licznikiem zmian i stałym `map_seed`), `defense_layouts`, `bot_castles` (20 zamków-botów z seedem z
    `BotRoster`, #26), `attacks` (seed terenu obrońcy `map_seed`, seed bitwy, rozkazy, wynik, łup oraz kopie
    obrony i zamku obrońcy i armii atakującego z chwili startu; z nich liczy się bitwa), `shields`, `ad_rewards`.
  - **Dostęp gracza:** czyta i zapisuje tylko swój zamek, obronę i nick. Nie zmieni seedu terenu, licznika
    zmian, rankingu ani epoki i nie usunie zamku. Ataki, tarcze i nagrody tylko czyta (swoje); zapisuje je
    serwer (Edge Functions, #25, #33). Kopii obrony i zamku z ataku klient nie czyta (pułapki obrońcy
    są ukryte do zwiadu, #28). Listę zamków-botów czyta każdy, także bez logowania.
  - **Wyzwalacze:** konto Auth zakłada wiersz gracza; zapis zamku albo obrony podbija `revision`.
  - **Testy:** `supabase/tests/database/rls_test.sql` (50 testów pgTAP), np. obcy gracz nie zmieni cudzego zamku,
    `anon` nie czyta danych graczy, a serwer zapisuje ataki, tarcze i nagrody.
- Klient Supabase (#22, `scripts/net/`): przy starcie gra zakłada anonimowe konto gracza
  (`/auth/v1/signup`), trzyma sesję w `user://session.json` i odświeża token przed wygaśnięciem.
  - **Offline:** bez sieci gra działa jak dotąd, a klient ponawia próby co 5 s, 15 s, 30 s… do 5 min.
    Odrzucony token odświeżania oznacza nowe konto (anonimowego nie da się odzyskać).
    „Zacznij od nowa” zostawia konto (ten sam gracz), a nowy zamek nadpisuje stary na serwerze.
  - **Seed mapy (#166):** pierwszy zapis zakłada `castles` z `map_seed` (INSERT); kolejne zmieniają
    tylko `save_version` i `data`. Edge Function `start_attack` zwraca `map_seed`
    obrońcy osobno od `battle_seed`; atakujący buduje teren z `AttackStart.terrain_map`.
  - **Synchronizacja zamku (#23, `CastleSync`):** zamek (budynki, ekonomia, kolejka, badania, towary,
    armia, plan ataku, tożsamość w `profile`) idzie do `castles.data`, a układ obrony (zadania, pułapki,
    priorytet wież) także do `defense_layouts`, z którego `start_attack` robi kopię. Przy połączeniu klient
    raz czyta swój zamek, potem zapisuje najwyżej co 15 s (przy wyjściu z gry od razu) z filtrem
    `revision=eq.<znana rewizja>`; rewizję zna telefon z `user://sync.json`.
  - **Konflikty:** zapis, który nie trafił w wiersz (ktoś zapisał w międzyczasie), czyta zamek od nowa.
    Serwer wygrywa, gdy ma nowszą rewizję niż ta, od której zaczął stan na telefonie (kopia zapasowa,
    drugi telefon); wtedy zamek wraca na telefon i scena wczytuje się od nowa. Start bez zapisu
    (reinstalacja, to samo konto) przywraca zamek, seed terenu i tożsamość z serwera. Wyjątki: „Zacznij
    od nowa” nadpisuje zamek na serwerze, gra sprzed #23 z postępem wysyła swój zamek, a zamku
    zapisanego nowszą wersją gry (`save_version` wyższa niż nasza) klient nie rusza.
  - **Dobór przeciwnika (#24, `TargetSearch`):** Edge Function `find_targets` bierze id gracza z tokenu
    i woła `match_targets`: do 3 graczy bez aktywnej tarczy, z epoką ±1 i rankingiem ±100, z zamkiem
    po onboardingu, których gracz nie atakował w ostatnich 24 h, w losowej kolejności. Funkcję SQL
    może wykonać tylko serwer (`service_role`), najwyżej 20 razy na 10 minut na gracza (potem 429
    i same boty z napisem „Za często”). Odpowiedź ma nick, nazwę zamku, władcę, epokę, ranking,
    seed terenu, zarys budynków i łup szacowany jako 5% zapasów (w dół do dziesiątek). Klient czyści
    nazwy jak w onboardingu i przycina liczby oraz zarys, bo to dane od innych graczy.
  - **Konfiguracja:** adres i klucz publishable w `config/supabase.json` (poza repo, wzór w
    `config/supabase.example.json`). Działa tylko nowy klucz `sb_publishable_…` (w grze i w CI);
    z kluczem serwera albo dawnym kluczem JWT klient się nie łączy. APK z CI dostaje plik ze zmiennych
    repozytorium `SUPABASE_URL` i `SUPABASE_PUBLISHABLE_KEY`.
  - **Ustawienia** pokazują stan: offline, łączenie, połączono albo brak sieci.
- Wynik ataku (#99, `scripts/battle/battle_result.gd`, okno `scripts/ui/result_panel.gd`): liczony tylko ze
  stanu skończonej bitwy, w liczbach całkowitych (ten sam u atakującego, w powtórce i na serwerze).
  - **Procent zniszczeń:** zburzone budynki bez odcinków wału i palisady.
  - **Gwiazdki:** brama zdobyta (zburzona brama albo atakujący na murze po drabinie), połowa zamku
    (od 50%) i donżon (zburzony albo zdobyty, czyli wygrana).
  - **Łup z zamku-bota, tylko po wygranej:** skarbiec 1000 + 500 × numer drewna, kamienia i żywności oraz 20 + 10 × numer
    złota; połowę chroni magazyn, z reszty do 20% w proporcji do zniszczeń (wygrana liczy się co najmniej
    jak 50% zniszczeń); ponowny atak na zdobyty
    zamek daje połowę. Łup wchodzi do magazynu do jego pojemności. Liczby tymczasowe.
  - **Okno wyniku:** tytuł, gwiazdki, procent, spełnione warunki, łup, polegli i odblokowany zamek.
  - **Odbudowa:** bitwa działa na kopii budynków, więc zamek obrońcy po bitwie jest w pełnym stanie.
    Ranking (#27) i tarcza obrońcy (#25) dojdą z PvP.
- Efekty bitwy (#101, `scripts/battle/battle_effects.gd`):
  - strzały to kreska 1 px, a oszczepy i garnki smoły Podpalacza lecą łukiem z cieniem na ziemi;
  - uderzenia w budynki wzbijają pył, a zawalony budynek chmurę pyłu;
  - nad płonącym budynkiem migocze ogień i unosi się dym.

  Efekty powstają ze zdarzeń, które bitwa zapisuje tylko dla widoku (`Battle.take_fx`). Nie wchodzą do
  sumy kontrolnej, więc nie zmieniają przebiegu. Ogień w symulacji przechodzi po 4 s na sąsiednie
  drewniane budynki, także po skosie (bez losowania; wał ziemny nie płonie; czas tymczasowy).
  Gaszenie wodą ze Studni czeka na Studnię (#35).
- `scripts/world/save_game.gd` (`SaveGame`): zapis lokalny w `user://castle.json` (JSON z wersją formatu
  i miejscem na migracje; wersja 2 dodała badania, wersja 3 towary, wersja 4 armię). Zapisuje seed terenu, budynki, surowce,
  towary, kolejkę budowy i badania. Pisze pełny plik
  tymczasowy, a potem tylko zmienia nazwy: poprzedni zapis staje się kopią (`.bak`), a nowy plikiem
  głównym, więc na dysku zawsze leży co najmniej jeden pełny zapis. Nieczytelny plik główny jest
  odkładany obok (`.broken`) i nie trafia do kopii; zapis z nowszej wersji gry też nie jest nadpisywany.
- `scripts/world/economy_config.gd` (`EconomyConfig`): wszystkie liczby ekonomii w jednym pliku.
  Drewno, kamień, żywność i złoto. Start 500/300/300/50, Dwór mieści 1000 każdego surowca, a każdy
  ukończony Magazyn (Gospodarka, bez technologii) dodaje +500/750/1000/1500/2000 na poziomach 1–5;
  Magazyny się sumują, a rozbiórka zmniejsza limit (nadmiar przepada). Złoto jest bez
  limitu (docelowo waluta premium, przybywa tylko z łupu i PvE). Gród daje 20/h drewna, kamienia
  i żywności, a Chata drwala +60/90/120/160/200 drewna/h na poziomach 1–5.
- `scripts/world/economy.gd` (`Economy`): naliczanie produkcji w liczbach całkowitych (ten sam wynik
  co klatkę i jednym skokiem), limity magazynów (`capacities_for` z siatki: Dwór plus Magazyny,
  przeliczane w kolejce budowy, po rozbiórce i przed odczytem zapisu), łup (`add`) i wydawanie (`spend`). Produkcja liczy
  się z zegara systemowego, więc rośnie też, gdy gra jest w tle. Po powrocie komunikat podaje przyrost.
- `scripts/gfx/pixel_icons.gd` (`PixelIcons`): ikony surowców 5×5 zapisane w kodzie jako wzory znaków
  (dwa bale, kamień, jabłko, moneta), kolory z palety, atlas w cache. Ikony 7×7 głównej kolumny HUD-u (#150):
  młotek, księga, hełm, tarcza, klepsydra, zębatka (#177).
- `scripts/ui/hud.gd`: interfejs na jeden kciuk w poziomie. Treść trzyma się 12 px od bocznych krawędzi
  (zaokrąglone narożniki), a wycięcia ekranu odsuwają ją dalej. U góry surowce z ikonami (pełny magazyn
  ma żółtą liczbę), a z prawej czas budowy z liczbą czekających zleceń oraz epoka i rok. U dołu komunikat
  i FPS. Przyciski trybów stoją w kolumnie przy prawej krawędzi, od góry (48×16 px, po teście na
  telefonie mniejsze niż dawne 56×22). W trybie oglądania kolumna jest wąska (#150): przyciski 18×16
  z ikoną na ciemnym okienku, nazwa w dymku po lewej, póki palec trzyma przycisk, a liczba zleceń
  Kolejki w czerwonej plakietce. Pasek celu sięga do samej kolumny. Tryb oglądania: Buduj, Badania, Wojsko, Obrona, Kolejka,
  Ustawienia (Oblężenie i Wyprawa są na karcie Strażnicy); dotknięcie budynku otwiera kartę (poziom albo czas budowy, koszt i czas ulepszenia łamane na linie oraz „Wymaga:” z poziomem Dworu dla następnego poziomu, na zielono albo czerwono;
  Ulepsz, Rozbierz lub Anuluj, Zamknij). Dotknięcie surowca na górnym pasku otwiera okienko z informacją
  (`InfoPopup`, treść z `InfoText`): zapas i magazyn, produkcja na godzinę z rozbiciem na gród, budynki
  i badania, kiedy magazyn się zapełni i jak zdobyć więcej. Na ekranie Wojsko dotknięcie licznika
  „Wojsko: 12/12 (?)” mówi, skąd jest limit armii (Dwór i każde Koszary) i jak go podnieść (Koszary zliczone w jednej linii); pełny licznik
  jest czerwony. Tryb budowy: Gotowe i Zmień (wraca do panelu budowy), koszt
  wybranego budynku w komunikacie; dotknięcia mapy tylko stawiają, niczego nie zaznaczają.
- `scripts/ui/settings_panel.gd` (`SettingsPanel`, #177): gra startuje od razu w zamku (to gra PvP,
  bez ekranu startowego; tylko pierwsze uruchomienie zaczyna się od onboardingu z #228). Ustawienia pod zębatką na dole kolumny HUD-u: Język polski/English
  (angielski jako zapowiedź #64), Dźwięk: wkrótce, Zacznij od nowa (z potwierdzeniem; usuwa zapis
  i przeładowuje scenę, mapa zostaje ta sama, bo seed należy do gracza) i Zamknij. Stopka: gra offline
  z zapisem na telefonie i wersja z `project.godot`. Gra nie łączy się z siecią przy starcie.
- Strażnica (`BuildingTypes.Kind.WATCHTOWER`, #177): budynek PvE 2×2, czatownia na słupach z drabiną.
  Stoi od startu przy Dworze (z kratką odstępu od Dworu i donżonu), jest jedna, nie da się jej rozebrać
  i ma jeden poziom (`BuildingTypes.has_levels`, decyzja właścicielki); starsze zapisy dostają ją przy
  wczytaniu. Jej karta ma tylko Oblężenie (fale samouczka), Wyprawę (atak na zamek bota) i Zamknij;
  Oblężenie i Atak zniknęły z kolumny HUD-u.
  PvP dostanie osobny budynek w etapie 9.
- Komenda umocnień (`BuildingTypes.Kind.SEAL_HOUSE`, #199): budynek 2×2 w zakładce Umocnienia,
  odblokowuje go technologia O2 Zaostrzone pale. Karta ma Sprawdź (odliczanie ~1 min, jedno naraz)
  i Domknij. Po Sprawdź luki świecą na czerwono na mapie; gracz dotyka luki (wybrana ma ramkę tuszu),
  a Domknij zleca w niej odcinek wału/palisady przez kolejkę budowy. Przy pełnej szczelności komunikat
  „Obrona szczelna”. Odliczanie, luki i wybór są w zapisie gry (format 9), ale nie idą na serwer.
  Bez gotowej Komendy nie ma tego flow (`SealCheck`).
- `scripts/ui/queue_panel.gd` (`QueuePanel`, #163): ekran Kolejka pod przyciskiem Kolejka (z liczbą
  zleceń budowy i szkolenia) albo po dotknięciu czasu budowy na górnym pasku. Zakładka Budynki: zlecenia
  w kolejności wykonania (nazwa, „nowy” albo „poz. N→N+1”, czas; pierwsze z paskiem postępu, kolejne
  „czeka”), pod listą zajęte miejsca w kolejce. Anuluj przy wierszu prosi o drugie dotknięcie („Na pewno”,
  komunikat podaje zwrot), dotknięcie wiersza pokazuje budynek na mapie. Zakładka Jednostki: szkolenia
  pogrupowane według budynku rekrutacji (jednostka, oddział docelowy, czas, pasek trwającego), pod listą
  armia względem limitu. Pusta zakładka ma przycisk Buduj albo Wojsko, Dalej przewija długą listę,
  Zamknij albo dotknięcie pustego miejsca wraca do mapy. Anulowania szkolenia nie ma (decyzja balansowa).
- `scripts/ui/build_panel.gd` (`BuildPanel`): panel pod Buduj, w układzie jak drzewko i Wojsko. Zakładki
  kategorii (Umocnienia, Gospodarka, Wytwórcy, Wojsko; `BuildingTypes.CATEGORIES`), kafelki budynków
  (zablokowane przygaszone) i szczegóły: rozmiar, stan, koszt i czas, wymagana technologia oraz co budynek
  daje (produkcja, towary wytwórcy, szkolone jednostki). Postaw włącza stawianie, Zamknij wraca do mapy.
- `scripts/ui/research_panel.gd` (`ResearchPanel`): ekran drzewka pod przyciskiem Badania (obok Buduj).
  Pięć zakładek gałęzi, kafelki z kodami (zbadana na zielono, w toku kolorem strzechy, zablokowana
  przygaszona, ★ z czerwonym znacznikiem w rogu), szczegóły zaznaczonej technologii z efektem, kosztem, czasem
  i wymaganiami (ramki na wymaganych kafelkach) oraz Badaj i Zamknij w miejscu Badania i Buduj.
  Szczegóły pokazują też, co technologia odblokowuje (złota ramka) i z czym łączy się przez towary
  (`TechLinks`, niebieska ramka; np. A39 Drzewcarz robi kopię dla Kopijnika z A22). Teksty zawijają się.
  Zbadane technologie mają zielony kafelek ze znaczkiem w rogu. Ramki są tylko w bieżącej zakładce,
  a zakładki innych gałęzi z powiązaniami mają pasek w kolorze ramki.
- `scripts/world/ages.gd` (`Ages`): epoka i rok na pasku. Epoka I zaczyna się w 550 r., a rok rośnie
  z poziomem Dworu (550, 600, 650, 700, 750).

Wymagania technologii dla budynków i jednostek dojdą razem z efektami badań (#12).
Gra zapisuje się po każdej akcji, po ukończeniu budowy i przy zejściu do tła, a po ponownym uruchomieniu
nadrabia czas nieobecności (budowa i produkcja liczą się tak, jakby gra działała cały czas).

Do ręcznego testu na telefonie: czy Buduj, Gotowe, pasek budynków i karta dają się obsłużyć jednym
kciukiem, czy przewijanie paska palcem jest wygodne, czy budowa długiego wału kratka po kratce nie jest
zbyt męcząca, czy po zejściu do tła na kilka minut surowce przybywają i czy po zamknięciu aplikacji
(także „ubiciu” z listy ostatnich) zamek wraca z nadrobioną budową. Przy wytwórcach: czy ich rekwizyty
da się odróżnić na telefonie i czy pasek budowy z 14 budynkami przewija się wygodnie. Przy badaniach: czy kafelki
drzewka (34×14 px) dają się trafić kciukiem, czy kody i opisy są czytelne i czy badanie kończy się w tle.

## Uruchomienie

1. Zainstaluj [Godot 4.7.2](https://godotengine.org/download) (wersja standardowa, nie .NET).
2. W Godocie: **Import** → wskaż `project.godot`.
3. **F5** uruchamia scenę testową na komputerze.

## Testowy APK na telefon

Jednorazowa konfiguracja:

1. Zainstaluj JDK 17 (np. `brew install --cask zulu@17`) i Android SDK (najprościej przez Android Studio: SDK Platform-Tools, Build-Tools, SDK Platform 34+).
2. W Godocie: **Editor → Manage Export Templates → Download and Install**.
3. **Editor Settings → Export → Android**: ustaw ścieżkę do JDK i Android SDK. Debug keystore Godot tworzy sam przy pierwszym eksporcie.
4. Na telefonie włącz opcje programisty i debugowanie USB.

Potem:

- **Project → Export → Android (debug APK) → Export Project** zapisuje `build/castle_defender.apk`, albo
- ikona Androida w prawym górnym rogu edytora (**Remote Deploy**) instaluje i uruchamia grę na podłączonym telefonie jednym kliknięciem.

## Testy

Wymagają Godota 4.7.2 w PATH jako `godot`. Na Windows użyj `Godot_v4.7.2-stable_win64_console.exe` i Git Bash.

```bash
bash .github/scripts/run_checks.sh          # wszystko naraz, to samo co CI
godot --headless --path . --script res://tests/run_tests.gd   # same testy logiki
```

Nowe testy dodajesz jako `tests/test_<nazwa>.gd` z `extends TestCase`. Każda metoda `test_*`
kończy się `return true` (wzór: `tests/test_pixel_canvas.gd`).

Baza PvP (Supabase, #21): migracje są w `supabase/migrations`, a testy RLS w pgTAP
w `supabase/tests/database`. Z Supabase CLI i Dockerem:

```bash
supabase start      # lokalny stos Supabase z migracjami
supabase test db    # testy RLS (pgTAP)
```

Połączenie gry z projektem Supabase (#22): skopiuj `config/supabase.example.json` do
`config/supabase.json` i wpisz adres projektu oraz klucz publishable (Dashboard → Project Settings →
API Keys). Plik jest w `.gitignore`; klucza serwera (`sb_secret_…`, `service_role`) nigdy tam nie wpisuj.

## Wersje i changelog

Wersja to SemVer `MAJOR.MINOR.PATCH`. Pierwsze wydanie, 0.0.1, obejmuje etapy 1 i 2 (szkielet projektu,
teren, siatka budowy i kamera). Przed 1.0.0 wersje mają postać `0.x.y`, a numer kolejnego wydania wybiera właściciel. Jedno źródło prawdy to `tools/version.py`, który trzyma w zgodzie
`project.godot`, `export_presets.cfg` (`version/name`, `version/code = MAJOR*10000 + MINOR*100 + PATCH`)
i `CHANGELOG.md`.

- **Changelog generuje się ze scalonych PR-ów.** Tytuł PR to wpis w changelogu. Podsekcję wybiera
  prefiks gałęzi (`feat/` → Dodane, `fix/` → Naprawione, reszta → Zmienione) albo etykieta PR
  (`dodane`, `zmienione`, `naprawione`, `usuniete`). Etykieta `bez-changelogu` pomija PR.
  Podgląd następnego wydania (wymaga `gh` albo `GITHUB_TOKEN`): `python3 tools/changelog.py preview`.
- Wydanie:
  1. **Actions → Przygotuj wydanie → Run workflow** (`patch`, `minor`, `major` albo `X.Y.Z`). Workflow
     generuje sekcję changelogu z PR-ów od ostatniego tagu, podbija wersję i otwiera PR „Wydanie X.Y.Z”.
     Wymaga włączonego *Settings → Actions → General → Allow GitHub Actions to create pull requests*.
     Bez tego wypchnie tylko gałąź, a PR otwierasz ręcznie.
  2. Po merge'u PR-a z wydaniem:

     ```bash
     git tag vX.Y.Z origin/main
     git push origin vX.Y.Z
     ```

  To samo lokalnie: `python3 tools/version.py bump minor`, potem commit, PR i tag.

- `python3 tools/version.py check` sprawdza zgodność wersji (uruchamia się też w CI).

## CI/CD (GitHub Actions)

| Workflow | Kiedy | Co robi |
|---|---|---|
| `ci.yml` | każdy push i PR | wersja i changelog, import, kompilacja skryptów, test dymny, testy logiki |
| `release.yml` | push na `main` | CI i debug APK jako artefakt (Actions → Wydanie → przebieg → Artifacts) |
| `release.yml` | tag `vX.Y.Z` | CI, debug APK, GitHub Release z opisem z changelogu (APK do pobrania na telefon) |
| `release.yml` (ręcznie) | Actions → Wydanie → Run workflow | samo debug APK jako artefakt, bez Release |
| `prepare-release.yml` | Actions → Przygotuj wydanie → Run workflow | changelog z PR-ów, nowa wersja, PR „Wydanie X.Y.Z” |
| `dependabot.yml` | co miesiąc | PR z aktualizacjami akcji |

Godot jest pobierany z oficjalnych wydań i weryfikowany przypiętą sumą SHA-512
(`.github/scripts/install_godot.sh`). Zmiana wersji Godota oznacza podmianę wersji i sum w tym pliku.
APK jest podpisany jednorazowym kluczem debug, więc przed instalacją nowej wersji odinstaluj
poprzednią. Podpis release (Google Play) dojdzie później, z kluczem w sekretach repozytorium.

## Struktura

```
scenes/          sceny Godota
scripts/         logika gry
scripts/gfx/     rysowanie proceduralne i palety
scripts/world/   dane świata: teren, siatka budowy, ekonomia, badania, armia
scripts/battle/  deterministyczna symulacja bitwy (bez renderu)
scripts/camera/  kamera z gestami (zoom 0,5×/1×/2×/4×)
scripts/ui/      HUD
scripts/net/     klient Supabase: konto anonimowe, sesja, tryb offline
config/          wzór konfiguracji Supabase (właściwy plik poza repo)
tests/           testy headless (run_tests.gd, check_compile.gd, test_*.gd)
tools/           narzędzia (version.py, changelog.py i ich testy)
supabase/        backend PvP: config.toml, migracje SQL i testy RLS (pgTAP)
.github/         workflowy CI/CD i skrypty instalacji Godota
.claude/skills/  skille dla agenta AI, także bezpieczeństwa i review (zob. CLAUDE.md)
.cursor/         reguły dla Cursora i Bugbota (odsyłają do CLAUDE.md i skilli)
docs/castle-defender-vault/  vault Obsidiana z notatkami projektowymi (Godot go pomija)
build/           eksportowane APK i logi (ignorowane przez git)
```

## Następny etap

Etap 8 (#130) jest zrobiony w kodzie: ustawienia obrony (#19), zadania obrony (#20) i pułapki (#100).
Gaszenie pożarów przeszło do Studni (#35), komendant do generałów (#31), a odsłanianie pułapek do zwiadu
(#28). PvE przeszło do Strażnicy, a kolumna HUD-u ma zębatkę Ustawień z trybem offline (#177). Trwa etap 9 (#131):
backend Supabase i PvP. Jest schemat bazy z RLS (#21), klient z anonimowym kontem (#22) oraz zapis
`map_seed` i `start_attack` z seedem terenu (#166), onboarding z imieniem gracza, nazwą zamku i domyślnym
władcą (#228), synchronizacja zamku z obroną z rewizjami (#23, w kodzie) i dobór przeciwnika z ekranem
3 celów (#24, migracja `match_targets` i funkcja `find_targets` są na projekcie). Konto anonimowe przetrwa
reinstalację tylko z sesją na telefonie, więc pełny powrót po reinstalacji czeka na decyzję: kopia
zapasowa Androida albo logowanie (np. Google). Atak ma serwerowy start i koniec (#25): `start_attack` blokuje cel na czas ataku (tarcza, limit 10 startów na 10 minut, armia z zamku na serwerze), a `finish_attack` przyjmuje wynik tylko w limitach: łup najwyżej z niechronionych zapasów obrońcy i najwyżej tyle, ile uniosą ocaleli (piechota 5, konnica 10), tarcza obrońcy 8 h od 30% zniszczeń. Łup z zamków-botów też ogranicza capacity ocalałych. Klient atakuje gracza z ekranu 3 celów (#240): bitwa z kopii zamku i obrony z `start_attack`, łup z odpowiedzi `finish_attack`. Do zrobienia: odjęcie łupu z magazynu obrońcy i wynik, który nie ginie przy zamknięciu gry przed odpowiedzią serwera. Z wcześniejszych etapów zostają: Dwór z epokami i garnizonem (#81),
część efektów badań (#12) i ogólny wygląd (#150). Sprawdzanie szczelności obrony (#199) jest w kodzie
(Komenda umocnień + Sprawdź / Domknij). Magazyn podnosi limit surowców ponad 1000 z Dworu. Donżon strzela jak wieża,
gdy stoi przy nim strzelec obrońcy, i nie ma już ulepszeń (#232).
