# Interfejs

Trzy elementy na stałe, reszta ekranu należy do zamku. Orientacja pozioma, obsługa jednym kciukiem.

| Element | Miejsce | Zawartość |
| --- | --- | --- |
| Pasek surowców | góra, 12 px | ikony 5×5 px rysowane kodem + liczby, epoka i rok („III · 1287”) |
| Przycisk Buduj | prawy dolny róg | lista budynków bieżącej epoki, przewijana w poziomie |
| Przycisk Oblężenie | lewy dolny róg | startuje falę; w trakcie tylko przewijanie czasu |

**Gesty:** przeciągnięcie = kamera, szczypanie = zoom, dotknięcie budynku = karta (poziom, ulepsz, przebuduj, rozbierz), przytrzymanie pustej kratki w trybie budowy = podgląd zasięgu.

**Zasady:** czcionka pikselowa 3×5 lub 4×6 px z bitmapy w skrypcie, cele dotyku min. 48 dp, ekrany zamykane tapnięciem poza nimi.

**Ekrany PvP** (każdy korzysta z tego samego widoku zamku, zmienia się tylko nakładka):

| Ekran | Co robisz |
| --- | --- |
| Ustawienia obrony | widok własnego zamku w trybie edycji: przeciągasz załogę i pułapki, rysujesz strefy patroli, ustawiasz priorytety wież |
| Wybór celu | 3 karty przeciwników: portret władcy, imię, nazwa zamku, siła jako przedział, np. „Siła 200-250” (bot z klienta, gracz z serwera; #310, #293, [[ADR/0004-sila-celu-pvp-przedzial-z-serwera\|ADR 0004]]) |
| Zwiad | animacja zwiadowcy, potem mapa z mgłą wojny i odsłoniętym obszarem |
| Planowanie ataku | siatka ze strefami rozstawienia; dolny pasek z oddziałami; dotknięcie oddziału otwiera listę manewrów i ich parametry (cel, trasa, start, odwrót); strzałki pokazują plan |
| Bitwa | widok na żywo bez sterowania, przewijanie czasu ×2 i ×4 |
| Raport i powtórka | wynik, gwiazdki, łup; obrońca może obejrzeć powtórkę i od razu poprawić obronę; historia obron (okno po połączeniu z liczbą ataków, przycisk Historia, czerwona kropka nad Obroną, tarcze zamiast gwiazdek) [[ADR/0003-historia-obron-z-nickiem-i-sila-napastnika\|ADR 0003]]; wiersz z przedziałem siły obrony zamku napastnika („Obr. 200-250”, [[ADR/0004-sila-celu-pvp-przedzial-z-serwera\|ADR 0004]]) |

Powiązane: [[Widok zamku]], [[Koncept gry]]
