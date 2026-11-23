extends TestCase
## Zaległy wynik ataku na gracza (#99, PendingFinish): treść `finish_attack` przetrwa zamknięcie gry,
## wraca z pliku w tym samym kształcie (liczby całkowite) i zły plik nie idzie na serwer.

const TEST_PATH := "user://test_attack_result.json"


func _body() -> Dictionary:
	var r := BattleResult.new()
	r.won = true
	r.percent = 60
	r.stars = [true, true, false] as Array[bool]
	r.loot = [600, 240, 120, 18] as Array[int]
	r.destroyed_ids = [12, 7] as Array[int]
	return AttackFinish.request("a1b2", r, 3, [5, 0, 2] as Array[int])


## Zapis i odczyt dają tę samą treść żądania i ten sam wynik do okna, także po JSON-ie (floaty).
func test_round_trip() -> bool:
	PendingFinish.clear(TEST_PATH)
	var p := PendingFinish.new()
	p.body = _body()
	p.fallen = 8
	assert_eq(p.write(TEST_PATH), OK, "zapis do pliku")
	var back := PendingFinish.read(TEST_PATH)
	assert_true(not back.is_empty(), "wynik czeka po ponownym starcie")
	assert_eq(back.fallen, 8, "polegli do okna wyniku")
	assert_eq(JSON.stringify(back.body), JSON.stringify(_body()), "ta sama treść żądania co po bitwie")
	assert_true(back.body["loot"] is Array[int], "łup w liczbach całkowitych")
	var r := back.result()
	assert_true(r != null and r.won and r.percent == 60, "wynik bitwy")
	assert_eq(r.stars, [true, true, false] as Array[bool], "gwiazdki")
	assert_eq(r.loot, [600, 240, 120, 18] as Array[int], "łup wysłany serwerowi")
	PendingFinish.clear(TEST_PATH)
	assert_true(PendingFinish.read(TEST_PATH).is_empty(), "po odpowiedzi serwera nic nie czeka")
	return true


## Ten sam wynik zapisany dwa razy daje identyczny plik (determinizm treści).
func test_same_result_same_file() -> bool:
	var a := PendingFinish.new()
	a.body = _body()
	var b := PendingFinish.new()
	b.body = _body()
	assert_eq(JSON.stringify(a.to_dict()), JSON.stringify(b.to_dict()), "identyczny zapis")
	return true


## Zły albo obcy plik nie daje zaległego wyniku: brak id, zły wynik, ujemny łup, zły kształt, inna wersja.
func test_invalid_file_is_ignored() -> bool:
	var good := PendingFinish.new()
	good.body = _body()
	var d := good.to_dict()
	assert_true(not PendingFinish.from_dict(d).is_empty(), "dobry plik")
	var cases: Array[Dictionary] = []
	for key: String in ["attack_id", "result", "loot", "survivors"]:
		var c := d.duplicate(true)
		(c["body"] as Dictionary).erase(key)
		cases.append(c)
	var bad_loot := d.duplicate(true)
	(bad_loot["body"] as Dictionary)["loot"] = [600, -1, 0, 0]
	cases.append(bad_loot)
	var short_loot := d.duplicate(true)
	(short_loot["body"] as Dictionary)["loot"] = [600]
	cases.append(short_loot)
	var bad_percent := d.duplicate(true)
	((bad_percent["body"] as Dictionary)["result"] as Dictionary)["percent"] = 140
	cases.append(bad_percent)
	var bad_ids := d.duplicate(true)
	(bad_ids["body"] as Dictionary)["destroyed"] = ["x"]
	cases.append(bad_ids)
	var version := d.duplicate(true)
	version["version"] = 99
	cases.append(version)
	cases.append({"version": PendingFinish.VERSION, "body": "x"})
	cases.append({})
	for c in cases:
		assert_true(PendingFinish.from_dict(c).is_empty(), "odrzucony: %s" % JSON.stringify(c))
	return true


## Nieznane pola z pliku nie trafiają do żądania (serwer odrzuca `unknown_field`).
func test_unknown_fields_dropped() -> bool:
	var p := PendingFinish.new()
	p.body = _body()
	var d := p.to_dict()
	(d["body"] as Dictionary)["extra"] = 1
	var back := PendingFinish.from_dict(d)
	assert_true(not back.body.has("extra"), "bez obcego pola")
	assert_eq(back.body.keys().size(), _body().keys().size(), "te same pola co AttackFinish.request")
	return true


## Zaległy wynik blokuje start nowego ataku na serwerze (review #283): `begin_attack` porzuciłby
## atak z wynikiem w pliku. Bez sieci nic nie startuje na serwerze, więc nic nie blokuje.
func test_pending_blocks_server_start() -> bool:
	var p := PendingFinish.new()
	assert_true(not p.blocks_start(true), "bez zaległego wyniku atak startuje")
	p.body = _body()
	assert_true(p.blocks_start(true), "z zaległym wynikiem najpierw wynik")
	assert_true(not p.blocks_start(false), "bez sieci wyprawa na bota idzie lokalnie")
	return true


## Awaria w środku zapisu (review #283): bez pliku głównego wynik wraca z pełnego .tmp albo z kopii .bak.
func test_read_falls_back_to_tmp_and_bak() -> bool:
	PendingFinish.clear(TEST_PATH)
	var p := PendingFinish.new()
	p.body = _body()
	p.fallen = 3
	assert_eq(p.write(TEST_PATH), OK, "pierwszy zapis")
	DirAccess.rename_absolute(TEST_PATH, TEST_PATH + ".tmp")
	assert_eq(PendingFinish.read(TEST_PATH).fallen, 3, "z pełnego .tmp")
	DirAccess.rename_absolute(TEST_PATH + ".tmp", TEST_PATH + ".bak")
	assert_eq(PendingFinish.read(TEST_PATH).fallen, 3, "z kopii .bak")
	var f := FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string("{zły")
	f.close()
	assert_eq(PendingFinish.read(TEST_PATH).fallen, 3, "zły plik główny: kopia")
	PendingFinish.clear(TEST_PATH)
	assert_true(PendingFinish.read(TEST_PATH).is_empty(), "po wyczyszczeniu nic")
	return true
