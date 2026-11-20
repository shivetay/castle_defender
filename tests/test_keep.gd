extends TestCase
## Donżon jako cel ataku (#120): Wieża grodowa stoi od startu obok Dworu, bitwa kończy się
## dopiero po jej upadku albo zdobyciu, a zniszczenie Dworu bitwy nie kończy.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const W := Battle.Winner
const E := Battle.EndReason
const SPAWN := Vector2i(32, 60)
const MAIN := preload("res://scripts/main.gd")


## Zamek jak w nowej grze: Dwór i donżon na swoich miejscach.
func _castle(keep_level: int = 1) -> BuildGrid:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	grid.place(grid.manor_spot(64), K.MANOR, 3)
	grid.place(grid.keep_spot(64), K.KEEP, keep_level)
	return grid


func test_keep_stands_next_to_manor_and_is_unique() -> bool:
	var grid := _castle()
	assert_true(grid.keep_id() != 0, "donżon stoi")
	var manor := grid.buildings[grid.manor_id()]
	var keep := grid.buildings[grid.keep_id()]
	assert_true(not manor.intersects(keep), "obok Dworu, nie na nim")
	assert_true(absi(keep.position.x - manor.position.x) <= 6 and absi(keep.position.y - manor.position.y) <= 6,
			"blisko Dworu")
	assert_true(BuildingTypes.is_unique(K.KEEP) and BuildingTypes.is_unique(K.MANOR), "nie do rozebrania")
	assert_true(not BuildingTypes.is_unique(K.TOWER), "wieżę drewnianą można rozebrać")
	assert_true(not BuildingTypes.has_levels(K.KEEP), "donżon bez ulepszeń (#232)")
	assert_eq(BuildConfig.max_level(K.KEEP, BuildingTypes.MAX_LEVEL), 1, "nawet przy Dworze 5")
	return true


## #97 + #120: walidacja seeda mapy sprawdza też miejsce na donżon.
func test_every_new_map_has_room_for_keep() -> bool:
	var rng := RandomNumberGenerator.new()
	rng.seed = 120
	for i in 200:
		var s := WorldSeed.first_playable((rng.randi() & WorldSeed.MAX_SEED) | 1)
		var grid := BuildGrid.new(TerrainMap.generate(s))
		grid.place(grid.manor_spot(WorldSeed.MANOR_MAX_RING), K.MANOR)
		if not grid.keep_spot(WorldSeed.KEEP_MAX_RING).has_area():
			assert_true(false, "seed %d: brak miejsca na donżon" % s)
			break
	return true


func test_battle_targets_the_keep() -> bool:
	var grid := _castle()
	var b := Battle.for_castle(grid, {U.AXE_WARRIOR: 4}, {}, SPAWN, 1)
	assert_eq(b.objective, grid.keep_id(), "celem jest donżon, nie Dwór")
	return true


## Kryterium #120: zniszczenie Dworu nie kończy bitwy.
func test_destroying_manor_does_not_end_battle() -> bool:
	var grid := _castle()
	var b := Battle.for_castle(grid, {U.AXE_WARRIOR: 4}, {}, SPAWN, 1)
	b.structures[grid.manor_id()].hp = 0
	for i in 30:
		b.step()
	assert_eq(b.winner, W.NONE, "bitwa trwa mimo zburzonego Dworu")
	return true


## Kryterium #120: bitwa kończy się zwycięstwem po upadku donżonu.
func test_destroyed_keep_wins() -> bool:
	var grid := _castle()
	var b := Battle.for_castle(grid, {U.AXE_WARRIOR: 4}, {}, SPAWN, 1)
	b.step()
	b.structures[grid.keep_id()].hp = 0
	b.step()
	assert_eq(b.winner, W.ATTACKER, "upadek donżonu to zwycięstwo atakującego")
	assert_eq(b.end_reason, E.DESTROYED, "powód: zniszczenie")
	return true


## Kryterium #120: zdobycie, czyli piechota utrzymuje się przy donżonie 10 s bez obrońców.
func test_infantry_captures_the_keep() -> bool:
	var grid := _castle(5)  # mocny donżon: piechota nie zburzy go w 10 s
	var b := Battle.for_castle(grid, {U.AXE_WARRIOR: 2}, {}, SPAWN, 9)
	assert_eq(b.run(), W.ATTACKER, "atakujący wygrywa")
	assert_eq(b.end_reason, E.CAPTURED, "przez zdobycie")
	assert_true(b.structures[grid.keep_id()].hp > 0, "donżon stoi, ale jest zdobyty")
	return true


func test_defender_near_keep_blocks_capture() -> bool:
	var grid := _castle(5)
	var b := Battle.for_castle(grid, {U.AXE_WARRIOR: 1}, {U.TRACKER: 1}, SPAWN, 9)
	var zone := grid.buildings[grid.keep_id()].grow(1)
	var spot := zone.position
	for f in b.fighters:
		f.x = spot.x * BattleConfig.SUB + BattleConfig.SUB / 2
		f.y = spot.y * BattleConfig.SUB + BattleConfig.SUB / 2
		f.cooldown = 1000  # bez walki: sprawdzamy tylko obsadę
	b.step()
	assert_eq(b.capture_ticks, 0, "obrońca przy donżonie: brak zdobywania")
	for f in b.fighters:
		if f.side == Battle.Side.DEFENDER:
			f.hp = 0
	b.step()
	assert_eq(b.capture_ticks, 1, "bez obrońcy zdobywanie rusza")
	return true


