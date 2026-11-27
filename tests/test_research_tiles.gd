extends TestCase
## Wygląd kafelków drzewka badań (#356): stan kafelka (zbadana, w toku, dostępna, niedostępna, perk
## wykluczony przez innego władcę), różne kolory stanów i zaznaczenie, którego nie da się pomylić
## z ramkami powiązań.

const S := ResearchPanel.TileState


func test_state_follows_research() -> bool:
	var r := Research.new()
	assert_eq(ResearchPanel.tile_state(r, "A2", 0), S.AVAILABLE, "A2 bez wymagań dostępna")
	assert_eq(ResearchPanel.tile_state(r, "A7", 0), S.LOCKED, "A7 bez A2 i A43 niedostępna")
	assert_eq(ResearchPanel.tile_state(r, "A47", 0), S.LOCKED, "A47 z epoki II w epoce I niedostępna")
	r.active = "A2"
	assert_eq(ResearchPanel.tile_state(r, "A2", 0), S.ACTIVE, "badana A2 w toku")
	r.active = ""
	r.done["A2"] = true
	assert_eq(ResearchPanel.tile_state(r, "A2", 0), S.DONE, "zbadana A2")
	r.active = "A2"
	assert_eq(ResearchPanel.tile_state(r, "A2", 0), S.DONE, "kolejny poziom doktryny: kafelek dalej zbadany")
	return true


func test_missing_building_locks_tile() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var r := Research.new()
	assert_eq(ResearchPanel.tile_state(r, "A2", 0, grid), S.LOCKED, "A2 bez Koszar niedostępna")
	return true


## Błąd z #356: technologia wykluczona przez perk innego władcy wyglądała jak dostępna.
func test_other_ruler_perk_is_locked() -> bool:
	var r := Research.new()
	r.done["A60"] = true
	assert_eq(ResearchPanel.tile_state(r, "O23", 0), S.PERK_LOCKED, "O23 to inna linia perka niż A60")
	assert_eq(ResearchPanel.tile_state(r, "A60", 0), S.DONE, "wybrana linia zbadana")
	return true


func test_state_colors_differ() -> bool:
	var states: Array[int] = [S.DONE, S.ACTIVE, S.AVAILABLE, S.LOCKED]
	for a in states:
		for b in states:
			if a < b:
				var same_bg := ResearchPanel.state_color(a, false) == ResearchPanel.state_color(b, false)
				var same_text := ResearchPanel.tile_text_color(a, false) == ResearchPanel.tile_text_color(b, false)
				assert_true(not (same_bg and same_text), "stany %d i %d wyglądają inaczej" % [a, b])
	assert_true(ResearchPanel.state_color(S.LOCKED, false) != ResearchPanel.state_color(S.AVAILABLE, false),
			"niedostępna ma inne tło niż dostępna, nie tylko inny napis")
	for s in states:
		assert_true(ResearchPanel.state_color(s, true) != ResearchPanel.state_color(s, false),
				"zaznaczony kafelek stanu %d jest jaśniejszy" % s)
	return true


func test_selection_differs_from_link_frames() -> bool:
	var reqs: Array[String] = ["A1"]
	var next: Array[String] = ["A2"]
	var linked: Array[String] = ["A3"]
	var frames: Array[Color] = [
		ResearchPanel.link_color("A1", reqs, next, linked, false),
		ResearchPanel.link_color("A1", reqs, next, linked, true),
		ResearchPanel.link_color("A2", reqs, next, linked, false),
		ResearchPanel.link_color("A3", reqs, next, linked, false),
	]
	for f in frames:
		assert_true(f != ResearchPanel.SELECTION_COLOR, "ramka powiązania %s inna niż zaznaczenie" % f)
	var tile := Rect2(10, 20, 30, 14)
	var outer := ResearchPanel.selection_rect(tile)
	assert_true(outer.encloses(tile) and outer != tile, "zaznaczenie rysuje się na zewnątrz kafelka")
	assert_eq(outer.grow(-1), tile, "o 1 px, w odstępie między kafelkami")
	assert_true(ResearchPanel.GAP >= 2, "ramka zaznaczenia nie dotyka sąsiedniego kafelka")
	return true
