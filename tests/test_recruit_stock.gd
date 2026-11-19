extends TestCase
## Zapas zbrojowni na ekranie Wojsko: towary używane przez jednostki (broń, zbroja…)
## z ilościami z goods.amounts; bez osobnego UI magazynu.

const G := GoodsConfig.Good


## Lista obejmuje tylko towary z kosztów jednostek, w kolejności GoodsConfig; półprodukty poza
## kosztami (np. Len) nie wchodzą.
func test_unit_goods_are_equipment_from_unit_costs() -> bool:
	var list := RecruitPanel.unit_goods()
	assert_true(list.has(G.BOW) and list.has(G.ARROW) and list.has(G.LEATHER_ARMOR),
			"łuk, strzały i zbroja skórzana z kosztów")
	assert_true(list.has(G.STONE_AXE) and list.has(G.HORSE) and list.has(G.SADDLE),
			"topór, koń i siodło")
	assert_true(not list.has(G.FLAX) and not list.has(G.LEATHER) and not list.has(G.BOWSTRING),
			"półprodukty poza kosztami jednostek nie wchodzą")
	assert_true(not list.has(G.HARNESS), "uprząż nie jest kosztem żadnej jednostki MVP")
	var prev := -1
	for good in list:
		assert_true(good > prev, "kolejność GoodsConfig")
		prev = good
	return true


## Pusta zbrojownia: podpowiedź; z zapasem: ilości i nazwy; Len nie pojawia się mimo ilości.
func test_stock_texts_from_goods_amounts() -> bool:
	var goods := Goods.new()
	assert_eq(RecruitPanel.stock_texts(goods).size(), 0, "pusto")
	assert_true(RecruitPanel.stock_lines(goods, 240, 3)[0][0].begins_with("Pusto."),
			"podpowiedź bez zapasu")
	goods.amounts[G.BOW] = 2
	goods.amounts[G.ARROW] = 40
	goods.amounts[G.FLAX] = 99
	goods.amounts[G.LEATHER] = 5
	var texts := RecruitPanel.stock_texts(goods)
	assert_eq(texts.size(), 2, "tylko towary jednostkowe z ilością > 0")
	assert_eq(texts[0], "2 Łuk", "łuk pierwszy (kolejność Good)")
	assert_eq(texts[1], "40 Strzały", "strzały")
	var joined := ", ".join(texts)
	assert_true(not joined.contains("Len") and not joined.contains("Wyprawiona"),
			"półprodukty pominięte: %s" % joined)
	return true


## Linie zapasu mieszczą się w szczegółach Wojsko (jak produkcja cywilna).
func test_stock_lines_fit_detail_room() -> bool:
	var goods := Goods.new()
	for good in RecruitPanel.unit_goods():
		goods.amounts[good] = 3 + good
	for width: int in [200, 240, 296]:
		var lines := RecruitPanel.stock_lines(goods, width, RecruitPanel.DETAIL_LINES - 1)
		assert_true(lines.size() <= RecruitPanel.DETAIL_LINES - 1, "najwyżej 3 linie przy %d px" % width)
		assert_true(not lines.is_empty(), "jest treść")
		for l: Array in lines:
			assert_true(PixelFont.text_width(l[0] as String) <= width, "„%s” w %d px" % [l[0], width])
	return true
