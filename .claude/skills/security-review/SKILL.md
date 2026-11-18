---
name: security-review
description: >
  Lista kontrolna review pod kątem bezpieczeństwa w Castle Defender: dane graczy, Supabase (RLS,
  uprawnienia, klucze, migracje), PvP (klient niezaufany), sekrety, CI i zależności, z poziomami
  wagi uwag. Użyj przy każdym review PR i przed zgłoszeniem własnej zmiany jako gotowej, zwłaszcza
  gdy diff dotyka `supabase/`, kodu sieciowego, zapisu gry, logowania, CI albo `export_presets.cfg`.
---

# Review bezpieczeństwa

Review każdego PR zaczyna się od pytania: czy ta zmiana pozwala graczowi zobaczyć, zmienić albo
zdobyć coś, czego nie powinien, albo ujawnia dane lub sekrety? Dopiero potem poprawność i styl.

## Poziomy wagi

- **🔴 Krytyczne (blokuje merge):** wyciek sekretu lub klucza `service_role`, tabela bez RLS albo
  z polityką bez warunku na właściciela, możliwość zmiany cudzych danych, klient ustawiający wynik,
  łup, ranking, tarczę lub nagrodę, SECURITY DEFINER w `public` dostępny dla klienta, dane osobowe
  w logach.
- **🟠 Ważne (poprawić przed merge):** brak testu RLS dla nowej tabeli lub polityki, brak walidacji
  danych z klienta po stronie serwera, nowe pole o graczu bez opisu w PR, brak limitu rozmiaru
  lub częstotliwości, zależność bez przypiętej wersji.
- **🟡 Drobne:** komentarze, nazwy, nadmiarowe uprawnienia bez realnego skutku (np. SELECT na
  tabeli publicznej z założenia).

Uwagi 🔴 i 🟠 opisz konkretnie: plik i linia, scenariusz ataku („gracz B wysyła PATCH na
`castles?player_id=eq.A`…”) i propozycja poprawki. Nie zgłaszaj hipotez bez śladu w kodzie.

## Lista kontrolna

### Supabase (`supabase/`, kod klienta API)
- [ ] Każda nowa tabela: RLS włączone, `revoke` od `anon`/`authenticated`, granty minimalne,
      zapis ograniczony do kolumn.
- [ ] Polityki: `to authenticated` + warunek na właściciela z `(select auth.uid())`, UPDATE ma
      `using` i `with check`, brak `auth.role()` i `user_metadata`.
- [ ] Funkcje: SECURITY DEFINER tylko w `private`, z `search_path = ''` i odebranym EXECUTE;
      RPC w `public` są SECURITY INVOKER.
- [ ] Testy pgTAP pokrywają nową tabelę/politykę (właściciel tak, obcy nie, kolumny serwera nie).
- [ ] Migracja jest nowa (nie edytuje wgranej) i opis PR mówi, czy i gdzie ją wgrano.
- [ ] W kliencie tylko klucz publishable; żadnych sekretów w `project.godot`, skryptach, eksporcie.

### PvP i ekonomia
- [ ] Wynik, łup, ranking, tarcze, nagrody liczy albo weryfikuje serwer.
- [ ] Dane zamku z klienta są walidowane, zanim trafią do innych graczy.
- [ ] Logika bitwy pozostaje deterministyczna (test determinizmu przechodzi).
- [ ] Powtórzone żądanie nie daje podwójnej korzyści.

### Dane graczy
- [ ] Nowe dane o graczu są potrzebne, opisane w PR i kasowane razem z kontem.
- [ ] Brak danych osobowych, tokenów i całych odpowiedzi API w `print`/logach.

### Repo, CI, zależności
- [ ] Brak sekretów w diffie (klucze, hasła, keystore, `.env`, tokeny w URL-ach).
- [ ] Workflowy nie wypisują sekretów, nie używają `pull_request_target` z kodem z forka,
      akcje są przypięte do wersji.
- [ ] Nowe zależności i addony mają zgodę właścicielki i przypiętą wersję.
- [ ] Zmiany w `export_presets.cfg` (uprawnienia Androida, podpisywanie) są uzasadnione w PR.

## Narzędzia

- Wbudowane `/security-review` (Claude Code) na diffie gałęzi.
- `get_advisors` (Supabase MCP, typ `security`) po wgraniu migracji.
- Testy RLS: `supabase test db` albo lokalny Postgres z zaślepką platformy.

Zobacz też: `supabase-security`, `pvp-anti-cheat`, `user-data-privacy`.
