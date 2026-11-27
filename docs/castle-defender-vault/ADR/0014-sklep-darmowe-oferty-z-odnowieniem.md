# ADR 0014: Sklep w Targu: darmowe oferty z odnowieniem, przyznawane przez serwer

- **Status:** przyjęty
- **Data:** 2026-11-27
- **Issue:** #408 (część #174; ustalenia w komentarzu „Ustalenia” w #174)

## Kontekst

Sklep z #174 miał najpierw wejść z HUD-u po MVP, z zakupami i reklamami. Właścicielka zmieniła zakres:
sklep otwiera się z budynku **Targ** i jest dostępny od początku gry, a pierwsza wersja ma tylko darmowe
oferty, które właścicielka układa w panelu admina (`castle_defender_admin`). Klient nie jest zaufany
([[Serwer]]): surowce w zapisie zamku pilnuje bilans serwera, a złoto ma wymóg źródła
(`private.ruler_gold_left`, `gold_unbacked`). Targ był dotąd w [[Budynki/Gospodarka|Gospodarce]] budynkiem
epoki III dającym złoto.

## Decyzja

1. **Targ** to budynek 4×4 (`BuildingTypes.Kind.MARKET` = 33, na końcu rodzajów, więc numery starych
   zapisów się nie zmieniają). Stoi od startu jak Dwór, jeden na zamek, bez poziomów, bez rozbiórki
   i przenoszenia, bez produkcji, kosztu i czasu budowy; nie ma go w panelu budowy. Jedyna akcja to Sklep.
2. Nowa gra stawia Targ po Strażnicy na najbliższym wolnym 4×4 przy Dworze (`BuildGrid.market_spot`).
   Stary zapis dostaje go tak samo przy wczytaniu; bez miejsca HUD mówi „Zrób miejsce 4×4 na Targ”,
   a Targ staje sam po rozbiórce albo anulowaniu budowy.
3. W bitwie Targ jest **przeszkodą**: blokuje drogę jak woda, nie jest celem, nie ma wytrzymałości i nie
   wchodzi do skrótu stanu bitwy. Serwer nie pozwala go przenieść ani usunąć z zapisu (`market_moved`),
   chyba że zapis ma same budynki startu („Zacznij od nowa”).
4. **Oferty są darmowe** i mają odnowienie per gracz i oferta, od odbioru, na zegarze serwera, minimum
   1 h (najwyżej 30 dni). Oferta to jeden surowiec (drewno, kamień, żywność, złoto) i ilość: złoto do 100,
   inne do 2000 (CHECK w bazie). Bez limitu dziennego.
5. Oferty są w **grupach po najwyżej 3** (slot 1–3, pilnuje unikalny indeks w bazie). Grupa ma nazwę,
   kolejność, flagę aktywności i opcjonalne okno od–do. Usuwanie to archiwum: archiwizacja grupy zabiera
   oferty, przywrócenie grupy oddaje ją i jej oferty jako nieaktywne, przywrócona oferta jest nieaktywna.
6. **Odbiór przyznaje serwer**: Edge Function `shop_claim` → `public.claim_offer` (tylko service_role)
   sprawdza widoczność, odnowienie i magazyn (odmowa `storage_full`, złoto bez magazynu), zapisuje odbiór
   w `shop_claims` i nagrodę w `castle_loot_pending`, którą zapis zamku scala i zwraca w `loot_applied`.
   Sklep działa tylko online.
7. **Złoto z ofert** wlicza się do `private.ruler_gold_left`, więc nie łamie zapisów zamku (`gold_unbacked`).
8. **Schemat, RLS i testy pgTAP** są w repo gry (`*_shop.sql`); panel admina to tylko UI na tym samym
   projekcie. Admin to JWT z `app_metadata.role = 'admin'` (`public.is_admin()`).

## Rozważane opcje

- **Darmowe oferty z odnowieniem, przyznawane przez serwer** (wybrana): pozwala wystartować sklep bez Google
  Play i reklam, a nagroda nie przejdzie bez serwera.
- **Odbiór liczony na telefonie, serwer tylko sprawdza bilans**: odrzucona. Bilans surowców nie zna ofert,
  więc odebrany surowiec wyglądałby jak oszustwo, a zmodyfikowany klient mógłby odbierać bez odnowienia.
- **Sklep z HUD-u**: odrzucona przez właścicielkę; sklep jest w Targu i bez Targu go nie ma.
- **Schemat w repo panelu**: odrzucona. Testy RLS i migracje projektu są w repo gry, a pgTAP w CI gry
  pilnuje reguł, na których opiera się bilans zamku.
- **Limit dzienny ponad odnowienie**: odrzucony; odnowienie (min. 1 h) i limity ilości wystarczą.

## Konsekwencje

- `updated_by` (uuid admina) nie jest czytelne przez API: rola `authenticated` ma SELECT kolumnowy bez niego,
  więc panel admina też go nie wybiera. Poprawka panelu musi wejść przed migracją `*_shop.sql`.
- Nowe dane o graczu: tylko odbiory (id konta, oferta, czas, surowiec, ilość), kasowane z kontem.
- Targ zmienia drogę atakujących w bitwie, więc wynik bitwy na zamku z Targiem różni się od tego bez niego;
  starsza wersja gry go nie zna, więc wydanie wymaga podniesienia `min_code` ([[ADR/0006-wymuszenie-aktualizacji-wersji-klienta|ADR 0006]]).
- Serwer nie zna terenu, więc pierwszego miejsca Targu nie sprawdza (stawia go gra deterministycznie);
  pilnuje tylko, żeby potem się nie przesuwał.
- Panel admina (PR 2 w `castle_defender_admin`) zależy od tego schematu; nazw kolumn i funkcji nie zmienia
  się bez zmiany w panelu.
- Zakupy Google Play, reklamy z nagrodą (#33), zestawy wielu surowców, kosmetyki, cena oferty i wóz
  sprzedawcy (#268) zostają na później.

## Dotknięte notatki

- [[Budynki/Gospodarka|Gospodarka]]: wiersz Targ (od epoki I, stoi od startu, tylko sklep).
- [[Balans]]: wiersz Sklep (#174) z darmowymi ofertami i limitami.
- [[Otwarte pytania]]: wpis w „Ustalone” z datą 27.11.2026 i #408.
