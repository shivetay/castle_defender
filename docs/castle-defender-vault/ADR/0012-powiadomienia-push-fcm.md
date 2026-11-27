# ADR 0012: Powiadomienia push o ataku przez FCM, koniec budowy lokalnie

- **Status:** przyjęty
- **Data:** 2026-11-27
- **Issue:** #30

## Kontekst

Gracz ma się dowiedzieć o ataku na zamek, nawet gdy gra jest zamknięta (#30, [[Backend PvP]]).
Do tej pory wie o ataku dopiero po uruchomieniu gry, z okienka „Zaatakowano Cię N×” (#328,
[[ADR/0003-historia-obron-z-nickiem-i-sila-napastnika|ADR 0003]]). Godot nie ma FCM w silniku,
gra łączy się z Supabase przez `HTTPRequest` bez wtyczek, a preset debug APK buduje się bez Gradle.
Budowa liczy się na telefonie, w lokalnym zapisie.

## Decyzja

1. **Push o ataku idzie przez Firebase Cloud Messaging (HTTP v1)**, wysyłany przez Edge Function
   `finish_attack` po zapisaniu wyniku, w tle. Błąd FCM nie zmienia odpowiedzi ani wyniku ataku.
   Wysyłkę wyzwala wyłącznie serwer: klient nie ma endpointu „wyślij push”.
2. **Jeden push na atak.** `attack_push_claim` oznacza atak jako powiadomiony (`attacks.push_sent_at`),
   więc ponowione `finish_attack` nic nie wyśle. Push dostaje tylko zakończony atak na gracza ze skutkami
   (`outcome_applied_at`). Atak w weryfikacji (tryb enforce) pusha nie dostaje, dopóki nie dojdzie wysyłka
   po wyniku workera.
3. **Treść:** tytuł „Twój zamek został zaatakowany!”, treść „Obrona odparta (35%)” albo
   „Donżon zdobyty (80%)”. Bez nicku napastnika i bez łupu. Wspólny klucz i tag `attack` (kanał `attacks`),
   więc kolejny atak zastępuje poprzednie powiadomienie. Dotknięcie otwiera grę z okienkiem z #328.
4. **Tokeny urządzeń** w tabeli `public.push_tokens` (`player_id`, `token`, `attacks`, `updated_at`).
   Klient nie ma do niej uprawnień, a zapisuje i usuwa własny token przez Edge Function `push_token`
   z id z JWT, najwyżej 20 zapisów na godzinę na konto. Na konto przypada najwyżej 5 tokenów, a tokeny nieodświeżone od 60 dni wypadają. Token tego samego
   urządzenia przechodzi na konto, które zapisało go ostatnie. Token odrzucony przez FCM usuwa serwer.
   Tokeny znikają razem z kontem i nie trafiają do logów.
5. **Przełączniki:** „Ataki” (per urządzenie, kolumna `push_tokens.attacks` na serwerze) i „Koniec budowy”
   (na telefonie). Oba są domyślnie włączone.
6. **Zgoda na Androidzie 13+:** najpierw okienko w grze przy pierwszym wejściu na ekran PvP
   („Tak” / „Nie teraz”), dopiero potem systemowe `POST_NOTIFICATIONS`. Po odmowie gra pyta ponownie
   najwcześniej po 7 dniach.
7. **Wtyczka:** własna, mała wtyczka Android v2 w Kotlinie w repo (`android/plugins/push/`) z Firebase
   Messaging od Google, bez addonów osób trzecich. Preset debug APK przechodzi na budowę Gradle.
8. **Sekrety:** `google-services.json` leży poza repo, CI bierze go z sekretu `GOOGLE_SERVICES_JSON` (base64).
   Konto serwisowe FCM jest tylko w sekrecie Edge Functions `FCM_SERVICE_ACCOUNT`. Bez niego push się nie wysyła.
9. **Koniec budowy** to lokalne powiadomienie z tej samej wtyczki (`AlarmManager`), bez serwera.
   Gra planuje je przy zleceniu budowy i anuluje przy zmianie kolejki. Treść: „Budowa zakończona: <budynek> (poz. N)”.
10. **Trzy PR-y:** (1) tokeny i wysyłka na serwerze, (2) wtyczka, Gradle, uprawnienie, zgoda, rejestracja
    tokenu i przełączniki, (3) lokalne powiadomienie o końcu budowy.

## Rozważane opcje

- **Własna wtyczka Android v2** (wybrana): bez cudzego kodu i ryzyka porzucenia przy Godot 4.7, a zakres
  (token, kanał, lokalne powiadomienie) jest mały.
- **Gotowy addon FCM społeczności**: odrzucony, bo to cudzy kod do przeglądu i nowa zależność, często
  nieaktualna względem Godota.
- **Bez FCM, tylko okienko po uruchomieniu (#328)**: odrzucone, bo przy zamkniętej grze nic nie przychodzi
  (kryterium akceptacji #30).
- **Koniec budowy przez FCM z serwera**: odrzucone, bo serwer nie zna czasu budowy z kolejki na telefonie,
  a lokalne powiadomienie działa też offline.
- **Nick napastnika w pushu**: odrzucony, żeby do Google szło jak najmniej danych.

## Konsekwencje

- Nowa usługa zewnętrzna: Google Firebase dostaje token urządzenia i treść pusha (wynik i procent),
  bez id konta i nicków.
- Nowe dane gracza: token FCM urządzenia i przełącznik „Ataki”, kasowane z kontem.
- Debug APK buduje się przez Gradle, więc CI jest wolniejsze, a bez `google-services.json` wtyczka się nie zbuduje.
- `export_presets.cfg` dostaje uprawnienie `POST_NOTIFICATIONS` i wtyczkę.
- Właścicielka zakłada projekt Firebase (pakiety `com.shivetay.dunhold` i `.debug`) i ustawia oba sekrety.
- Odbiór przy zamkniętej grze da się sprawdzić tylko na telefonie.
- Atak jest oznaczany jako powiadomiony przed wysyłką, więc przy awarii FCM ten jeden push przepada; gracz
  i tak zobaczy okienko z #328 po uruchomieniu gry.
- Dalej: push po wyniku workera, gdy weryfikacja przejdzie na enforce.

## Dotknięte notatki

- [[Backend PvP]]: wiersz „Powiadomienia” opisuje tabelę tokenów, jeden push na atak i sekret.
- [[Otwarte pytania]]: push w „Ustalone”.
