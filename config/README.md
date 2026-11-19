# config/

Konfiguracja klienta spoza gita (sekrety / lokalne endpointy).

## Kluczowe pliki

| Plik | Rola |
|---|---|
| `supabase.example.json` | Wzór: URL projektu + klucz **publishable** |
| `supabase.json` | Lokalna kopia (w `.gitignore`) — skopiuj ze wzoru |

Nigdy nie commituj `service_role` / `sb_secret_…`. Odczyt w grze: `scripts/net/supabase_config.gd`.
