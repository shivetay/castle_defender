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


static func is_known(id: String) -> bool:
	return NAMES.has(id)


static func ruler_name(id: String) -> String:
	return str(NAMES.get(id, NAMES[DEFAULT]))


## Perki władcy; pusta lista dla domyślnego i nieznanego.
static func perks(id: String) -> Array[String]:
	var out: Array[String] = []
	out.assign(PERKS.get(id, []) as Array)
	return out
