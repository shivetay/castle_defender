extends TestCase
## Determinizm grafiki: ten sam seed musi dawać te same piksele (na tym opiera się asynchroniczne PvP).


func test_hash2_is_deterministic_and_non_negative() -> bool:
	for y in range(-20, 20):
		for x in range(-20, 20):
			var h := PixelCanvas.hash2(x, y, 5)
			assert_eq(h, PixelCanvas.hash2(x, y, 5), "hash2(%d,%d) powtarzalny" % [x, y])
			if h < 0:
				assert_true(false, "hash2(%d,%d) >= 0" % [x, y])
	return true


func test_hash2_depends_on_seed() -> bool:
	var same := 0
	for i in 100:
		if PixelCanvas.hash2(i, i * 3, 1) == PixelCanvas.hash2(i, i * 3, 2):
			same += 1
	assert_true(same < 5, "różne seedy dają różne hashe (zgodnych: %d/100)" % same)
	return true


func test_terrain_same_seed_same_pixels() -> bool:
	var a := PixelCanvas.make_terrain(Vector2i(64, 48), 7)
	var b := PixelCanvas.make_terrain(Vector2i(64, 48), 7)
	assert_eq(a.get_data(), b.get_data(), "teren z seedem 7 identyczny")
	var c := PixelCanvas.make_terrain(Vector2i(64, 48), 8)
	assert_true(a.get_data() != c.get_data(), "inny seed daje inny teren")
	return true


func test_terrain_uses_only_palette() -> bool:
	var img := PixelCanvas.make_terrain(Vector2i(32, 32), 3)
	var allowed := {}
	for col: Color in Palette.GRASS:
		allowed[col.to_rgba32()] = true
	var outside := 0
	for y in img.get_height():
		for x in img.get_width():
			if not allowed.has(img.get_pixel(x, y).to_rgba32()):
				outside += 1
	assert_eq(outside, 0, "piksele spoza palety GRASS")
	return true
