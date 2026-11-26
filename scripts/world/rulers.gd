class_name Rulers
extends RefCounted
## Władcy zamku (#228). Na start każdy gracz dostaje domyślnego władcę bez żadnych premii, żeby
## wybór postaci nie blokował pierwszej synchronizacji zamku (#23). Każdy władca ma najwyżej jeden perk
## wrodzony (#308, ADR 0002) z osobnej puli, innej niż perki z technologii (RulerPerks); pula i nowi władcy
## dojdą osobnym zadaniem. Perk z technologii gracz odblokowuje badaniem niezależnie od władcy.

## Identyfikator domyślnego władcy w profilu gracza.
const DEFAULT := "kasztelan"

## Nazwy władców w UI.
const NAMES := {
	DEFAULT: "Kasztelan",
}

## Perk wrodzony władcy (#308): nazwa perka albo pusty napis. Domyślny władca nie ma żadnego.
const INNATE := {
	DEFAULT: "",
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


## Perk wrodzony władcy jednym tekstem, np. „Brak premii”.
static func perk_text(id: String) -> String:
	var innate := innate_perk(id)
	return NO_PERKS if innate.is_empty() else innate


static func is_known(id: String) -> bool:
	return NAMES.has(id)


static func ruler_name(id: String) -> String:
	return str(NAMES.get(id, NAMES[DEFAULT]))


## Perk wrodzony władcy; pusty napis dla domyślnego i nieznanego.
static func innate_perk(id: String) -> String:
	return str(INNATE.get(id, ""))
