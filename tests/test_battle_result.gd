extends TestCase
## Wynik ataku (#99): procent zniszczeń bez odcinków muru, 3 gwiazdki (brama, połowa zamku, donżon),
## łup ze skarbca zamku-bota, ten sam wynik dla tego samego przebiegu, zamek obrońcy bez strat
## po bitwie i okno wyniku na 320×180.

const K := BuildingTypes.Kind
const U := UnitTypes.Unit
const VIEW := Vector2(320, 180)


func _battle(army: Array, i: int = 0) -> Battle:
	var bot := BotRoster.generate(i)
	return Battle.create_squads(bot.grid, bot.objective, army, bot.defenders, bot.spawn,
			PixelCanvas.hash2(bot.seed_value, i, 0xa77) & 0x7fffffff)


## Silna armia zdobywa pierwszy zamek: wygrana daje gwiazdkę donżonu; ten sam przebieg, ten sam wynik.
func test_win_and_determinism() -> bool:
	var army := [[U.AXE_WARRIOR, 12], [U.ARCHER, 8]]
	var a := _battle(army)
	a.run()
	var ra := BattleResult.of(a)
	assert_true(ra.won, "silna armia wygrywa")
	assert_true(ra.stars[BattleResult.Star.KEEP], "gwiazdka za donżon")
	assert_true(ra.star_count() >= 1 and ra.percent > 0, "jest wynik")
	var b := _battle(army)
	b.run()
	var rb := BattleResult.of(b)
	assert_eq([rb.percent, rb.stars, rb.won], [ra.percent, ra.stars, ra.won], "ten sam przebieg, ten sam wynik")
	return true


## Przegrana bez szturmu: bez gwiazdki donżonu i bez wygranej.
func test_loss_has_no_keep_star() -> bool:
	var b := _battle([[U.PEASANT, 1]], 10)
	b.run()
	var r := BattleResult.of(b)
	assert_true(not r.won and not r.stars[BattleResult.Star.KEEP], "przegrana bez donżonu")
	return true


## Procent liczy budynki bez murów; gwiazdki: połowa przy 50%, brama przy zburzonej bramie albo
## atakującym na murze.
func test_percent_and_stars_rules() -> bool:
	var b := _battle([[U.AXE_WARRIOR, 1]])
	var buildings: Array[Battle.Structure] = []
	var walls := 0
	var gate: Battle.Structure = null
	var gates: Array[Battle.Structure] = []
	for id: int in b.structures:
		var s: Battle.Structure = b.structures[id]
		if BuildingTypes.is_wall(s.kind):
			walls += 1
		else:
			buildings.append(s)
		if s.kind == K.GATE:
			gate = s
			gates.append(s)
	assert_true(walls > 0 and gate != null, "zamek ma mury i bramę")
	var r := BattleResult.of(b)
	assert_eq(r.total, buildings.size(), "procent bez odcinków muru")
	assert_eq([r.percent, r.star_count()], [0, 0], "przed bitwą nic")
	for id: int in b.structures:
		if BuildingTypes.is_wall(b.structures[id].kind):
			b.structures[id].hp = 0
	assert_eq(BattleResult.of(b).percent, 0, "zburzone mury nie liczą się do procentu")
	var half := (buildings.size() + 1) / 2
	for k in half:
		buildings[k].hp = 0
	r = BattleResult.of(b)
	assert_eq(r.percent, half * 100 / buildings.size(), "procent zburzonych budynków")
	assert_true(r.stars[BattleResult.Star.HALF], "połowa zamku")
	for g in gates:
		g.hp = g.max_hp  # pierścień może mieć drugą bramę na drodze
	for f in b.fighters:
		f.climbed = false
	assert_true(not BattleResult.of(b).stars[BattleResult.Star.GATE], "brama cała: bez gwiazdki")
	gate.hp = 0
	assert_true(BattleResult.of(b).stars[BattleResult.Star.GATE], "zburzona brama")
	gate.hp = gate.max_hp
	b.fighters[0].climbed = true
	assert_true(BattleResult.of(b).stars[BattleResult.Star.GATE], "atakujący na murze")
	return true


