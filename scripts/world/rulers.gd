class_name Rulers
extends RefCounted
## Władcy zamku (#228). Na start każdy gracz dostaje domyślnego władcę bez żadnych premii, żeby
## wybór postaci nie blokował pierwszej synchronizacji zamku (#23). Generałowie (#31) i perki
## władcy (#32) dojdą później jako kolejne wpisy z własnymi premiami.

## Identyfikator domyślnego władcy w profilu gracza.
const DEFAULT := "kasztelan"

## Nazwy władców w UI.
const NAMES := {
	DEFAULT: "Kasztelan",
}

## Perki władców (#32). Domyślny władca nie ma żadnych.
const PERKS := {
	DEFAULT: [],
}

## Miejsca na ekranie wyboru władcy w onboardingu: dostępni władcy po kolei, reszta to puste,
## szare miejsca na postacie, które dojdą z #31 i #32.
const SLOTS := 5
const ROSTER: Array[String] = [DEFAULT]
const NO_PERKS := "Brak premii"
const LOCKED_NAME := "Wkrótce"
const LOCKED_INFO := "Nowi władcy dojdą później"


## Władca na miejscu `slot` albo pusty tekst, gdy to puste miejsce.
static func at_slot(slot: int) -> String:
	return ROSTER[slot] if slot >= 0 and slot < ROSTER.size() else ""


## Premie władcy jednym tekstem, np. „Brak premii”.
static func perk_text(id: String) -> String:
	var list := perks(id)
	return NO_PERKS if list.is_empty() else ", ".join(list)


static func is_known(id: String) -> bool:
	return NAMES.has(id)


static func ruler_name(id: String) -> String:
	return str(NAMES.get(id, NAMES[DEFAULT]))


## Perki władcy; pusta lista dla domyślnego i nieznanego.
static func perks(id: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(PERKS.get(id, []) as Array)
	return out
