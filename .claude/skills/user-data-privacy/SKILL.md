---
name: user-data-privacy
description: >
  Ochrona danych graczy w Castle Defender: minimalizacja danych, RODO (prawo do usunięcia i wglądu),
  konta anonimowe, brak danych osobowych w logach i telemetrii, przechowywanie na telefonie,
  sekrety. Użyj przy dodawaniu pól o graczu, logowania (anonimowe, Google), telemetrii, logów,
  powiadomień push, reklam i przy wszystkim, co zapisuje albo wysyła dane gracza.
---

# Dane graczy i prywatność

Gra trafi do Google Play (zamknięte testy z 50–100 osobami, potem publicznie), więc obowiązuje RODO
i zasady Google Play dotyczące danych. Zasada ogólna: zbieraj tylko to, czego gra naprawdę
potrzebuje, i daj graczowi to usunąć.

## Zasady

1. **Minimalizacja.** Bez e-maila, imienia, lokalizacji, kontaktów i identyfikatorów urządzenia,
   jeśli gra ich nie potrzebuje. Konto anonimowe Supabase wystarcza do PvP. Nick wybiera gracz;
   traktuj go jak treść od użytkownika (limit długości, filtr na treści obraźliwe przed publicznym
   rankingiem).
2. **Każde nowe pole o graczu** opisz w PR: po co jest, kto je widzi (tylko gracz, inni gracze,
   tylko serwer), jak długo jest przechowywane.
3. **Prawo do usunięcia.** Usunięcie konta Auth kasuje kaskadowo wszystkie dane gracza
   (`on delete cascade` od `auth.users`). Nowe tabele z danymi gracza muszą to zachować. Gra
   powinna mieć ścieżkę „Usuń konto” w Ustawieniach, zanim trafi do publicznego sklepu.
4. **Widoczność dla innych graczy** tylko przez to, co konieczne do gry (nick, ranking, kopia
   obrony w trakcie ataku), i tylko przez serwer albo politykę, która tego jawnie dotyczy.
5. **Logi i telemetria bez danych osobowych:** bez tokenów, identyfikatorów kont w połączeniu
   z innymi danymi, nicków, adresów IP. W Godot nie wypisuj odpowiedzi API ani tokenów przez
   `print`/`push_warning`.
6. **Na telefonie** (`user://`): token sesji Supabase i zapis gry to dane gracza. Nie kopiuj ich do
   miejsc dostępnych dla innych aplikacji ani do logów. Nie trzymaj tam kluczy serwera.
7. **Sekrety** (keystore, hasła, klucze Supabase poza publishable, klucze AdMob SSV, FCM): tylko
   w sekretach GitHub Actions albo Edge Functions. `.env`, `*.keystore`, `*.jks` są w `.gitignore`;
   nie obchodź tego i nie wklejaj sekretów do PR, issue ani komentarzy.
8. **Usługi zewnętrzne** (AdMob, FCM, Google Sign-In) dodają własne zbieranie danych. Przed
   dodaniem opisz w PR, jakie dane wysyłają; to musi trafić do deklaracji w Google Play
   (Data safety) i polityki prywatności.
9. **Dzieci.** Jeśli gra może trafić do dzieci, reklamy i dane podlegają dodatkowym zasadom
   (Families Policy). Każda decyzja w tej sprawie należy do właścicielki.

## Czerwone flagi w kodzie

- Nowa kolumna z e-mailem, numerem, lokalizacją albo identyfikatorem urządzenia.
- `print(response)` / logowanie całych żądań i odpowiedzi HTTP.
- Dane gracza wysyłane do usługi zewnętrznej bez opisu w PR.
- Tabela z danymi gracza bez `on delete cascade` do konta.
