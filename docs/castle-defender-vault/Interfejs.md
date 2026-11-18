# Interfejs

Trzy warstwy na stałe, reszta ekranu należy do zamku. Orientacja pozioma, obsługa jednym kciukiem.

| Element | Miejsce | Zawartość |
| --- | --- | --- |
| Pasek surowców | góra, 12 px | ikony 5×5 px rysowane kodem + liczby, epoka i rok („III · 1287”) |
| Kolumna HUD | prawy dolny róg | Buduj, Badania, Wojsko, Obrona, Kolejka (z liczbą zleceń), Ustawienia (zębatka) |
| Karta Strażnicy | po tapnięciu Strażnicy | Oblężenie (kolejna fala samouczka), Wyprawa (wybór zamku-bota), Zamknij |

**Gesty:** przeciągnięcie = kamera, szczypanie = zoom (0,5×–4×), dotknięcie budynku = karta (poziom, ulepsz, przebuduj, rozbierz; Strażnica: tylko Oblężenie / Wyprawa), przytrzymanie pustej kratki w trybie budowy = podgląd zasięgu.

**Zasady:** czcionka pikselowa 3×5 lub 4×6 px z bitmapy w skrypcie, cele dotyku min. 48 dp, ekrany zamykane tapnięciem poza nimi.

**PvE (od 0.4.0):** Strażnica stoi obok Dworu od startu. Oblężenie odpala 5 fal na własnym zamku (z prowadzeniem gracza). Wyprawa otwiera wybór spośród 20 zamków-botów, potem plan ataku, bitwę i okno wyniku (gwiazdki, % zniszczeń, łup).

**Ekrany PvP** (każdy korzysta z tego samego widoku zamku, zmienia się tylko nakładka):

| Ekran | Co robisz |
| --- | --- |
| Ustawienia obrony | widok własnego zamku w trybie edycji: przeciągasz załogę i pułapki, rysujesz strefy patroli, ustawiasz priorytety wież |
| Wybór celu | 3 karty przeciwników: miniatura zamku, epoka, ranking, szacowany łup |
| Zwiad | animacja zwiadowcy, potem mapa z mgłą wojny i odsłoniętym obszarem |
| Planowanie ataku | siatka ze strefami rozstawienia; dolny pasek z oddziałami; dotknięcie oddziału otwiera listę manewrów i ich parametry (cel, trasa, start, odwrót); strzałki pokazują plan |
| Bitwa | widok na żywo bez sterowania, przewijanie czasu ×2 i ×4 |
| Raport i powtórka | wynik, gwiazdki, łup; obrońca może obejrzeć powtórkę i od razu poprawić obronę |

Powiązane: [[Widok zamku]], [[Koncept gry]], [[Stan prac]]
