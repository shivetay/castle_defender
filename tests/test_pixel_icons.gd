extends TestCase
## Ikony surowców: wzory 5×5, kolory tylko z palety, każda ikona inna, ikona na każdy surowiec.


func test_one_icon_per_resource() -> bool:
	assert_eq(PixelIcons.RESOURCES.size(), EconomyConfig.count(), "ikona dla każdego surowca")
	for i in PixelIcons.RESOURCES.size():
		var rows: Array = PixelIcons.RESOURCES[i]
		assert_eq(rows.size(), PixelIcons.SIZE, "ikona %d ma 5 wierszy" % i)
		for row: String in rows:
			assert_eq(row.length(), PixelIcons.SIZE, "ikona %d: wiersz „%s” ma 5 znaków" % [i, row])
			for ch in row:
				assert_true(ch == "." or PixelIcons.LEGEND.has(ch), "ikona %d: znak „%s” jest w legendzie" % [i, ch])
	return true


func test_atlas_uses_palette_and_icons_differ() -> bool:
	var allowed := {}
	for col: Color in Palette.AGE_I + Palette.UI:
		allowed[col.to_rgba32()] = true
	var a := PixelIcons.make_atlas()
	assert_eq(a.get_size(), Vector2i(PixelIcons.SIZE * EconomyConfig.count(), PixelIcons.SIZE), "rozmiar atlasu")
	assert_eq(a.get_data(), PixelIcons.make_atlas().get_data(), "atlas powtarzalny")
	var seen := {}
	for i in EconomyConfig.count():
		var icon := a.get_region(Rect2i(i * PixelIcons.SIZE, 0, PixelIcons.SIZE, PixelIcons.SIZE))
		seen[icon.get_data()] = true
		var filled := 0
		for y in PixelIcons.SIZE:
			for x in PixelIcons.SIZE:
				var col := icon.get_pixel(x, y)
				if col.a > 0.0:
					filled += 1
					assert_true(allowed.has(col.to_rgba32()), "ikona %d: kolor z palety" % i)
		assert_true(filled >= 12, "ikona %d jest czytelna (≥12 pikseli)" % i)
	assert_eq(seen.size(), EconomyConfig.count(), "każda ikona jest inna")
	return true


## Ikony towarów: jedna na towar, wzory 5×5 z legendy, każda inna i czytelna.
func test_one_icon_per_good() -> bool:
	assert_eq(PixelIcons.GOODS.size(), GoodsConfig.count(), "ikona dla każdego towaru")
	var a := PixelIcons.make_atlas(PixelIcons.GOODS)
	var seen := {}
	for i in PixelIcons.GOODS.size():
		var rows: Array = PixelIcons.GOODS[i]
		assert_eq(rows.size(), PixelIcons.SIZE, "towar %d ma 5 wierszy" % i)
		var filled := 0
		for row: String in rows:
			assert_eq(row.length(), PixelIcons.SIZE, "towar %d: wiersz „%s” ma 5 znaków" % [i, row])
			for ch in row:
				assert_true(ch == "." or PixelIcons.LEGEND.has(ch), "towar %d: znak „%s” w legendzie" % [i, ch])
				if ch != ".":
					filled += 1
		assert_true(filled >= 7, "towar %d jest czytelny (≥7 pikseli)" % i)
		seen[a.get_region(Rect2i(i * PixelIcons.SIZE, 0, PixelIcons.SIZE, PixelIcons.SIZE)).get_data()] = true
	assert_eq(seen.size(), GoodsConfig.count(), "każda ikona towaru jest inna")
	return true


## Ikony jednostek (#309): jedna na jednostkę, wzory 5×5 z legendy, kolory z palety, każda inna,
## także Chłop, Topornik, Oszczepnik i Włócznik z tej samej klasy lekkiej.
func test_one_icon_per_unit() -> bool:
	assert_eq(PixelIcons.UNITS.size(), UnitTypes.UNITS.size(), "ikona dla każdej jednostki")
	var allowed := {}
	for col: Color in Palette.AGE_I + Palette.UI:
		allowed[col.to_rgba32()] = true
	var a := PixelIcons.make_atlas(PixelIcons.UNITS)
	assert_eq(a.get_data(), PixelIcons.make_atlas(PixelIcons.UNITS).get_data(), "atlas powtarzalny")
	var seen := {}
	for i in PixelIcons.UNITS.size():
		var rows: Array = PixelIcons.UNITS[i]
		assert_eq(rows.size(), PixelIcons.SIZE, "jednostka %d ma 5 wierszy" % i)
		var filled := 0
		for row: String in rows:
			assert_eq(row.length(), PixelIcons.SIZE, "jednostka %d: wiersz „%s” ma 5 znaków" % [i, row])
			for ch in row:
				assert_true(ch == "." or PixelIcons.LEGEND.has(ch), "jednostka %d: znak „%s” w legendzie" % [i, ch])
				if ch != ".":
					filled += 1
		assert_true(filled >= 7, "jednostka %d jest czytelna (≥7 pikseli)" % i)
		var icon := a.get_region(Rect2i(PixelIcons.unit_region(i)))
		for y in PixelIcons.SIZE:
			for x in PixelIcons.SIZE:
				var col := icon.get_pixel(x, y)
				if col.a > 0.0:
					assert_true(allowed.has(col.to_rgba32()), "jednostka %d: kolor z palety" % i)
		seen[icon.get_data()] = true
	assert_eq(seen.size(), UnitTypes.UNITS.size(), "każda ikona jednostki jest inna")
	assert_true(not PixelIcons.unit_region(-1).has_area(), "brak ikony poza zakresem")
	assert_true(not PixelIcons.unit_region(UnitTypes.UNITS.size()).has_area(), "brak ikony poza zakresem")
	return true
