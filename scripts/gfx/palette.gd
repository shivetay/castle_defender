class_name Palette
extends RefCounted
## Paleta epoki I (Gród): 16 kolorów, brązy i zieleń. Cała grafika gry korzysta wyłącznie z palet.
## Rampy (GRASS, WOOD, EARTH...) to nazwane widoki na AGE_I, więc ziemia i drewno dzielą ciemne
## brązy. Kolory UI (napisy, ramka budowy) są osobno w UI i nie liczą się do palety epoki.

const AGE_I: Array[Color] = [
	Color("3b5d2a"), Color("4a7034"), Color("5a8540"), Color("6b9a4c"),  # 0–3 trawa
	Color("3d2a1a"), Color("5c3f25"), Color("7a5634"), Color("a07444"),  # 4–7 drewno i ziemia
	Color("8c6c3c"),  # 8 jasna ziemia i ciemna strzecha
	Color("b08f45"), Color("d1b25e"),  # 9–10 strzecha
	Color("2b4a5e"), Color("365e74"), Color("4d7d8f"),  # 11–13 woda
	Color("1e1a14"),  # 14 cień
	Color("c8432b"),  # 15 akcent (flagi, sztandary)
]

const GRASS: Array[Color] = [AGE_I[0], AGE_I[1], AGE_I[2], AGE_I[3]]
const WOOD: Array[Color] = [AGE_I[4], AGE_I[5], AGE_I[6], AGE_I[7]]
const EARTH: Array[Color] = [AGE_I[4], AGE_I[5], AGE_I[6], AGE_I[8]]
const THATCH: Array[Color] = [AGE_I[8], AGE_I[9], AGE_I[10]]
const WATER: Array[Color] = [AGE_I[11], AGE_I[12], AGE_I[13]]
const SHADOW: Color = AGE_I[14]
const ACCENT: Color = AGE_I[15]

## Paleta epoki II (Zamek drewniano-ziemny, #34): 16 kolorów. Trawa, drewno, ziemia i cień są
## wspólne z epoką I (zamek się nie zmienia, tylko rośnie), strzechę zastępuje gont, dochodzi kamień
## podmurówki, a sztandar pana na kopcu jest błękitny. Woda zostaje z AGE_I (teren się nie zmienia).
const AGE_II: Array[Color] = [
	AGE_I[0], AGE_I[1], AGE_I[2], AGE_I[3],  # 0–3 trawa
	AGE_I[4], AGE_I[5], AGE_I[6], AGE_I[7],  # 4–7 drewno i ziemia
	AGE_I[8],  # 8 jasna ziemia
	Color("5b4a3c"), Color("75614d"), Color("917b62"),  # 9–11 gont
	Color("6f6c66"), Color("9a958a"), Color("c2bcae"),  # 12–14 kamień i wapno
	Color("2f5f8f"),  # 15 sztandar epoki II
]
const SHINGLE: Array[Color] = [AGE_II[9], AGE_II[10], AGE_II[11]]
const STONE: Array[Color] = [AGE_II[12], AGE_II[13], AGE_II[14]]
const AGE_II_ACCENT: Color = AGE_II[15]

## Ekran tytułowy (#360): zachód słońca nad grodem. Niebo od fioletu do złota, słońce, chmury,
## dwa pasma gór, skała pod zamkiem, dachówka wież i ciemna zieleń sosen. Kamień zamku to STONE.
const TITLE: Array[Color] = [
	Color("4a3a6e"), Color("7a4a7e"), Color("c25a78"), Color("e8804a"), Color("f4b860"),  # 0–4 niebo
	Color("fce49a"), Color("f6c4a0"),  # 5 słońce, 6 chmury
	Color("a8688a"), Color("c88898"),  # 7–8 dalekie góry (cień, światło)
	Color("6e4466"), Color("8a5878"),  # 9–10 bliższe góry
	Color("3a2440"), Color("5a3858"),  # 11–12 skała i sylwetki sosen pod słońce
	Color("d8643a"), Color("f08c4a"),  # 13–14 dachówka
	Color("1f3f34"),  # 15 ciemna zieleń sosen
]
const TITLE_SKY: Array[Color] = [TITLE[0], TITLE[1], TITLE[2], TITLE[3], TITLE[4]]
const ROOF_TILE: Array[Color] = [TITLE[13], TITLE[14]]

## Pora dnia (#36): mnożnik koloru świata (CanvasModulate), nie kolor do rysowania. Noc, świt,
## dzień i zmierzch. Noc jest jasna na tyle, żeby budynki i jednostki dało się rozpoznać na telefonie.
const DAYLIGHT: Array[Color] = [Color("aab0d8"), Color("ecd0b6"), Color("ffffff"), Color("ecc2a0")]
const NIGHT_TINT: Color = DAYLIGHT[0]
const DAWN_TINT: Color = DAYLIGHT[1]
const DAY_TINT: Color = DAYLIGHT[2]
const DUSK_TINT: Color = DAYLIGHT[3]

## Kolory interfejsu, wspólne dla wszystkich epok.
const UI: Array[Color] = [Color("f2e8cf"), Color("9bd06a"), Color("7fb0e0"), Color("dca67c"), Color("6e6b66"),
		Color("8f8b84")]
const INK: Color = UI[0]
const VALID: Color = UI[1]
## Skóra na portretach władców (#228); cień skóry to WOOD[3].
const SKIN: Color = UI[3]
## Szare, puste miejsce na władcę, który dojdzie później (onboarding #228): tło i sylwetka.
const LOCKED: Array[Color] = [UI[4], UI[5]]
## Strony bitwy (#15): obrońca niebieski z UI, atakujący czerwony jak sztandary.
const SIDE_DEFENDER: Color = UI[2]
const SIDE_ATTACKER: Color = ACCENT
