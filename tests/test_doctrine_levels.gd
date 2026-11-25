extends TestCase
## Poziomy doktryn: doktrynę z TechTree.LEVELED_DOCTRINES bada się ponownie na kolejne poziomy
## (+5 punktów procentowych za poziom), do TechTree.max_level w epoce zamku (I: 3, II: 5), a każdy
## poziom podnosi koszt kolejnych doktryn epoki jak nowa doktryna. Zapis trzyma poziomy w `levels`.

const T0 := 1_700_000_000_000
const R := EconomyConfig.Res


func _economy() -> Economy:
	var e := Economy.new(T0)
	for res in EconomyConfig.count():
		e.amounts[res] = 1 << 40
	return e


## Bada `code` (pierwszy raz albo kolejny poziom) od razu do końca w epoce `age`.
func _finish(r: Research, code: String, age: int = 0) -> Research.Result:
	var result := r.start(code, age, _economy(), T0)
	if result == Research.Result.OK:
		r.update(T0 + r.duration_ms)
	return result


func test_levels_raise_bonus_up_to_age_limit() -> bool:
	var r := Research.new()
	assert_eq(r.level("G1"), 0, "niezbadana: poziom 0")
	assert_eq(r.production_percent(R.WOOD), 100, "bez premii")
	assert_eq(_finish(r, "G1"), Research.Result.OK, "poziom 1")
	assert_eq(r.level("G1"), 1, "zbadana: poziom 1")
	assert_eq(r.production_percent(R.WOOD), 120, "poziom 1: efekt z drzewka +20%")
	assert_eq(_finish(r, "G1"), Research.Result.OK, "poziom 2")
	assert_eq(r.production_percent(R.WOOD), 125, "poziom 2: +5 punktów")
	assert_eq(_finish(r, "G1"), Research.Result.OK, "poziom 3")
	assert_eq(r.production_percent(R.WOOD), 130, "poziom 3: +30%")
	assert_eq(r.check("G1", 0), Research.Result.MAX_LEVEL, "epoka I: najwyżej 3 poziomy")
	assert_eq(r.check("G1", 1), Research.Result.OK, "epoka II pozwala na wyższy poziom")
	assert_eq(_finish(r, "G1", 1), Research.Result.OK, "poziom 4 w epoce II")
	assert_eq(_finish(r, "G1", 1), Research.Result.OK, "poziom 5 w epoce II")
	assert_eq(r.check("G1", 1), Research.Result.MAX_LEVEL, "epoka II: najwyżej 5 poziomów")
	assert_eq(r.production_percent(R.WOOD), 140, "poziom 5: +40%")
	return true


func test_only_leveled_doctrines_repeat() -> bool:
	var r := Research.new()
	_finish(r, "A1")
	assert_eq(r.check("A1", 0), Research.Result.ALREADY_DONE, "A1 bez poziomów (bitwa) jeszcze nie")
	_finish(r, "A39")
	assert_eq(r.check("A39", 0), Research.Result.ALREADY_DONE, "zwykła technologia raz")
	assert_eq(r.level("A39"), 1, "zwykła technologia: poziom 1")
	for code in TechTree.LEVELED_DOCTRINES:
		assert_true(TechTree.is_doctrine(code), "%s z poziomami jest doktryną" % code)
	return true


func test_level_cost_grows_like_next_doctrine() -> bool:
	var r := Research.new()
	var base := ResearchConfig.cost(0, 0)
	assert_eq(r.cost_of("G1"), base, "pierwsza doktryna po bazie")
	_finish(r, "G1")
	assert_eq(r.cost_of("G1"), ResearchConfig.cost(0, 1), "poziom 2: krok 1")
	assert_eq(r.cost_of("G2"), ResearchConfig.cost(0, 1), "inna doktryna też krok 1")
	_finish(r, "G1")
	assert_eq(r.cost_of("G2"), ResearchConfig.cost(0, 2), "dwa poziomy G1: G2 krok 2")
	assert_eq(r.cost_of("A39"), base, "zwykła technologia nadal po bazie")
	assert_eq(r.time_of("G1"), ResearchConfig.time_ms(0), "czas poziomu stały w epoce")
	r.start("G1", 0, _economy(), T0)
	assert_eq(r.cost_of("G2"), ResearchConfig.cost(0, 3), "poziom w toku podnosi koszt")
	assert_eq(r.check("G2", 0), Research.Result.BUSY, "jedno badanie naraz")
	assert_eq(r.level("G1"), 2, "w toku: poziom jeszcze stary")
	r.update(T0 + r.duration_ms)
	assert_eq(r.level("G1"), 3, "po końcu: nowy poziom")
	return true


