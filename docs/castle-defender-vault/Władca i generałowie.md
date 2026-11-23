# Władca i generałowie

Gracz jest władcą zamku i ma własne perki. Do tego dowodzą generałowie: jeden prowadzi atak, drugi (komendant) dowodzi obroną. Generałowie nie mają państw ani narodowości, tylko archetypy zgodne z epoką.

## Perki władcy

- Miejsca na perki: 1 na start, 2. po przejściu do epoki III, 3. po przejściu do epoki V.
- Perk z wyższej epoki odblokowuje się dopiero po wejściu do niej. Zmiana perka jest darmowa raz na 24 h, kolejne zmiany kosztują złoto.
- Perki władcy działają na cały zamek: w ataku, w obronie i w gospodarce.
- W MVP (#32): 1 miejsce i 6 perków (Zdobywca, Łupieżca, Gospodarz grodu, Gospodarny, Budowniczy, Ukochany władca), wybór z portretu władcy w HUD-zie. Kolejna zmiana w ciągu 24 h kosztuje 50 zł (tymczasowo). Serwer sprawdza perk przy zapisie zamku (epoka, 24 h, pokrycie złota), bierze perk atakującego z zamku na serwerze, a Łupieżcę liczy w limicie łupu. Budowniczy skraca czas przy zleceniu budowy (budowy już w kolejce się nie zmieniają).

| Perk | Kategoria | Od epoki | Efekt |
| --- | --- | --- | --- |
| Zdobywca | atak | I | +10% obrażeń wszystkich oddziałów w ataku |
| Łupieżca | atak | II | +15% łupu z ataków PvP |
| Oblegający | atak | III | inżynieria i artyleria +15% HP |
| Strateg | atak | V | +1 oddział w planie ataku |
| Gospodarz grodu | obrona | I | wszystkie budynki +10% wytrzymałości |
| Czujny | obrona | II | pułapki +20% obrażeń |
| Niezłomny | obrona | IV | tarcza po przegranej obronie +4 h |
| Mistrz fortyfikacji | obrona | V | mury i bastiony naprawiają się 2× szybciej po bitwie |
| Gospodarny | gospodarka | I | +10% produkcji wszystkich surowców |
| Budowniczy | gospodarka | II | budowa −10% czasu |
| Kupiec | gospodarka | III | +20% złota |
| Uczony | gospodarka | IV | badania −15% czasu |
| Ukochany władca | morale | I | +10 morale załogi |
| Pobożny | morale | II | efekt Kaplicy ×2 |
| Charyzma | morale | III | +10 morale oddziałów ataku |
| Żelazna dyscyplina | morale | V | oddziały wycofują się dopiero przy morale 20 (zamiast 30) |
| Przebiegły | specjalne | II | zwiad +20% zasięgu |
| Mecenas | specjalne | III | +1 miejsce na generała w rezerwie |
| Mistrz intryg | specjalne | IV | sabotaż +10 pkt proc. skuteczności, wróg słabiej go wykrywa |

## Generałowie

- Masz do 3 generałów (4 z perkiem Mecenas). Do bitwy wysyłasz jednego jako dowódcę ataku, a jednego ustawiasz jako komendanta obrony.
- Generał nie stoi na siatce i nie da się go wystawić w bitwie (decyzja z 21.11.2026, #31). Przypisany do ataku albo obrony dowodzi całą stroną, a jego perki działają na wszystkie jej oddziały. Wcześniejszy pomysł z postacią na siatce (HP 150, aura 4 kratek, −20 morale po śmierci) odpadł.
- Generałów rekrutuje się za złoto w budynku głównym. Dostępni są tylko ci z bieżącej i wcześniejszych epok.
- Generał zdobywa doświadczenie w bitwach i ma poziomy 1–5. Na poziomie 1 ma perk główny, na poziomie 3 wybiera drugi perk, a na poziomie 5 trzeci, z puli poniżej.

| Generał | Od epoki | Najlepszy w | Perk główny |
| --- | --- | --- | --- |
| Wódz drużyny | I | atak | piechota +10% obrażeń, +10 morale w aurze |
| Łowczy | I | atak, zwiad | zwiad +20%, Oskrzydlenie 20% szybciej |
| Mistrz konnicy | II | atak | szarża konnicy +15% obrażeń |
| Budowniczy kopców | I (w MVP; było II) | obrona | wał, palisada i kopiec +15% wytrzymałości |
| Mistrz oblężniczy | III | atak | artyleria +20% obrażeń przeciw murom |
| Kasztelan | III | obrona | mury +10% wytrzymałości, morale załogi nie spada poniżej 50 |
| Puszkarz | IV | atak, obrona | artyleria i działa w basztach +15% zasięgu |
| Hetman taboru | IV | atak | strzelcy za wozem bojowym +20% obrażeń |
| Inżynier fortyfikacji | V | atak, obrona | inżynieria 30% szybciej, Kontrminy 2× skuteczniejsze |
| Pułkownik jazdy | V | atak | husarze, rajtarzy i dragoni +15% obrażeń w szarży |
| Marszałek | VI | atak | +1 oddział w planie, manewry 10% szybciej |
| Komendant twierdzy | VI | obrona | bastiony, kazamaty i reduty +15% obrażeń |

**Pula perków dodatkowych (poziom 3 i 5)**

W MVP (#31) z puli epok I–II działają Szybki marsz (wszyscy +1 szybkości) i Ostrożny (wszyscy −15% od strzał). Weteran i Twardy nie mają sensu bez postaci na siatce, a Okrutny czeka na łup z generałem liczony na serwerze. Wódz drużyny: piechota +10% obrażeń i +10 morale całej armii. Koszty MVP (tymczasowe, obniżone 22.11.2026): rekrutacja 50 zł, poziom 2: 100 PD i 80 zł, poziom 3: 300 PD i 150 zł; 20 PD za bitwę, +20 za wygraną. Głównym źródłem złota i PD jest PvP: boty i fale PvE wystarczają najwyżej na poziom 2, poziom 3 tylko za PD i złoto z PvP. Awans robi się w Dworze (Wyszkol) i zużywa PD oraz złoto z zamku. Serwer przy zapisie zamku sprawdza, czy złoto i PD generałów mają pokrycie w łupach, nagrodach fal i bitwach zapisanych na serwerze (anti-cheat).

| Perk | Od epoki | Efekt |
| --- | --- | --- |
| Weteran | I | aura +2 kratki |
| Twardy | I | generał +100% HP |
| Szybki marsz | I | oddziały w aurze +1 szybkości |
| Ostrożny | II | oddziały w aurze −15% obrażeń od strzał |
| Okrutny | II | +10% łupu, ale −5 morale własnych oddziałów |
| Natchniony | III | po zniszczeniu celu +10 morale wszystkim oddziałom |
| Mistrz pułapek | III | w obronie pułapki w aurze +30% obrażeń |
| Artylerzysta | IV | artyleria w aurze przeładowuje 20% szybciej |
| Zimna krew | IV | pierwsze 30 s bitwy oddziały nie tracą morale |
| Saper | V | podkopy i miny 25% szybsze |
| Taktyk | V | manewr z warunkiem startu rusza 5 s wcześniej |
| Sztab | VI | aura obejmuje całą siatkę, ale słabsza o połowę |

Powiązane: [[Koncept gry]], [[Jednostki]], [[Manewry i zadania]], [[Drzewko technologiczne]]
