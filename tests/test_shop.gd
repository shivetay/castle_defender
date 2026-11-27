extends TestCase
## Sklep w Targu (#408): katalog z serwera (niezaufany: nazwy, liczby, najwyżej 3 oferty na grupę), odliczanie
## odnowienia z czasów serwera, stan kart (Odbierz, odliczanie, Magazyn pełny), karta Targu w HUD-zie
## i liczby z migracji `*_shop.sql`.

const MIGRATION := "res://supabase/migrations/20261127200000_shop.sql"
const NOW := 1_000_000_000


func _row(group: int, offer: int, slot: int, res: int, amount: int, next_at: Variant = null) -> Dictionary:
	return {"group_id": group, "group_name": "Grupa %d" % group, "sort_order": group, "offer_id": offer, "slot": slot,
			"name": "Oferta %d" % offer, "resource": res, "amount": amount, "cooldown_minutes": 60,
			"next_available_at": next_at, "server_now": "2026-11-27T12:00:00.000000+00:00"}


func test_countdown_format() -> bool:
	assert_eq(ShopNet.countdown(0), "", "bez odliczania")
	assert_eq(ShopNet.countdown(15 * 60000), "15 min", "15 min")
	assert_eq(ShopNet.countdown(14 * 60000 + 1), "15 min", "pełne minuty w górę")
	assert_eq(ShopNet.countdown(59 * 1000), "1 min", "poniżej minuty to 1 min")
	assert_eq(ShopNet.countdown((2 * 60 + 15) * 60000), "2 h 15 min", "2 h 15 min")
	assert_eq(ShopNet.countdown(2 * 3600000), "2 h", "pełne godziny")
	assert_eq(ShopNet.countdown((26 * 60) * 60000), "1 d 2 h", "doby")
	assert_eq(ShopNet.countdown(30 * 24 * 3600000), "30 d", "najdłuższe odnowienie")
	return true


func test_iso_time_from_postgrest() -> bool:
	assert_eq(ShopNet.iso_ms("1970-01-01T00:00:01.500000+00:00"), 1500, "ułamek sekundy")
	assert_eq(ShopNet.iso_ms("1970-01-01T01:00:00Z"), 3600000, "UTC z Z")
	assert_eq(ShopNet.iso_ms("1970-01-01T02:00:00+01:00"), 3600000, "przesunięcie strefy")
	assert_eq(ShopNet.iso_ms("zły czas"), -1, "zły tekst")
	assert_eq(ShopNet.wait_ms("2026-11-27T14:15:00+00:00", "2026-11-27T12:00:00+00:00"), (2 * 60 + 15) * 60000,
			"odliczanie z czasów serwera")
	assert_eq(ShopNet.wait_ms("2026-11-27T11:00:00+00:00", "2026-11-27T12:00:00+00:00"), 0, "minione odnowienie")
	assert_eq(ShopNet.wait_ms(null, "2026-11-27T12:00:00+00:00"), 0, "do odbioru")
	return true


func test_catalog_groups_and_limits() -> bool:
	var rows := [
		_row(1, 10, 1, EconomyConfig.Res.WOOD, 300),
		_row(1, 11, 2, EconomyConfig.Res.GOLD, 500, "2026-11-27T12:15:00+00:00"),
		_row(1, 12, 3, EconomyConfig.Res.STONE, 99999),
		_row(1, 13, 3, EconomyConfig.Res.FOOD, 10),
		_row(2, 20, 1, 9, 10),
		_row(2, 21, 1, EconomyConfig.Res.FOOD, 0),
		_row(3, 30, 1, EconomyConfig.Res.FOOD, 150),
		"nie wiersz",
	]
	var groups := ShopNet.parse_catalog(rows, NOW)
	assert_eq(groups.size(), 2, "grupy z dobrymi ofertami, w kolejności serwera")
	assert_eq(groups[0].offers.size(), ShopNet.MAX_OFFERS, "najwyżej 3 oferty w grupie")
	assert_eq(groups[0].offers[1].amount, 100, "złoto przycięte do 100")
	assert_eq(groups[0].offers[2].amount, 2000, "inne surowce do 2000")
	assert_eq(groups[0].offers[0].ready_at_ms, 0, "drewno do odbioru")
	assert_eq(groups[0].offers[1].ready_at_ms, NOW + 15 * 60000, "złoto za 15 min od teraz na telefonie")
	assert_eq(groups[1].id, 3, "grupa bez dobrych ofert pominięta")
	assert_eq(ShopNet.parse_catalog({"error": "x"}, NOW).size(), 0, "zła odpowiedź: pusto")
	return true


