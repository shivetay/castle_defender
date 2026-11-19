# supabase/tests/

Testy bazy (pgTAP), głównie RLS.

| Ścieżka | Rola |
|---|---|
| `database/rls_test.sql` | Właściciel może, obcy gracz nie — scenariusze na tabelach PvP |
| `database/match_targets_test.sql` | Dobór przeciwnika (#24): filtry, limit 3, tylko serwer wywoła funkcję |

```bash
supabase test db
```
