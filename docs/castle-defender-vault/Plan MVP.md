# Plan MVP

Pierwsza grywalna wersja obejmuje epoki I i II z okrojoną zawartością, pełną pętlą PvP (budowa, obrona offline, zwiad, plan ataku, bitwa, raport) i reklamami z nagrodą. Cel: sprawdzić, czy planowanie ataku z manewrów i oglądanie bitwy bawią, zanim powstaną kolejne epoki.

| Obszar | W MVP | Później |
| --- | --- | --- |
| Epoki | I i II, z przejściem I → II (Dwór 5 + preferencyjnie 2 techy; budynki max→lvl1 z bonusami; bez niszczenia postępu — #34) | III–VI |
| Budynki | 29: Wał ziemny, Fosa sucha, Palisada, Brama drewniana, Wieża drewniana, Kopiec, Chata drwala, Pole i spichlerz, Studnia, Kamieniołom, Dwór grodowy, Koszary (od epoki I), Stajnia (od epoki I), Wieża sygnałowa, Dom drużyny, Strzelnica, Chata myśliwego, Garbarnia, Wytwórca zbroi skórzanych, Drzewcarz, Cięciwiarz, Łukmistrz, Strzałmistrz, Rymarz, Smolarnia, Pole lnu, Rybak, Wieża grodowa i Wieża na kopcu (donżon) | Pomost strzelecki, Częstokół, Młyn, Kaplica, Dom zwiadowców i budynki epok III–VI |
| Poziomy | budynki i zamek poziomy 1–5 | bez zmian |
| Jednostki | 13 w 5 klasach: Wojownik z toporem, Oszczepnik, Łucznik, Tarczownik, Podpalacz, Tropiciel, Jeździec (epoka I), Włócznik, Drużynnik w przeszywanicy, Strzelec z łukiem refleksyjnym, Kopijnik (epoka II), Taran, Kopacz | pozostałe 50, w tym cała artyleria |
| Towary | bez metalu: skóry, skórzane pancerze, przeszywanice, tarcze, siodła, łuki, strzały z kościanymi grotami, smoła, konie; rekrutacja je zużywa ([[Klasy jednostek i produkcja]]) | żelazo od epoki III (Kopalnia rudy), kusze, zbroje, broń palna, proch |
| Technologie | 34: A1–A7, A21, A22, A38–A47, O1–O3, G1, G2, G4, G6, G18–G21, G24, U1, S1, S2 | pozostałe 97 |
| Manewry ataku | 6: Szturm frontalny, Ostrzał z dystansu, Podpalenie, Oskrzydlenie, Szturm z drabinami, Taranowanie bramy | Osłona i manewry epok III–VI |
| Zadania obrony | 5: Obrona odcinka, Patrol, Priorytet celów wież, Gaszenie pożarów, Wypad konnicy | Rezerwa, Odwrót do donjonu, Kontrminy |
| Generałowie | 3: Wódz drużyny, Łowczy (atak), Budowniczy kopców (obrona); poziomy 1–3, jeden perk dodatkowy | pozostałe 9, poziomy 4–5 |
| Perki władcy | 1 miejsce, 6 perków: Zdobywca, Łupieżca, Gospodarz grodu, Gospodarny, Budowniczy, Ukochany władca | miejsca 2 i 3, pozostałe 13 perków |
| Surowce | drewno, kamień, żywność, złoto (z łupu i PvE) | proch, żelazo |
| PvP | dobór przeciwnika, zwiad z mgłą wojny, plan ataku, bitwa bez sterowania, łup, tarcza, ranking, powtórka, 20 zamków-botów | sezony rankingu, weryfikacja bitew na serwerze (Godot headless) |
| PvE | samouczek: 5 fal oblężenia | kampania z lokacjami |
| Reklamy z nagrodą | przyspieszenie budowy, szybsze zbieranie surowców | skrócenie czasu do ataku, wywiad, sabotaż, ochrona magazynu |
| Backend | Supabase: logowanie, zapis zamku i obrony, `start_attack` / `finish_attack`, tarcze, boty, weryfikacja reklam (AdMob SSV), powiadomienia push | klany i sojusze |
| Grafika | rzut 3/4, paleta epok I–II, 4 stany zniszczeń, mieszkańcy, dym, flagi, pora dnia | pogoda, tryb Kronika |

## Kolejność prac (etapy)

Każdy etap ma w repo ticket „Etap N” z podpiętymi zadaniami (sub-issues, etykieta `etap`).

| Etap | Zakres | Ticket | Zadania |
| --- | --- | --- | --- |
| 1 | Projekt w Godot 4, viewport 320×180, testowy APK, CI | #123 | #1, #2 |
| 2 | Generator terenu, siatka budowy, kamera | #124 | #3, #4 |
| 3 | Rysowanie proceduralne, autotiling, pierwsze 5 budynków, stany zniszczeń | #125 | #5–#8 |
| 4 | Ekonomia, progresja, zapis lokalny, HUD, Dwór przez epoki, seed mapy | #126 | #9–#11, #13, #81, #97 |
| 5 | Klasy jednostek, towary, wytwórcy, rekrutacja, badania (34 technologie), budynki gospodarcze | #127 | #12, #87–#91, #119, #122 |
| 6 | Deterministyczna symulacja bitwy, jednostki, morale, efekty, donżon jako cel, samouczek PvE | #128 | #14–#16, #92, #98, #101, #120 |
| 7 | Plan ataku i manewry | #129 | #17, #18 |
| 8 | Ustawienia obrony, zadania obrony, pułapki | #130 | #19, #20, #100 |
| 9 | Backend Supabase: logowanie, zapis, dobór przeciwnika, atak, tarcze, boty, ranking | #131 | #21–#27 |
| 10 | Zwiad z mgłą wojny, wynik bitwy, raport i powtórka, push | #132 | #28–#30, #99 |
| 11 | Generałowie i perki władcy | #133 | #31, #32 |
| 12 | Reklamy z nagrodą (AdMob + SSV) | #134 | #33 |
| 13 | Epoka II, pozostałe budynki i jednostki MVP, życie w zamku | #135 | #34–#36 |
| 14 | Zamknięte testy w Google Play | #136 | #37 |

Wersje po MVP mają tickety zbiorcze z podpiętymi zadaniami: Etap 0.2 (#38), 0.3 (#43), 0.4 (#46), 0.5 (#51), 1.0 (#137).

Bieżący stan (17.11.2026): etap 8 w toku, szczegóły i daty wdrożeń w [[Stan prac]]; pytania i braki w [[Otwarte pytania]].

Powiązane: [[Stack technologiczny]], [[Backend PvP]], [[Otwarte pytania]], [[Jednostki]], [[Drzewko technologiczne]]