func test_save_round_trip_keeps_levels() -> bool:
	var r := Research.new()
	_finish(r, "G1")
	_finish(r, "G1")
	_finish(r, "G2")
	r.start("G2", 0, _economy(), T0 + 1000)
	var d := r.save_data()
	assert_eq(d["levels"], {"G1": 2}, "zapis: poziomy od 2")
	var back := Research.new()
	assert_eq(back.load_data(d, T0 + 2000), 0, "nic nie pominięto")
	assert_eq(back.level("G1"), 2, "G1 poziom 2")
	assert_eq(back.level("G2"), 1, "G2 poziom 1")
	assert_eq(back.active, "G2", "poziom G2 w toku wraca")
	assert_eq(back.save_data(), d, "ten sam zapis po wczytaniu")
	var none := Research.new()
	_finish(none, "A39")
	assert_true(not none.save_data().has("levels"), "bez poziomów bez pola levels")
	return true


func test_load_rejects_bad_levels() -> bool:
	var r := Research.new()
	var skipped := r.load_data({"done": ["G1", "A39"], "levels": {"G1": 9, "A39": 2, "G2": 2, "X": 3}}, T0)
	assert_eq(skipped, 4, "poziom ponad limit, zwykła technologia, niezbadana i nieznana")
	assert_eq(r.level("G1"), 1, "zły poziom G1 wraca do 1")
	assert_eq(r.level("A39"), 1, "A39 bez poziomów")
	var ok := Research.new()
	assert_eq(ok.load_data({"done": ["G1"], "levels": {"G1": 3.0}}, T0), 0, "liczba z JSON jako float")
	assert_eq(ok.level("G1"), 3, "poziom 3")
	return true


func test_economy_rates_follow_level() -> bool:
	var r := Research.new()
	_finish(r, "G2")
	var one := Economy.rates(null, r)[R.FOOD]
	_finish(r, "G2")
	var two := Economy.rates(null, r)[R.FOOD]
	@warning_ignore("integer_division")
	assert_eq(two, EconomyConfig.BASE_PER_HOUR[R.FOOD] * 120 / 100, "G2 poziom 2: +20% żywności")
	assert_true(two >= one, "wyższy poziom nie zmniejsza produkcji")
	return true


func test_panel_texts() -> bool:
	var r := Research.new()
	assert_eq(ResearchPanel.state_text(r, "G1", 0, T0), "dostępna", "przed badaniem")
	_finish(r, "G1")
	assert_eq(ResearchPanel.state_text(r, "G1", 0, T0), "poziom 1/3", "poziom z limitem epoki")
	assert_eq(ResearchPanel.level_text(r, "G1", 0), "Premia +20%, następny poziom +25%", "premia i następny poziom")
	assert_eq(ResearchPanel.title_of(r, "G1", true), "G1 Karczowanie lasu, poziom 2", "tytuł następnego poziomu")
	assert_true(r.is_level_up("G1"), "przycisk Ulepsz")
	_finish(r, "G1")
	_finish(r, "G1")
	assert_eq(ResearchPanel.level_text(r, "G1", 0), "Premia +30%", "najwyższy poziom: bez następnego")
	assert_true(not ResearchPanel.can_research_more(r, "G1", 0), "bez kosztu na najwyższym poziomie")
	assert_eq(ResearchPanel.state_text(r, "A39", 0, T0), "dostępna", "zwykła technologia bez zmian")
	for line: Array in ResearchPanel.detail_lines(r, "G1", 0, T0, 296):
		assert_true(PixelFont.text_width(line[0] as String) <= 296, "linia mieści się: %s" % line[0])
	return true


func test_deterministic() -> bool:
	var a := Research.new()
	var b := Research.new()
	for code: String in ["G1", "G2", "G1", "A39", "G1"]:
		_finish(a, code)
		_finish(b, code)
	assert_eq(a.save_data(), b.save_data(), "ten sam przebieg, ten sam stan")
	return true
