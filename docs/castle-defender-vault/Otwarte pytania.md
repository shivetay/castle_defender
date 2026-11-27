# Otwarte pytania

Pytania projektowe do decyzji właściciela oraz braki względem planu / kodu na `main` (stan na 23.11.2026). Chronologia: [[Stan prac]]. Liczby: [[Balans]].

## Ustalone

- Bitwą nikt nie steruje (działa plan); klany i sojusze w późniejszych wersjach; gra darmowa z dobrowolnymi reklamami.
- **Czy każdy budynek ma 2×2?** Nie: Koszary 3×3, budynki wojska, Magazyn i pola 3×2, stare budynki w starym rozmiarze (#340, 26.11.2026, [[ADR/0005-rozmiary-budynkow|ADR 0005]]).
- **Ile oddziałów w planie ataku?** 3 w epoce I, potem 4 / 5 / 6 / 7 / 8 do epoki VI (`AttackPlan`, 16.11.2026).
- Celem ataku jest donżon (Wieża grodowa od epoki I), nie Dwór (#120).
- Gaszenie pożarów + Studnia weszły z #35 / #20.
- Generał nie stoi na siatce; PvE max poziom 2; awans w Dworze za PD i złoto (#31 / #273).
- Przejście I → II: Dwór 5 + O1 + G1 + A7; przebudowa L6; budynki max→lvl1 z bonusami (#34 / #261). Liczby epoki II: [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]] (#262).
- Historia obron (26.11.2026, #328): okno po połączeniu z liczbą ataków, lista z nickiem i siłą armii atakującego z serwera; siła obrony atakującego odłożona do #293. [[ADR/0003-historia-obron-z-nickiem-i-sila-napastnika|ADR 0003]].
- Siła celu PvP (26.11.2026, #293): serwer liczy siłę obrony z własnej kopii zamku, karta celu, karta bota i historia obron pokazują tylko przedział o stałych granicach, także po zwiadzie. [[ADR/0004-sila-celu-pvp-przedzial-z-serwera|ADR 0004]].
- Wymuszenie aktualizacji (26.11.2026, #336): komunikat o nowej wersji ze sklepem i blokada gry poniżej minimum z serwera, także offline; serwer odrzuca starsze klienty. [[ADR/0006-wymuszenie-aktualizacji-wersji-klienta|ADR 0006]].
- Wersja symulacji ataku (27.11.2026, #354): klient podaje ją przy zatwierdzeniu ataku, a wersja bez packa na serwerze blokuje atak z komunikatem o aktualizacji. [[ADR/0008-wersja-symulacji-ataku-z-klienta|ADR 0008]].
- Pierwsza passa balansu i premie poziomów 6–10 (27.11.2026, #262): ciągła krzywa kosztu i czasu przez 10 poziomów, premie epoki II rosną dalej (tablice do poziomu 10), Dwór II.1–II.5 z własnej tabeli; z Opcji C z [[Balans]] została zasada reklam i sklepu, reszta odrzucona. Liczby tymczasowe. [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]].
- Dobór PvP (27.11.2026, #383): dobór, zwiad i start ataku tylko w tej samej epoce; bez graczy w epoce karty uzupełniają boty z Wyprawy jak dotąd. [[ADR/0010-dobor-pvp-tylko-w-tej-samej-epoce|ADR 0010]].
- Budynki epoki II od poziomu 6 i Młyn (27.11.2026, #102): budynek nowej epoki stawia się na poziomie narastającym 6 i ulepsza do 10; Młyn to G5 z premią +4–20% żywności (#388). Liczby tymczasowe. [[ADR/0011-budynki-epoki-ii-od-poziomu-6|ADR 0011]].

## Pytania otwarte

- [ ] Czy obok reklam dodać jednorazowy zakup (pakiet startowy / „wesprzyj twórcę” ze sztandarem)? Ticket sklepu: #174; model reklam: [[Model wydania]].
- [ ] Czy ranking PvP ma sezony z resetem co kilka tygodni? (Roadmapa od 0.3 / #45.)
- [ ] Samouczek: czy #185 wystarczy, a mini-highlight UI (#251) idzie osobno?

## Braki (kod / tickety vs vault)

### Domknięcie bieżących

| Brak | Ticket | Uwagi |
| --- | --- | --- |
| Pełne efekty 34 technologii | #12 | drzewko i część premii są; reszta efektów otwarta |
| Dwór przez epoki + garnizon UI | #81 | w PR: 4 miejsca za poziom Dworu, +20% HP przy donżonie, bez ataku (decyzja 23.11.2026); liczby do testu na telefonie |
| Wynik bitwy: % / gwiazdki / łup UI | #99 | odbudowa / ruiny są (#255); reszta UI otwarta |
| Perki władcy | #32 | generałowie #31 gotowe |
| Powiadomienia push | #30 | — |
| Ranking PvE (ticket zbiorczy) | #242 | kod rankingu #264–#265; checklist issue |
| Balans epoki II (koszty, czasy, premie) | #262 | ustalone w [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]], kod w PR, migracja do wgrania z wydaniem |
| Mini-samouczek UI do 6 żołnierzy | #251 | — |
| Życie w zamku | #36 | — |
| Reklamy z nagrodą | #33 | — |
| Wygląd zamku / teren | #150 | — |
| Obrót kamery | #151 | — |

### Zamknięte niedawno (nie trzymać jako braków)

#19, #20, #28, #29 (rdzeń), #31, #35, #89, #101, #164, #166, #185, #199, #214, #225, #226 — szczegóły w [[Stan prac]] / [[Bugs]].

### Świadomie później (po MVP / 1.0)

Epoki III–VI (#93–#96, #103+), sezony i ligi, kampania PvE, osiągnięcia, i18n, zgodność ze sklepem — [[Roadmapa do 1.0]]. Budynki epoki II spoza rdzenia (Pomost, Częstokół, Młyn, Kaplica): #102.

Powiązane: [[Koncept gry]], [[Plan MVP]], [[Stan prac]], [[Bugs]], [[Balans]], [[Model wydania]]