func test_names_from_panel_are_safe() -> bool:
	assert_eq(ShopNet.safe_text("  Dar   dla @0 gracza  "), "Dar dla 0 gracza", "bez znaku ikony i podwójnych spacji")
	assert_eq(ShopNet.safe_text("Bardzo długa nazwa oferty z panelu").length(), ShopNet.NAME_MAX, "najwyżej 24 znaki")
	assert_eq(ShopNet.safe_text("Żółć"), "Żółć", "polskie litery zostają")
	var row := _row(1, 10, 1, EconomyConfig.Res.WOOD, 5)
	row["name"] = "@@@"
	assert_eq(ShopNet.offer_from(row, NOW).name, "Drewno", "pusta nazwa: nazwa surowca")
	return true


func test_claim_response() -> bool:
	var c := ShopNet.parse_claim({"offer_id": 7, "resource": 3, "amount": 50, "claimed_at": "2026-11-27T12:00:00+00:00",
			"next_available_at": "2026-11-27T13:00:00+00:00"})
	assert_eq(int(c["offer_id"]), 7, "oferta")
	assert_eq(int(c["amount"]), 50, "ilość")
	assert_eq(int(c["wait_ms"]), 3600000, "odnowienie godzinę")
	assert_true(ShopNet.parse_claim({"offer_id": 7, "resource": 8, "amount": 1}).is_empty(), "zły surowiec")
	assert_eq(ShopNet.error_text("storage_full"), "Magazyn pełny", "pełny magazyn")
	assert_eq(ShopNet.error_text("network"), "Brak połączenia", "brak sieci")
	assert_eq(ShopNet.claim_request(7), {"offer_id": 7}, "treść żądania bez id gracza")
	return true


func test_card_states() -> bool:
	var o := ShopNet.Offer.new()
	o.id = 5
	o.resource = EconomyConfig.Res.WOOD
	o.amount = 300
	var amounts: Array[int] = [800, 0, 0, 0]
	var caps: Array[int] = [1000, 1000, 1000, 0]
	assert_eq(ShopPanel.card_state(o, NOW, amounts, caps, 0), ShopPanel.CardState.FULL, "800 + 300 ponad 1000")
	amounts[0] = 700
	assert_eq(ShopPanel.card_state(o, NOW, amounts, caps, 0), ShopPanel.CardState.READY, "700 + 300 mieści się")
	assert_eq(ShopPanel.button_label(ShopPanel.CardState.READY, o, NOW), "Odbierz", "Odbierz")
	assert_eq(ShopPanel.card_state(o, NOW, amounts, caps, 5), ShopPanel.CardState.BUSY, "czeka na serwer")
	o.ready_at_ms = NOW + 135 * 60000
	assert_eq(ShopPanel.card_state(o, NOW, amounts, caps, 0), ShopPanel.CardState.COOLDOWN, "odnawia się")
	assert_eq(ShopPanel.button_label(ShopPanel.CardState.COOLDOWN, o, NOW), "2 h 15 min", "odliczanie na przycisku")
	assert_eq(ShopPanel.card_state(o, NOW + 135 * 60000, amounts, caps, 0), ShopPanel.CardState.READY, "po odnowieniu")
	var gold := ShopNet.Offer.new()
	gold.resource = EconomyConfig.Res.GOLD
	gold.amount = 100
	assert_eq(ShopPanel.card_state(gold, NOW, [0, 0, 0, 99999] as Array[int], caps, 0), ShopPanel.CardState.READY,
			"złoto bez magazynu")
	return true


func test_panel_layout_fits_screen() -> bool:
	var view := Vector2(320, 180)
	var right := ShopPanel.card_rect(view, 0, 2)
	assert_true(ShopPanel.card_rect(view, 0, 0).position.x >= 12, "karty z dala od lewej krawędzi")
	assert_true(right.end.x <= view.x - 12, "karty z dala od prawej krawędzi")
	var button := ShopPanel.button_rect(right)
	assert_true(button.size.x >= 12 and button.size.y >= 12, "przycisk co najmniej 12×12")
	assert_true(PixelFont.text_width(ShopNet.STORAGE_FULL) <= int(button.size.x) - 2, "Magazyn pełny mieści się")
	assert_true(PixelFont.text_width("29 d 23 h") <= int(button.size.x) - 2, "najdłuższe odliczanie mieści się")
	var shown := ShopPanel.visible_groups(view.y)
	assert_true(shown >= 2, "co najmniej 2 grupy naraz")
	var last := ShopPanel.card_rect(view, shown - 1, 0)
	assert_true(last.end.y <= ShopPanel.list_bottom(view), "ostatnia grupa nad Zamknij")
	assert_eq(ShopPanel.max_first(shown + 2, view.y), 2, "przewijanie o grupy poza ekranem")
	assert_eq(ShopPanel.max_first(1, view.y), 0, "bez przewijania przy jednej grupie")
	return true


