# ADR 0002: Perki władcy z technologii zamiast wyboru z listy

- **Status:** przyjęty
- **Data:** 2026-11-26
- **Issue:** #308

## Kontekst

W MVP (#32) gracz wybierał jeden z 6 perków władcy z listy w panelu portretu. Zmiana była darmowa raz
na 24 h, kolejna kosztowała 50 zł, a serwer pilnował okna i opłaty wyzwalaczem
(`20261123120000_ruler_perk.sql`). Właścicielka chce, żeby perków nie wybierało się z listy: władca ma
perk przypisany, a kolejny odblokowuje technologia ([[Władca i generałowie]], [[Drzewko technologiczne]]).

## Decyzja

- Władca ma 0–1 perk wrodzony z osobnej puli, innej niż perki z technologii, oraz 1 miejsce na perk
  z technologii. Kasztelan (pierwszy władca) nie ma perka wrodzonego. Pula perków wrodzonych i nowi
  władcy to osobne zadanie.
- Perki z technologii to 4 **linie z poziomami**, po jednej technologii na poziom, w gałęzi kategorii perka:

| Linia | Poziom 1 (epoka I) | Poziom 2 (epoka II, wymaga poziomu 1) |
| --- | --- | --- |
| Zdobywca (Atak) | A60 Zdobywca: +10% obrażeń w ataku | A61 Łupieżca: +10% obrażeń i +15% łupu z PvP |
| Gospodarz grodu (Obrona) | O23: budynki +10% wytrzymałości | O24: budynki +15% wytrzymałości |
| Gospodarny (Gospodarka) | G25 Gospodarny: +10% produkcji | G26 Budowniczy: +10% produkcji i budowa −10% czasu |
| Ukochany władca (Użyteczne) | U14: +10 morale załogi | U15: +15 morale załogi |

- Liczby poziomu 2 są tymczasowe. Poziomy z epok III i wyższych dojdą z technologiami tych epok.
- Koszt i czas technologii perków liczą się ze zwykłego wzoru badań epoki. Poziom 1 nie ma wymagań.
  Technologię z wcześniejszej epoki da się badać później.
- Pierwsza zbadana (albo badana) technologia perkowa wybiera linię na stałe. Pozostałe linie są
  zablokowane we wszystkich epokach. Linii nie da się zmienić. Okno 24 h i opłata 50 zł znikają.
- Działa najwyższy zbadany poziom linii, nie wyższy niż epoka zamku. Serwer liczy perk z `research.done`
  w zapisie zamku: perk jest tylko z jednej linii, poziom 2 tylko z poziomem 1 i od epoki II, a technologie
  z dwóch linii dają brak perka. Perka wpisanego przez klienta w `ruler` serwer nie czyta.
- Gracze, którzy mieli perk wybrany z listy, tracą go. Rekompensata to osobna decyzja (#349).

## Rozważane opcje

- **Linie z poziomami, pierwsza linia blokuje pozostałe** (wybrana): wybór ma znaczenie na całą grę,
  a kolejne epoki rozwijają ten sam perk.
- **Jeden perk na epokę z puli tej epoki**: odrzucone, bo właścicielka chce kontynuacji perka z epoki I.
- **Jeden perk z technologii łącznie, bez poziomów**: odrzucone z tego samego powodu.
- **Poziom 2 podbija też efekt poziomu 1 (+15% obrażeń, +15% produkcji)**: odrzucone, bo linie
  Zdobywcy i Gospodarnego byłyby silniejsze od dwóch pozostałych.
- **Zostawienie zmiany perka raz na 24 h**: odrzucone, bo wybór ma być na stałe.

## Konsekwencje

- Klient: `RulerPerks` liczy stan perka z badań, `Research` blokuje inne linie
  (`RULER_PERK_LOCKED`, „Wybrano już perk władcy”), a panel władcy tylko pokazuje perk wrodzony
  i perk z technologii. Perk nie trafia już do zapisu gry.
- Serwer (`20261126121609_ruler_perk_research.sql`): `castle_ruler_perk` liczy perk z badań, drzewko
  `tech_tree` zna 8 nowych technologii, a wyzwalacz okna 24 h i kolumna `ruler_perk_free_at` znikają.
  `ruler_perk_paid` zostaje w budżecie złota do decyzji w #349.
- Drzewko w grze ma 43 technologie (34 z notatki MVP, S3 i 8 perków).

## Dotknięte notatki

- [[Władca i generałowie]]: sekcja „Perki władcy”.
- [[Drzewko technologiczne]]: technologie perków władcy.
- [[Plan MVP]]: wiersz „Perki władcy”.
