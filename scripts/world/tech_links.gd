class_name TechLinks
extends RefCounted
## Powiązania technologii do ekranu drzewka (po teście na telefonie): co technologia odblokowuje
## (technologie, które jej wymagają) i z czym łączy się przez towary. Przykład: A39 Drzewcarstwo
## daje Drzewcarza, który robi kopię, a kopii potrzebuje Kopijnik z A22, więc A39 i A22 są powiązane.
## Liczone z danych (TechTree, BuildConfig, GoodsConfig, UnitTypes), bez osobnej tabeli do pilnowania.


## Technologie, które wymagają `code` (bezpośrednio), w kolejności drzewka.
static func unlocks(code: String) -> Array[String]:
	var out: Array[String] = []
	for other in TechTree.codes():
		if TechTree.requires(other).has(code):
			out.append(other)
	return out


## Towary, które wytwarzają budynki odblokowane przez `code`.
static func outputs(code: String) -> Dictionary:
	var out := {}
	for kind: int in _kinds_of(code):
		var producer: String = GoodsConfig.PRODUCER_KINDS.get(kind, "")
		for row: Array in GoodsConfig.RECIPES:
			if row[0] == producer:
				for good: int in row[5] as Dictionary:
					out[good] = true
	return out


## Towary, których potrzebują budynki i jednostki odblokowane przez `code`.
static func inputs(code: String) -> Dictionary:
	var out := {}
	for kind: int in _kinds_of(code):
		var producer: String = GoodsConfig.PRODUCER_KINDS.get(kind, "")
		for row: Array in GoodsConfig.RECIPES:
			if row[0] == producer:
				for good: int in row[4] as Dictionary:
					out[good] = true
	for unit in UnitTypes.count():
		if UnitTypes.required_tech(unit) == code:
			for good: int in UnitTypes.goods_cost(unit):
				out[good] = true
	return out


## Technologie powiązane przez towary: jedna robi towar, którego druga potrzebuje (w obie strony).
## Bez samej `code`, jej wymagań i tego, co odblokowuje (te są w osobnych liniach).
static func related(code: String) -> Array[String]:
	var mine_out := outputs(code)
	var mine_in := inputs(code)
	var skip := TechTree.requires(code) + unlocks(code)
	skip.append(code)
	var out: Array[String] = []
	for other in TechTree.codes():
		if skip.has(other):
			continue
		if _shares(mine_out, inputs(other)) or _shares(mine_in, outputs(other)):
			out.append(other)
	return out


static func _shares(a: Dictionary, b: Dictionary) -> bool:
	for k: int in a:
		if b.has(k):
			return true
	return false


## Rodzaje budynków, które odblokowuje technologia `code`.
static func _kinds_of(code: String) -> Array[int]:
	var out: Array[int] = []
	for kind: int in BuildConfig.REQUIRED_TECH:
		if BuildConfig.REQUIRED_TECH[kind] == code:
			out.append(kind)
	return out