## Łup tylko po wygranej: połowę skarbca chroni magazyn, z reszty 20% przy 100% zniszczeń; ponowny
## atak daje połowę; magazyn gracza przyjmuje tylko do pojemności.
func test_loot() -> bool:
	var r := BattleResult.new()
	r.won = true
	r.percent = 100
	r.compute_loot(0, false)
	assert_eq(r.loot, [100, 100, 100, 2] as Array[int], "zamek 1, 100%")
	r.compute_loot(0, true)
	assert_eq(r.loot, [50, 50, 50, 1] as Array[int], "ponowny atak: połowa")
	r.percent = 50
	r.compute_loot(19, false)
	var s := BattleResult.stash(19)
	assert_eq(r.loot[0], s[0] / 2 * 20 / 100 * 50 / 100, "zamek 20, 50%")
	assert_true(BattleResult.stash(19)[0] > BattleResult.stash(0)[0], "bogatsze dalsze zamki")
	# wygrana przy małych zniszczeniach liczy się jak 50%, a przy większych jak faktyczny procent
	r.percent = 16
	r.won = true
	assert_eq(r.loot_percent(), BattleResult.WIN_LOOT_PERCENT, "szybka wygrana: jak 50%")
	r.compute_loot(0, false)
	assert_eq(r.loot[0], 50, "zamek 1: 50 drewna")
	r.percent = 80
	assert_eq(r.loot_percent(), 80, "większe zniszczenia: faktyczny procent")
	r.won = false
	r.percent = 90
	r.compute_loot(5, false)
	assert_eq(r.loot, [0, 0, 0, 0] as Array[int], "przegrana: bez łupu, nawet przy dużych zniszczeniach")
	var e := Economy.new(0)
	e.amounts[0] = Economy.capacity(0) - 10
	r.loot = [100, 0, 0, 0] as Array[int]
	assert_eq(r.apply_loot(e)[0], 10, "pełny magazyn przyjmuje tylko resztę")
	return true


## Odbudowa: bitwa działa na kopii, więc siatka zamku obrońcy po bitwie jest taka jak przed nią.
func test_defender_castle_is_intact_after_battle() -> bool:
	var bot := BotRoster.generate(3)
	var before := bot.grid.save_data()
	var b := Battle.create_squads(bot.grid, bot.objective, [[U.AXE_WARRIOR, 12], [U.ARCHER, 8]], bot.defenders,
			bot.spawn, 7)
	b.run()
	assert_true(b.winner != Battle.Winner.NONE, "bitwa się skończyła")
	# nawet całkiem zburzony zamek w bitwie nie zmienia siatki zamku
	for id: int in b.structures:
		b.structures[id].hp = 0
	assert_eq(BattleResult.of(b).percent, 100, "w bitwie wszystko padło")
	assert_eq(bot.grid.save_data(), before, "zamek po bitwie w pełnym stanie")
	return true


## Okno wyniku mieści się na 320×180, a linie mieszczą się w oknie.
func test_panel_layout() -> bool:
	var p := ResultPanel.panel_rect(VIEW)
	assert_true(p.position.x >= Hud.CORNER_INSET and p.end.x <= VIEW.x - Hud.CORNER_INSET, "okno w poziomie")
	assert_true(p.position.y >= 0 and p.end.y <= VIEW.y, "okno w pionie")
	var c := ResultPanel.close_rect(VIEW)
	assert_true(p.encloses(c) and c.size.x >= 12 and c.size.y >= 12, "Dalej w oknie, cel ≥ 12×12")
	var r := BattleResult.new()
	r.percent = 100
	r.stars = [true, true, true]
	r.won = true
	var got: Array[int] = [9999, 9999, 9999, 999]
	var lines := ResultPanel.lines(r, got, 99, "Odblokowany: 20. %s" % BotRoster.NAMES[19])
	var bottom := p.position.y + 30 + lines.size() * (PixelFont.LINE + 2)
	assert_true(bottom <= c.position.y, "linie nad przyciskiem (%d)" % int(bottom))
	for line: Array in lines:
		assert_true(PixelFont.text_width(line[0] as String) <= p.size.x - 8, "„%s” mieści się" % line[0])
	return true