func test_engineering_and_cavalry_do_not_capture() -> bool:
	var grid := _castle(5)
	var b := Battle.for_castle(grid, {U.DIGGER: 1, U.RIDER: 1}, {}, SPAWN, 9)
	var spot := grid.buildings[grid.keep_id()].grow(1).position
	for f in b.fighters:
		f.x = spot.x * BattleConfig.SUB + BattleConfig.SUB / 2
		f.y = spot.y * BattleConfig.SUB + BattleConfig.SUB / 2
	b.step()
	assert_eq(b.capture_ticks, 0, "zdobywa tylko piechota (lekka i ciężka)")
	return true


## Pierścienie liczą się od całego Dworu, a nie od jego lewego górnego rogu (review #152): na pustej
## łące pierwsze miejsce leży w pierścieniu 1 wokół Dworu z każdej strony tak samo daleko.
func test_keep_rings_are_measured_from_the_whole_manor() -> bool:
	var grid := BuildGrid.new(TerrainMap.generate(1337))
	var manor := grid.place(grid.manor_spot(64), K.MANOR, 3)
	var m := grid.buildings[manor]
	var spot := grid.spot_around(m, K.KEEP, 6)
	assert_true(spot.has_area(), "jest miejsce")
	var gap_x := maxi(m.position.x - spot.end.x, spot.position.x - m.end.x)
	var gap_y := maxi(m.position.y - spot.end.y, spot.position.y - m.end.y)
	assert_true(maxi(gap_x, gap_y) <= 1, "donżon w pierwszym wolnym pierścieniu wokół Dworu")
	return true


## Po zniszczeniu celu licznik zdobycia stoi (review #152).
func test_capture_stops_counting_on_destroyed_keep() -> bool:
	var grid := _castle()
	var b := Battle.for_castle(grid, {U.AXE_WARRIOR: 1}, {}, SPAWN, 1)
	var keep := b.structures[grid.keep_id()]
	for f in b.fighters:
		f.x = keep.rect.position.x * BattleConfig.SUB
		f.y = (keep.rect.position.y - 1) * BattleConfig.SUB
	keep.hp = 0
	b.capture_ticks = 5
	b._update_capture()
	assert_eq(b.capture_ticks, 5, "zniszczony cel nie liczy zdobycia")
	return true


## #232: karta donżonu ma sam Zamknij (bez Ulepsz i Rozbierz), a opisy mieszczą się na 320 px.
func test_keep_card_has_only_close() -> bool:
	var view := Vector2(320, 180)
	assert_eq(Hud.card_buttons(false, false, false, true), [Hud.CardButton.CLOSE] as Array[int], "sam Zamknij")
	var card := Hud.card_rects(view, false, false, false, true)
	assert_eq(card.size(), 1, "jeden przycisk")
	var b := Hud.content_bounds(view, Rect2())
	assert_eq(Hud.target_at(card[0].get_center(), view, b.y, false, true, false, false, false, false, true),
			Hud.Target.CARD + Hud.CardButton.CLOSE, "dotyk: Zamknij")
	assert_true(card[0].size.x >= 12 and card[0].size.y >= 12, "cel dotyku co najmniej 12×12")
	assert_eq(MAIN.upgrade_info(K.KEEP, 1, 5, false), MAIN.KEEP_INFO, "karta bez kosztu ulepszenia")
	assert_true(PixelFont.text_width(MAIN.KEEP_INFO) <= Hud.CARD_MIN_W - 8, "opis mieści się na karcie")
	var grid := _castle()
	assert_eq(BuildQueue.new().upgrade_hint(grid, grid.keep_id()), BuildQueue.KEEP_HINT, "komunikat bez ulepszenia")
	assert_true(PixelFont.text_width(BuildQueue.KEEP_HINT) <= Hud.MESSAGE_MAX_WIDTH, "komunikat mieści się w pasku")
	# stare zlecenie ulepszenia donżonu: zwykła karta, na której środkowy przycisk to Anuluj (review #244)
	assert_true(MAIN.plain_card(K.KEEP, false), "donżon bez zlecenia: sam Zamknij")
	assert_true(not MAIN.plain_card(K.KEEP, true), "donżon ze zleceniem: zwykła karta")
	assert_true(not MAIN.plain_card(K.TOWER, false), "inne budynki: zwykła karta")
	assert_true(Hud.card_buttons(false, false, false, MAIN.plain_card(K.KEEP, true)).has(Hud.CardButton.DEMOLISH),
			"jest przycisk Anuluj")
	var economy := Economy.new(0)
	assert_true(BuildQueue.new().order_upgrade(grid, economy, grid.keep_id(), 0) != BuildQueue.Result.OK,
			"ulepszenia nie da się zlecić")
	return true
