# ADR 0017: Obrona murów: jawne zadanie dla strzelców i piechoty

- **Status:** przyjęty
- **Data:** 2026-11-27
- **Issue:** #399

## Kontekst

Do #399 strzelcy wchodzili na wał, palisadę, wieżę i Kopiec tylko przez [[Manewry i zadania|Obronę odcinka]]
i dotknięcie muru (`DefensePlan.station_post`, `Battle._wall_station`). Na liście Zadanie na ekranie Obrona
nie było jawnego rozkazu, a inne klasy zawsze stały pod murem. Właścicielka chciała świadomie przypisywać
oddziały do obrony wału, palisady i wież. Pomost strzelecki (#389) jest poza MVP ([[Plan MVP]]).

## Decyzja

- Jest nowe zadanie obrony **Obrona murów** (`DefensePlan.Task.WALL` = 7, dopisane na końcu enuma, od epoki I).
  Obrona odcinka zostaje bez zmian, a stare zapisy strzelców „na murze” działają dalej bez migracji.
- Obronę murów dostają strzelcy i piechota (lekka i ciężka). Konnica i specjalni jej nie dostają.
- Strzelcy z Obroną murów stoją na wale, palisadzie, wieży albo Kopcu, dokładnie jak z Obroną odcinka na murze:
  +1 zasięgu z muru i Kopca, +2 z wieży, 60% obrażeń od strzał, wręcz dosięga ich tylko ten, kto wszedł po drabinie.
- Piechota z Obroną murów stoi na wale albo palisadzie (nie na wieży ani Kopcu). Nie strzela, bije wręcz tylko
  wroga, który wszedł po drabinie (w zasięgu wręcz), nie ma premii zasięgu i nie schodzi za wrogiem. Dostaje
  60% obrażeń od strzał, a wręcz dosięga jej tylko ten, kto wszedł po drabinie. Nowych liczb nie ma.
- Zadanie domyślne strzelców to Obrona murów na odcinku najbliżej bramy, z tym samym przebiegiem bitwy co dotąd.
  Piechota domyślnie stoi przy bramie jak dotąd.
- Obrona murów bez wskazanego muru i rozkaz spoza reguł (zła klasa, zła kratka z zapisu spoza gry) to w bitwie
  zadanie domyślne.
- Mury rozpoznaje `BuildingTypes.is_wall`, więc przyszłe mury epok III+ wejdą same po dopisaniu do tej funkcji.
- Pomost strzelecki (#389) nie blokuje tego zadania. Później może dodać premię albo stanowiska.

## Rozważane opcje

- **Nowe zadanie WALL** (wybrana): jawny rozkaz na liście Zadanie, jedno źródło reguł (`task_options`,
  `wall_task_post`) dla ekranu i bitwy. Stare zapisy zostają ważne.
- **Tylko opis w UI obecnej Obrony odcinka**: odrzucona, bo zostawiała ukrytą regułę „strzelcy po dotknięciu muru”
  i nie dawała miejsca na piechotę.
- **Piechota domyślnie na murze**: odrzucona jako zmiana balansu bez potrzeby.
- **Piechota także na wieży**: odrzucona, bo wieża jest stanowiskiem strzeleckim.

## Konsekwencje

- Gra: piechota może zatrzymać wspinających się po drabinie, ale nie przeszkadza w szturmie spod muru ani w ostrzale.
- Kod: `DefensePlan` (`Task.WALL`, `can_man_walls`, `wall_task_post`, `order_allowed`, `default_order`),
  `Battle._wall_station`, `Battle._wall_act`, `Battle._climber_for` i ekran Obrona (`DefensePanel`).
- Dane graczy i serwer: zapis zamku ma nowy numer zadania (7) w `defense.orders`. Serwer liczy garnizon tylko
  po zadaniu 6, a powtórka bitwy to ten sam kod GDScript, więc migracji w `supabase/` nie ma. Zła klasa albo
  kratka z zapisu spoza gry daje zadanie domyślne, więc klient nie uzyska tym niczego ponad ekran Obrona.
- Dalej: Pomost strzelecki (#389), odwrót z muru (Odwrót do donżonu, epoka III).

## Dotknięte notatki

- [[Manewry i zadania]]: wiersz „Obrona murów” w tabeli zadań obrony.
