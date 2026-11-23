# supabase/tests/

Testy bazy (pgTAP), głównie RLS.

| Ścieżka | Rola |
|---|---|
| `database/rls_test.sql` | Właściciel może, obcy gracz nie — scenariusze na tabelach PvP |
| `database/match_targets_test.sql` | Dobór przeciwnika (#24): filtry, limit 3, tylko serwer wywoła funkcję |
| `database/ruins_test.sql` | Zniszczone budynki po ataku (#99): tylko serwer, gotowe budynki z kopii, limit z procentu, odczyt tylko dla obrońcy |
| `database/replay_test.sql` | Powtórka obrony (#29): plan sprawdzony i zapisany przy zatwierdzeniu, badania z zamku na serwerze, ponowienie bez zmian, powtórka tylko dla obrońcy |
| `database/attack_general_test.sql` | Generał ataku (#31): poziom i perk z zamku atakującego na serwerze, zły rodzaj odrzucony, ponowienie bez zmian, ten sam generał w powtórce, gracz nie czyta kolumny |
| `database/general_budget_test.sql` | Pokrycie generałów (#31): przy zapisie zamku złoto i PD najwyżej z łupów, fal PvE i bitew na serwerze; bez pokrycia poziomy spadają albo generał znika |
| `database/ruler_perk_test.sql` | Perk władcy (#32): przy zapisie zamku tylko znany perk z epoki, zmiana darmowa raz na 24 h, potem za złoto z pokryciem; perk ataku z zamku na serwerze, Łupieżca w limicie łupu, Gospodarny w limicie żywności, gracz nie ustawia kolumn serwera |
| `database/resource_sanity_test.sql` | Surowce w zapisie zamku (#274): odrzut zapasów ponad pojemność, złego kształtu i złota bez pokrycia, rate limit zapisów, łup PvP przeniesiony raz (także przy ponowieniu) i scalony przy zapisie, kopia obrońcy z czekającym łupem, zamek spoza limitów poza PvP, gracz nie czyta łupu czekającego ani nie ustawia kolumn serwera |
| `database/building_sanity_test.sql` | Zabudowa w zapisie zamku (#274, etap 4): budynek wyżej niż Dwór, poziom spoza gry i epoka II bez technologii odrzucone; zabudowa najwyżej w czasie jednego budowniczego od poprzedniego zapisu (zlecenie w toku się liczy, niższa zabudowa przechodzi); serwer bez limitu czasu; zamek spoza reguł poza PvP |
| `database/army_research_goods_sanity_test.sql` | Badania, wojsko i towary w zapisie zamku (#281): technologia bez wymagań i z późniejszej epoki, jednostka bez technologii, oddział złego kształtu i towar ponad zbrojownię odrzucone; przyrost badań, szkolenia i produkcji najwyżej w czasie gry od poprzedniego zapisu (zlecenia w toku i tolerancja się liczą, powrót zwiadu i armia ponad limit, która nie rośnie, przechodzą); serwer bez limitu czasu; zamek spoza reguł poza PvP; gracz nie ustawi kredytów |
| `database/economy_growth_test.sql` | Bilans surowców w zapisie zamku (#282): przyrost najwyżej z produkcji od poprzedniego zapisu (tolerancja 5 minut łącznie), budowa, badania i rekrutacja z pokryciem, zwrot za anulowane zlecenie i nagroda fali PvE raz, spadek bez wydatku odrzucony (obrońca nie schowa łupu), zapis bez `economy` odrzucony, mniejszy magazyn przechodzi, łup z zamku-bota przez serwer, złoto po najeździe nie wraca, gracz nie ustawi kolumn bilansu. Starsze testy dostają kredyt bez limitu (`pg_temp.economy_free`), bo ich zamki nie mają zgodnego bilansu |
| `database/attack_flow_test.sql` | Start i koniec ataku (#25): blokada celu, tarcze, limity armii i startów, zawyżony łup, capacity, idempotencja |

```bash
supabase test db
```
