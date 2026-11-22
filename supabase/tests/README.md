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
| `database/attack_flow_test.sql` | Start i koniec ataku (#25): blokada celu, tarcze, limity armii i startów, zawyżony łup, capacity, idempotencja |

```bash
supabase test db
```
