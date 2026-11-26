# ADR 0003: Historia obron z nickiem atakującego i siłą jego armii

- **Status:** przyjęty
- **Data:** 2026-11-26
- **Issue:** #328

## Kontekst

Obrońca dowiaduje się o atakach dopiero po otwarciu powtórki z [[Interfejs]] (ekran „Raport i powtórka”).
Ta część ekranu pokazuje jedną bitwę, a nie historię. Powiadomienie push (#30) jest poza zakresem.
Zapis ataków leży w tabeli `attacks` (seed, rozkazy, wynik, `attacker_army`, [[Backend PvP]]).
RLS na `players` pozwala czytać tylko własny wiersz, więc klient nie może sam ustalić, kto go atakował.
Nick gracza jest już publiczny w rankingu i na kartach celu, więc pokazanie go nie zbiera nowych danych
osobowych. Siłę armii atakującego liczy się z jego `attacker_army` tym samym wzorem co `Strength.unit_power`
w kliencie. Klient nie jest zaufany, więc siły nie wysyła.

## Decyzja

1. Po połączeniu z serwerem gra pokazuje okno „Zaatakowano Cię N× od ostatniej wizyty (X odpartych, Y zdobytych)”
   z przyciskami Historia i OK. Liczą się wszystkie ataki, także odparte.
2. „Nowość” śledzi lokalny znacznik w `PlayerProfile`: `finished_at` ostatnio widzianej obrony. Znacznik nie
   trafia do zapisu zamku ani na serwer.
3. Nowa funkcja RPC zwraca tylko obrony zalogowanego gracza: nick atakującego i siłę armii, z którą atakował.
   Armię bierze serwer z `attacks.attacker_army` (kopia z chwili startu ataku, której klient nie zmieni),
   a klient liczy z niej liczbę wzorem `Strength.unit_power`. To podpowiedź na własnym ekranie obrońcy, która
   nie wpływa na nikogo innego, więc jeden wzór w kliencie wystarcza i odpada test zgodności wag klient–serwer.
   Funkcja SQL `public.defense_history` może wykonać tylko `service_role`; klient woła ją przez Edge Function
   `defense_history`, która bierze id gracza z tokenu (jak `ranking`). Nie zwraca
   id atakującego ani nazwy jego zamku. Konto usunięte pokazuje „?”. Testy pgTAP w `supabase/tests/database`:
   obrońca widzi swoje obrony, obcy gracz nie.
4. Siła obrony zamku atakującego nie wchodzi do tej zmiany. Odkłada się do #293 (siła obrony po stronie
   serwera i decyzja o mgle wojny). Do tego czasu wiersz pokazuje „Obr. ?”.
5. Lista pokazuje wszystkie zakończone obrony, także bez powtórki (wyszarzone, bez dotyku). Jest ich najwyżej 10,
   po 4 na stronę ze strzałkami. Wiersze są dwuliniowe.
6. W historii obron zamiast gwiazdek są tarcze: pełna tarcza = obrońca utrzymał donżon, ciemna i pęknięta =
   gwiazdkę zdobył atakujący.
7. Przycisk „Powtórki” na ekranie obrony zmienia nazwę na „Historia”. Nad przyciskiem Obrona w HUD pojawia się
   czerwona kropka, dopóki są niewidziane ataki. Znika dopiero po otwarciu Historii.
8. Poza zakresem: powiadomienia push i informacja o trwającym ataku.

## Rozważane opcje

- **Okno po połączeniu, przycisk Historia i lista z nickiem i siłą armii** (wybrana): obrońca dowiaduje się
  o atakach także po dłuższej nieobecności, a informacja nie znika po zamknięciu komunikatu.
- **Sam komunikat w HUD**: odrzucone, bo znika po chwili i nie zostawia historii.
- **Rozszerzenie RLS na `players`**: odrzucone, bo odsłania cały wiersz gracza zamiast jednej funkcji.
- **Kolumna „widziane” po stronie serwera**: odrzucone, bo to niepotrzebny stan na serwerze; lokalny znacznik wystarcza.
- **Siła obrony zamku atakującego w tej zmianie**: odroczona do #293, bo wymaga decyzji o mgle wojny.

## Konsekwencje

- Klient: `PlayerProfile` dostaje znacznik `finished_at`. Ekran obrony dostaje przycisk „Historia” i listę
  z tarczami, a HUD czerwoną kropkę. Zapis zamku się nie zmienia.
- Serwer: funkcja `public.defense_history` (tylko `service_role`), Edge Function `defense_history` i testy pgTAP. Klient czyta historię wyłącznie
  przez tę funkcję, nie przez tabelę `attacks`.
- Dane graczy: nick jest już publiczny, nie dodaje się nowe pole o graczu. Armia napastnika pochodzi z kopii na serwerze.
  Funkcja nie zwraca id ani nazwy zamku atakującego, więc nie ujawnia tożsamości przeciwnika.
- Dalej: #293 (siła obrony atakującego i mgła), #30 (push, poza tą decyzją).

## Dotknięte notatki

- [[Interfejs]]: wiersz „Raport i powtórka” o historii obron i oknie po połączeniu ([[ADR/0003-historia-obron-z-nickiem-i-sila-napastnika|ADR 0003]]).
- [[Backend PvP]]: wiersz „Historia obron” o funkcji RPC i zakresie danych ([[ADR/0003-historia-obron-z-nickiem-i-sila-napastnika|ADR 0003]]).
- [[Otwarte pytania]]: decyzja w „Ustalone” ([[ADR/0003-historia-obron-z-nickiem-i-sila-napastnika|ADR 0003]]).