func test_panel_claim_flow() -> bool:
	var panel := ShopPanel.new()
	var e := Economy.new(0)
	panel.open(e)
	assert_true(panel.loading, "wczytywanie po otwarciu")
	var groups := ShopNet.parse_catalog([_row(1, 10, 1, EconomyConfig.Res.FOOD, 100)], NOW)
	panel.set_groups(groups, true)
	assert_true(not panel.loading and not panel.offline, "katalog wczytany")
	var asked: Array[int] = []
	panel.claim_requested.connect(func(id: int) -> void: asked.append(id))
	panel.activate(ShopPanel.Target.CARD + 10)
	assert_eq(asked, [10] as Array[int], "Odbierz pyta serwer")
	panel.activate(ShopPanel.Target.CARD + 10)
	assert_eq(asked.size(), 1, "drugie dotknięcie w trakcie nic nie wysyła")
	panel.claim_done({"offer_id": 10, "resource": 2, "amount": 100, "wait_ms": 3600000}, NOW)
	assert_eq(groups[0].offers[0].ready_at_ms, NOW + 3600000, "karta odlicza godzinę")
	assert_eq(panel.status, "Odebrano: +100 Ży", "komunikat odbioru")
	panel.claim_failed("network")
	assert_true(panel.offline, "brak sieci: Brak połączenia")
	panel.set_groups([] as Array[ShopNet.Group], false)
	assert_true(panel.offline, "katalog bez sieci")
	panel.free()
	return true


func test_market_card_has_shop_button() -> bool:
	var buttons := Hud.card_buttons(false, false, false, false, true)
	assert_eq(buttons, [Hud.CardButton.SHOP, Hud.CardButton.CLOSE] as Array[int], "Sklep i Zamknij")
	assert_eq(Hud.card_label(Hud.CardButton.SHOP), "Sklep", "napis")
	var view := Vector2(320, 180)
	var rects := Hud.card_rects(view, false, false, false, false, true)
	var t := Hud.target_at(rects[0].get_center(), view, 300, false, true, false, false, false, false, false, true)
	assert_eq(t, Hud.Target.CARD + Hud.CardButton.SHOP, "dotknięcie Sklepu")
	return true


## Liczby klienta to liczby z migracji (CHECK w bazie).
func test_limits_match_migration() -> bool:
	var sql := FileAccess.get_file_as_string(MIGRATION)
	assert_true(sql.contains("MAX_OFFERS = %d" % ShopNet.MAX_OFFERS), "3 oferty na grupę")
	assert_true(sql.contains("slot between 1 and %d" % ShopNet.MAX_OFFERS), "sloty 1–3")
	assert_true(sql.contains("GOLD_MAX = %d, RES_MAX = %d" % [ShopNet.GOLD_MAX, ShopNet.RES_MAX]), "granice ilości")
	assert_true(sql.contains("then %d else %d end" % [ShopNet.GOLD_MAX, ShopNet.RES_MAX]), "granice w CHECK")
	assert_true(sql.contains("char_length(name) between 1 and %d" % ShopNet.NAME_MAX), "nazwa do 24 znaków")
	assert_true(sql.contains("cooldown_minutes between 60 and 43200"), "odnowienie 1 h – 30 dni")
	assert_eq(ShopNet.MAX_WAIT_MS, 43200 * 60 * 1000, "najdłuższe odliczanie")
	assert_eq(EconomyConfig.Res.GOLD, 3, "złoto to surowiec 3 jak w bazie")
	assert_eq(EconomyConfig.Res.WOOD, 0, "drewno to surowiec 0")
	return true


## Odpowiedzi sklepu w kliencie: katalog, odbiór, błąd serwera i brak sieci (bez sieci, handle_shop).
func test_client_handles_shop_responses() -> bool:
	var net := SupabaseClient.new()
	var loaded: Array = []
	var claimed: Array = []
	net.shop_loaded.connect(func(g: Array[ShopNet.Group], ok: bool) -> void: loaded.append([g.size(), ok]))
	net.shop_claimed.connect(func(c: Dictionary, e: String) -> void: claimed.append([c.get("amount", 0), e]))
	net.handle_shop(SupabaseClient.ShopCall.CATALOG, HTTPRequest.RESULT_SUCCESS, 200,
			JSON.stringify([_row(1, 10, 1, 0, 100)]))
	net.handle_shop(SupabaseClient.ShopCall.CATALOG, HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	assert_eq(loaded, [[1, true], [0, false]], "katalog i brak sieci")
	net.handle_shop(SupabaseClient.ShopCall.CLAIM, HTTPRequest.RESULT_SUCCESS, 200,
			JSON.stringify({"offer_id": 10, "resource": 0, "amount": 100}))
	net.handle_shop(SupabaseClient.ShopCall.CLAIM, HTTPRequest.RESULT_SUCCESS, 409, "{\"error\": \"storage_full\"}")
	net.handle_shop(SupabaseClient.ShopCall.CLAIM, HTTPRequest.RESULT_TIMEOUT, 0, "")
	assert_eq(claimed, [[100, ""], [0, "storage_full"], [0, "network"]], "odbiór, pełny magazyn, brak sieci")
	assert_true(not net.is_shop_pending(), "nic nie czeka")
	assert_true(not net.load_shop(), "bez połączenia sklep się nie wczytuje")
	net.free()
	return true
