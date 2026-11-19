# Bugs

Błędy i poprawki UX znalezione przy graniu (stan na 19.11.2026). Chronologia szersza: [[Stan prac]]. Pytania projektowe: [[Otwarte pytania]].

Źródło: repo [shivetay/castle_defender](https://github.com/shivetay/castle_defender), zakres PR #215–#224.

## Naprawione niedawno (na `main`)

Scalone 19.11.2026. Nie miały osobnych issue GitHub (tylko CAS w trackerze) — po merge nie było czego zamykać przez `gh issue close`.

| PR | Co naprawia |
| --- | --- |
| [#216](https://github.com/shivetay/castle_defender/pull/216) | Wojsko: zapas towarów jednostkowych ze zbrojowni |
| [#218](https://github.com/shivetay/castle_defender/pull/218) | Ikony klas czytelne w planie ataku i obrony |
| [#219](https://github.com/shivetay/castle_defender/pull/219) | Budowa: Anuluj kończy stawianie |
| [#220](https://github.com/shivetay/castle_defender/pull/220) | Bez pętli ścian przy wieży po auto-fill |
| [#222](https://github.com/shivetay/castle_defender/pull/222) | Wyprawa: zwarta lista, Planuj rozwija, kolejne startuje |
| [#223](https://github.com/shivetay/castle_defender/pull/223) | Ostrzał: stój w punkcie i strzelaj, idź tylko bez wroga w zasięgu |
| [#224](https://github.com/shivetay/castle_defender/pull/224) | Mapa repozytorium i README folderów dla agentów (docs, nie UX gry) |

## Nadal otwarte (znalezione)

| Ticket | Temat | PR | Label |
| --- | --- | --- | --- |
| [#199](https://github.com/shivetay/castle_defender/issues/199) | Komenda umocnień: Sprawdź, czerwone luki i Domknij | [#215](https://github.com/shivetay/castle_defender/pull/215) (open) | wcześniejszy |
| [#225](https://github.com/shivetay/castle_defender/issues/225) | Plan ataku: przeciąganie końca strzałki z donżonu | [#221](https://github.com/shivetay/castle_defender/pull/221) (open) | `bug`, `mvp` |
| [#226](https://github.com/shivetay/castle_defender/issues/226) | Dachy warsztatów wg kategorii: strzecha, pomost, namiot | [#217](https://github.com/shivetay/castle_defender/pull/217) (open) | `bug`, `mvp` |

[#199](https://github.com/shivetay/castle_defender/issues/199) zamyka dopiero merge **#215**.

## Inne niedawne merge (poza 215–224)

m.in. #213 seed mapy, #212 bitwa/zniszczenia/odznaki, #211 routing Claude, #210 README stan, #209 auto-fill wału do bramy/wieży, #208 produkcja cywilna, #207 widok z góry, #206 okienka info, #205 INTERNET Android, #204 wieża na murze, #203 karta budynku, #202 manewry wg jednostek, #201 klient Supabase, #200 szczelne mury botów.

Powiązane: [[Stan prac]], [[Otwarte pytania]], [[Interfejs]], [[Widok zamku]]
