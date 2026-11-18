---
name: pvp-anti-cheat
description: >
  Zasady ochrony PvP przed oszustwami w Castle Defender: klient nie jest zaufany, wynik ataku,
  łup, ranking i tarcze liczy albo weryfikuje serwer z deterministycznej powtórki, a dane z klienta
  mają limity. Użyj przy pracy nad atakiem, wynikiem bitwy, łupem, rankingiem, tarczami, nagrodami
  za reklamy, synchronizacją zamku z serwerem i każdym kodzie, który wysyła dane gry do Supabase.
---

# Anti-cheat w PvP

Gracz ma pełną kontrolę nad swoim telefonem: może zmienić zapis, podmienić APK, wysyłać własne
żądania do API i odtwarzać je wielokrotnie. Dlatego każda liczba, która daje przewagę nad innymi
graczami, musi pochodzić z serwera albo być przez serwer sprawdzona.

## Zasady

1. **Klient nie jest źródłem prawdy o wyniku.** Wynik ataku (procent, gwiazdki, łup) liczy serwer
   z deterministycznej powtórki: seed bitwy z `start_attack`, rozkazy z planu, kopia obrony
   z serwera. W MVP serwer może ufać wynikowi klienta tylko po sprawdzeniu limitów (łup nie
   większy niż możliwy, czas bitwy w granicach, cel zgodny z atakiem rozpoczętym przez tego gracza).
2. **Seed bitwy i kopia obrony pochodzą z serwera** (`start_attack`). Klient nie wybiera seeda,
   celu ani obrony przeciwnika.
3. **Jeden atak = jeden wynik.** `finish_attack` przyjmuje wynik tylko dla ataku w stanie `started`,
   należącego do wołającego, w rozsądnym czasie od startu; drugi raz nic nie zmienia.
4. **Ranking, epoka, tarcze i nagrody zmienia tylko serwer.** Klient nie ma do tych kolumn
   uprawnień (patrz `supabase-security`).
5. **Zapis zamku z klienta to dane niezaufane.** Przed użyciem w PvP (dobór, obrona) serwer
   sprawdza: wersję formatu, rozmiar, zakresy (poziomy budynków, liczba budynków, surowce do
   pojemności magazynu, armia do limitu epoki). Nierealny stan odrzuć, nie „napraw po cichu”.
6. **Determinizm to bezpieczeństwo.** Każda zmiana w symulacji bitwy (`scripts/battle/`) musi
   zachować powtarzalność: ten sam seed i te same dane dają ten sam wynik i tę samą sumę kontrolną.
   Test determinizmu jest obowiązkowy dla nowej logiki bitwy.
7. **Nagrody za reklamy** przyznaje tylko weryfikacja SSV po stronie serwera, z dziennym limitem
   w `ad_rewards`. Klient nie zgłasza „obejrzałem reklamę”.
8. **Limity częstotliwości.** Akcje, które da się spamować (start ataku, zapis zamku, zmiana nicku),
   mają limity po stronie serwera.

## Przy review i implementacji pytaj

- Czy gracz może tę liczbę ustawić sam (zapis, żądanie API, zmodyfikowany klient)?
- Czy serwer może ją policzyć albo odtworzyć? Jeśli tak, niech liczy.
- Czy to samo żądanie wysłane dwa razy daje podwójną korzyść?
- Czy gracz może zaatakować sam siebie, swojego drugiego konta albo cel z tarczą?
- Czy wynik zależy od czegoś spoza seeda i danych (czas, kolejność słownika, float)?
