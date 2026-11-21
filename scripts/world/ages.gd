class_name Ages
extends RefCounted
## Epoki, przejście między nimi (#34) i rok na pasku. Rok nie płynie sam: wynika z poziomu Dworu,
## czyli z rozwoju zamku.
##
## Poziomy budynków liczą się narastająco przez epoki: poziomy 1–5 to epoka I, 6–10 to epoka II
## (na ekranie „poziom 1/5, epoka II”). Budynek wchodzi do epoki II dopiero z poziomu 5, bo kolejny
## poziom po 5 to 6, czyli poziom 1 epoki II. Tak nic nie ginie przy przejściu: zamek, budynki i ich
## poziomy zostają, a premie z epoki I trzyma `bonus_level` (epoka II jeszcze nie dokłada nowych).
## Epoka zamku to epoka Dworu: przebudowa Dworu z poziomu 5 na poziom 1 epoki II jest przejściem
## I → II i wymaga technologii kluczowych z TRANSITION_TECHS.

const NAMES: Array[String] = ["Epoka I", "Epoka II"]
## Liczba epok w grze (MVP: I i II).
const COUNT := 2
## Poziomy budynku w jednej epoce.
const LEVELS_PER_AGE := 5
## Najwyższy poziom narastająco (poziom 5 ostatniej epoki).
const MAX_TOTAL_LEVEL := LEVELS_PER_AGE * COUNT
## Rok dla poziomów Dworu 1–5 w każdej epoce. Epoka II to zamek drewniano-ziemny (1050–1200).
const YEARS: Array = [[550, 600, 650, 700, 750], [1050, 1090, 1120, 1160, 1200]]
## Technologie kluczowe (★) wymagane do przejścia z epoki `i` do `i + 1`. Notatka Progresja budowy
## chce preferencyjnie dwóch; druga technologia I → II nie jest jeszcze nazwana w drzewku (#34),
## więc na razie jest tylko O1. G6 (II → III) czeka na epokę III, która jest poza MVP.
const TRANSITION_TECHS: Array = [["O1"], ["G6"]]


## Epoka poziomu narastającego (0 = epoka I). Plac budowy (poziom 0) liczy się jako epoka I.
static func of_level(level: int) -> int:
	if level < 1:
		return 0
	@warning_ignore("integer_division")
	return clampi((level - 1) / LEVELS_PER_AGE, 0, COUNT - 1)


## Poziom w obrębie epoki, 1–5 (0 dla placu budowy).
static func local_level(level: int) -> int:
	if level < 1:
		return 0
	return clampi(level, 1, MAX_TOTAL_LEVEL) - of_level(level) * LEVELS_PER_AGE


## Poziom narastający z epoki i poziomu w niej (odwrotność of_level/local_level).
static func total_level(age: int, local: int) -> int:
	return clampi(age, 0, COUNT - 1) * LEVELS_PER_AGE + clampi(local, 1, LEVELS_PER_AGE)


## Poziom, od którego liczą się premie budynku (produkcja, limity, wytrzymałość). Premie epoki I
## zostają po przejściu, a epoka II nie dokłada jeszcze nowych, więc to najwyżej poziom 5.
## Serwer (private.castle_buildings) obcina poziom tak samo, więc limity armii zgadzają się z nim.
static func bonus_level(level: int) -> int:
	return clampi(level, 0, LEVELS_PER_AGE)


## Czy budowa poziomu `level` przenosi budynek do nowej epoki (poziom 1 epoki II itd.).
static func is_age_step(level: int) -> bool:
	return level > LEVELS_PER_AGE and local_level(level) == 1


## Technologie wymagane do przejścia z epoki `age` do następnej (pusta lista poza zakresem).
static func transition_techs(age: int) -> Array[String]:
	var out: Array[String] = []
	if age >= 0 and age < TRANSITION_TECHS.size():
		out.assign(TRANSITION_TECHS[age] as Array)
	return out


## Czego brakuje do przejścia z epoki zamku do następnej: Dwór na poziomie 5 tej epoki
## i technologie kluczowe. Pusta lista znaczy, że przebudowę Dworu można zlecić.
## Napisy po polsku, do karty Dworu.
static func transition_missing(manor_level: int, research: Research) -> PackedStringArray:
	var out: PackedStringArray = []
	var age := of_level(manor_level)
	if age >= COUNT - 1:
		out.append("Ostatnia epoka")
		return out
	if local_level(manor_level) < LEVELS_PER_AGE:
		out.append("Dwór poz. %d" % LEVELS_PER_AGE)
	for code in transition_techs(age):
		if research == null or not research.is_done(code):
			out.append("%s %s" % [code, TechTree.tech_name(code)])
	return out


## Czy przebudowę Dworu na następną epokę można zlecić.
static func can_advance(manor_level: int, research: Research) -> bool:
	return transition_missing(manor_level, research).is_empty()


static func year(age: int, manor_level: int) -> int:
	var years: Array = YEARS[clampi(age, 0, YEARS.size() - 1)]
	return years[clampi(manor_level, 1, years.size()) - 1]


## Napis epoki, np. „Epoka II”.
static func age_name(age: int) -> String:
	return NAMES[clampi(age, 0, NAMES.size() - 1)]


## Napis na pasku, np. „Epoka I · 550 r.”. `manor_level` to poziom w obrębie epoki (1–5).
static func label(age: int, manor_level: int) -> String:
	return "%s · %d r." % [age_name(age), year(age, manor_level)]


## Napis na pasku dla poziomu Dworu liczonego narastająco.
static func label_for_manor(manor_total_level: int) -> String:
	return label(of_level(manor_total_level), local_level(manor_total_level))


## Krótki poziom do kolejki i list, np. „3” w epoce I i „II.2” w epoce II.
static func short_level(level: int) -> String:
	if of_level(level) == 0:
		return str(maxi(level, 0))
	return "%s.%d" % [TechTree.AGE_NUMERALS[of_level(level)], local_level(level)]


## Stan poziomu na karcie budynku, np. „poziom 3/5” albo „poziom 1/5, epoka II”.
static func level_status(level: int) -> String:
	var text := "poziom %d/%d" % [local_level(level), LEVELS_PER_AGE]
	if of_level(level) > 0:
		text += ", epoka %s" % TechTree.AGE_NUMERALS[of_level(level)]
	return text
