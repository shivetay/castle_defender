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

## Kolory interfejsu, wspólne dla wszystkich epok.
const UI: Array[Color] = [Color("f2e8cf"), Color("9bd06a")]
const INK: Color = UI[0]
const VALID: Color = UI[1]
