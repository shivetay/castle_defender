extends TestCase
## Widok bitwy po teście na telefonie: jednostki „przechodziły przez cały mur” i „przeskakiwały nad
## sobą”. Symulacja była poprawna, a mylił widok: zburzone odcinki rysowały się jako całe, odznaka
## oddziału stała w średniej pozycji (na murze, gdy oddział był po obu stronach), a nachodzące
## odznaki skakały co klatkę.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit


func _bot_battle(army: Array) -> Battle:
	var bot := BotRoster.generate(0)
	return Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn, 7)


## Stan zniszczeń: tylko uszkodzone budynki, z progów BuildingTypes.state_for_hp; zburzony to gruz.
func test_states_follow_structure_hp() -> bool:
	var b := _bot_battle([[U.PEASANT, 3]])
	assert_eq(BattleView.states_of(b), {}, "na starcie wszystko całe")
	var wall: Battle.Structure = null
	var hut: Battle.Structure = null
	for id: int in b.structures:
		var s: Battle.Structure = b.structures[id]
		if wall == null and BuildingTypes.is_wall(s.kind):
			wall = s
		elif hut == null and s.kind == K.LUMBER_HUT:
			hut = s
	wall.hp = 0
	hut.hp = hut.max_hp / 2
	var states := BattleView.states_of(b)
	assert_eq(int(states.get(wall.id, -1)), BuildingTypes.State.RUBBLE, "zburzony odcinek to gruz")
	assert_eq(int(states.get(hut.id, -1)), BuildingTypes.state_for_hp(hut.hp, hut.max_hp), "uszkodzona chata")
	assert_eq(states.size(), 2, "całych budynków nie ma w słowniku")
	return true


## Odznaka stoi na żywej jednostce oddziału, nawet gdy oddział jest rozdzielony (średnia wypada obok).
func test_badge_sits_on_a_member() -> bool:
	var b := _bot_battle([[U.PEASANT, 3]])
	var members: Array[Battle.Fighter] = []
	for f in b.fighters:
		if f.side == Battle.Side.ATTACKER:
			members.append(f)
	# dwóch po jednej stronie, jeden daleko po drugiej: średnia leży między nimi, gdzie nikogo nie ma
	members[0].x = 10 * BattleConfig.SUB
	members[0].y = 10 * BattleConfig.SUB
	members[1].x = 10 * BattleConfig.SUB
	members[1].y = 11 * BattleConfig.SUB
	members[2].x = 20 * BattleConfig.SUB
	members[2].y = 10 * BattleConfig.SUB
	var sq: Dictionary = b.squads_view(Battle.Side.ATTACKER)[0]
	var on_member := false
	for f in members:
		on_member = on_member or (f.x == int(sq["x"]) and f.y == int(sq["y"]))
	assert_true(on_member, "odznaka na jednej z jednostek")
	assert_true(sq.has("key"), "oddział ma klucz dla układu odznak")
	return true


## Odznaki nie skaczą: zepchnięta niżej trzyma wiersz, póki wyżej nie będzie wolno przez
## SETTLE_FRAMES klatek z rzędu; bez pamięci układ jest jak dawniej.
func test_badge_rows_are_stable() -> bool:
	var a := {"key": 1, "unit": U.AXE_WARRIOR, "alive": 5, "hp": 300, "max_hp": 300, "x": 2000, "y": 2000}
	var c := {"key": 2, "unit": U.ARCHER, "alive": 5, "hp": 175, "max_hp": 175, "x": 2000, "y": 2000}
	var rows := {}
	var free := {}
	var origins := BattleView.layout([a, c] as Array[Dictionary], rows, free)
	assert_eq(int(rows[2]), 1, "nachodząca odznaka schodzi wiersz niżej")
	c["x"] = 2000 + BattleConfig.SUB * 4  # odznaki już się nie stykają
	for i in BattleView.SETTLE_FRAMES - 1:
		origins = BattleView.layout([a, c] as Array[Dictionary], rows, free)
		assert_eq(int(rows[2]), 1, "klatka %d: trzyma wiersz" % i)
	origins = BattleView.layout([a, c] as Array[Dictionary], rows, free)
	assert_eq(int(rows[2]), 0, "po SETTLE_FRAMES wraca na miejsce przy jednostce")
	assert_eq(origins[1], BattleView.badge_origin(c), "odznaka znów nad jednostką")
	# mijanie: odznaki co klatkę na zmianę stykają się i nie, a wiersz zmienia się najwyżej raz
	var changes := 0
	var last := int(rows[2])
	for i in 40:
		c["x"] = 2000 + (BattleConfig.SUB * 4 if i % 2 == 0 else 0)
		BattleView.layout([a, c] as Array[Dictionary], rows, free)
		if int(rows[2]) != last:
			changes += 1
			last = int(rows[2])
	assert_true(changes <= 1, "przy mijaniu odznaka nie skacze co klatkę (zmian: %d)" % changes)
	return true


## Kropka jednostki w całych pikselach, wyśrodkowana na jej pozycji.
func test_unit_dot_is_pixel_aligned() -> bool:
	var at := BattleView.dot_origin(5 * BattleConfig.SUB + BattleConfig.SUB / 2, 3 * BattleConfig.SUB + BattleConfig.SUB / 2)
	assert_eq(at, Vector2i(5 * TerrainMap.CELL + TerrainMap.CELL / 2 - 1, 3 * TerrainMap.CELL + TerrainMap.CELL / 2 - 1), "środek kratki")
	return true
