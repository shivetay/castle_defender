# Review w Castle Defender (Cursor Bugbot)

Zasady review są wspólne dla Cursora i Claude Code. Źródłem prawdy są `CLAUDE.md` (sekcje
„Bezpieczeństwo” i „Review”) oraz skille w `.claude/skills/`:
`security-review/SKILL.md` (lista kontrolna i wagi uwag), `supabase-security/SKILL.md`,
`pvp-anti-cheat/SKILL.md` i `user-data-privacy/SKILL.md`. Przeczytaj je przed review. Gdy ten
plik i `CLAUDE.md` się różnią, wygrywa `CLAUDE.md`.

## Kolejność

1. **Bezpieczeństwo najpierw.** Czy zmiana pozwala graczowi zobaczyć, zmienić albo zdobyć coś,
   czego nie powinien, albo ujawnia dane lub sekrety?
2. Potem poprawność, determinizm symulacji, testy, zgodność z zasadami projektu (grafika z kodu,
   kolory z palet, typowanie GDScript), na końcu styl.

## Wagi uwag

- 🔴 **Krytyczne (blokuje merge):** wyciek sekretu lub klucza `service_role`; tabela bez RLS albo
  z polityką bez warunku na właściciela (`(select auth.uid()) = …`); możliwość zmiany cudzych
  danych; klient ustawiający wynik, łup, ranking, tarczę albo nagrodę; SECURITY DEFINER w `public`
  dostępny dla klienta; dane osobowe, tokeny albo całe odpowiedzi API w logach.
- 🟠 **Ważne (poprawić przed merge):** brak testu pgTAP dla nowej tabeli lub polityki; brak
  walidacji danych z klienta po stronie serwera; nowe pole o graczu bez opisu w PR; brak limitu
  rozmiaru lub częstotliwości; zależność bez przypiętej wersji; edycja migracji już wgranej.
- 🟡 **Drobne:** reszta.

Każdą uwagę 🔴/🟠 opisz konkretnie: plik i linia, scenariusz nadużycia (np. „gracz B wysyła PATCH
na `castles?player_id=eq.A`”) i propozycja poprawki. Nie zgłaszaj hipotez bez śladu w kodzie.

## Na co patrzeć szczególnie

- `supabase/migrations/**`: RLS, `revoke`/`grant` (także na kolumnach), polityki z `using`
  i `with check`, brak `auth.role()` i `user_metadata`, funkcje SECURITY DEFINER tylko w `private`
  z `search_path = ''`. Migracji już wgranej nie wolno edytować.
- `supabase/tests/**`: czy nowe reguły mają testy „właściciel tak, obcy nie, kolumny serwera nie”.
- `supabase/functions/**` (Edge Functions): id gracza z JWT, nie z treści żądania; walidacja
  wejścia; idempotentny zapis wyniku ataku; brak sekretów w odpowiedziach.
- `scripts/**` (Godot): tylko klucz publishable; brak `print` odpowiedzi API i tokenów; logika
  bitwy deterministyczna (bez `randf()`/`randi()` bez seeda i bez floatów w symulacji).
- `.github/workflows/**`: brak wypisywania sekretów, brak `pull_request_target` z kodem z forka,
  akcje przypięte do wersji.
- `export_presets.cfg`, `project.godot`: uprawnienia Androida, podpisywanie, brak haseł i kluczy.

Odpowiadaj po polsku, jak w reszcie projektu.
