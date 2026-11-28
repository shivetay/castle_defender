# ADR 0020: Flagi ofert, eventów i funkcji z panelu admina

- **Status:** przyjęty
- **Data:** 2026-11-28
- **Issue:** #280 (część #269; ustalenia w komentarzu „Ustalenia” w #280)

## Kontekst

Właścicielka chce włączać i wyłączać treści (wóz sprzedawcy #268, wydarzenia #58), a w przyszłości także całe
funkcjonalności gry, bez nowego APK. Steruje tym z mini panelu admina (`castle_defender_admin`, ten sam projekt
Supabase). Panel założył tabelę `public.feature_flags` własną migracją: `kind` tylko `offer`/`event`, SELECT dla
`anon` i `authenticated` na całej tabeli, także na `updated_by` (uuid admina), i DELETE dla admina. Przy sklepie
[[ADR/0014-sklep-darmowe-oferty-z-odnowieniem|ADR 0014]] ustalił, że schemat, RLS i pgTAP są w repo gry, a uuid
admina nie jest czytelny dla gracza. Klient nie jest zaufany ([[Serwer]]), a zegar telefonu da się przestawić.

## Decyzja

1. **Schemat w repo gry**: migracja `*_feature_flags.sql` jest idempotentna (na projekcie zmienia uprawnienia
   tabeli panelu i zostawia wiersze), test `feature_flags_test.sql` w CI gry. Panel to tylko UI.
2. **Rodzaje** `offer`, `event` i `feature` (całe funkcje gry). Klucz `[a-z0-9._]` do 64 znaków (CHECK),
   klient mapuje po kluczu, nie po uuid.
3. **Uprawnienia**: gracz (`authenticated`) czyta wszystkie wiersze bez `id` i `updated_by`; `anon` nic. Admin
   (`app_metadata.role = 'admin'`) dodaje i zmienia tylko jawne kolumny, bez `key` i `kind` po dodaniu;
   `updated_at` i `updated_by` ustawia wyzwalacz. DELETE nie ma nikt: flagę się wyłącza.
4. **Aktywna** = `enabled` i czas serwera w oknie `starts_at`..`ends_at` (oba końce włącznie, null = bez granicy).
5. **Domyślny stan bez wiersza** wynika z przedrostka: `feature.*` włączone, `offer.*`, `event.*` i każdy inny
   klucz wyłączone. Kolejność źródeł: odpowiedź serwera, cache `user://feature_flags.json`, stan domyślny.
6. **Czas serwera** z nagłówka `Date` odpowiedzi; w sesji dalej liczy zegar monotoniczny. Po restarcie z cache
   liczy się przesunięcie zegara telefonu, ale nie wcześniej niż ostatni znany czas serwera.
7. **Odświeżanie** po połączeniu sesji i co 15 minut online; po błędzie najwcześniej za minutę.
8. **Treść z panelu jest niezaufana**: najwyżej 100 wierszy, zły klucz albo czas odrzuca wiersz, `metadata`
   ponad 2000 znaków JSON jest pomijane. Odpowiedzi nie logujemy.
9. **Flaga steruje tylko widocznością w kliencie.** Nie przyznaje nagród, łupu ani dostępu na serwerze; to,
   co daje event (np. 2× łup), liczy serwer.
10. **Teraz żadna funkcja nie ma flagi** i wszystkie działają. Flagę konkretnej funkcji dodaje się dopiero,
    gdy wprost każe to zadanie albo właścicielka. Wtedy rozważa się też sprawdzenie flagi w Edge Functions.

## Rozważane opcje

- **Schemat w repo gry, odczyt REST tabeli** (wybrana): pgTAP w CI gry, ta sama ścieżka co sklep.
- **Schemat zostaje w panelu, w grze tylko test**: odrzucona; dwa źródła migracji jednej tabeli i brak
  kontroli nad uprawnieniami, na których opiera się klient.
- **SELECT także dla `anon`**: odrzucona; gra zawsze ma sesję anonimowego konta.
- **Okno czasu na zegarze telefonu**: odrzucona; zmiana daty włączałaby eventy.
- **Bez sieci i cache wszystko wyłączone**: odrzucona dla funkcji; brak wiersza wyłączałby działające funkcje.
- **Od razu flagi `feature.pvp`, `feature.scout`, `feature.ranking`, `feature.shop`**: odrzucona przez
  właścicielkę; flagi funkcji tylko na wyraźne polecenie.

## Konsekwencje

- Panel (`castle_defender_admin`) przestaje wybierać i wysyłać `id` i `updated_by`, przełącza po `key` i zna
  rodzaj `feature`. Ten PR panelu musi wejść przed migracją gry na projekcie `castle_defender`.
- Klient: `FeatureFlags` (`scripts/net/feature_flags.gd`) i `SupabaseClient.is_feature_active(key)`.
  #268 i #58 podpinają się pod `offer.merchant_wagon` i `event.*`.
- Wyłączona funkcja z flagą zniknie tylko w kliencie; zmodyfikowany APK dalej zawoła serwer, dopóki Edge
  Function nie sprawdza flagi.
- Dane gracza: żadne. Cache flag nie zawiera nic o graczu.

## Dotknięte notatki

- [[Serwer]]: punkt o flagach z panelu w „Klient i sekrety”.
- [[Otwarte pytania]]: wpis w „Ustalone” z datą 28.11.2026 i #280.
