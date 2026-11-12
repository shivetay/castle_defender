extends SceneTree
## Uruchamia wszystkie tests/test_*.gd (klasy dziedziczące po TestCase) i kończy się kodem 1 przy porażce.
##   godot --headless --path . --script res://tests/run_tests.gd
## Opcjonalnie tylko wybrane pliki: ... --script res://tests/run_tests.gd -- test_pixel_canvas


func _initialize() -> void:
	var only := OS.get_cmdline_user_args()
	var passed := 0
	var failed := 0
	for file: String in DirAccess.get_files_at("res://tests"):
		if not (file.begins_with("test_") and file.ends_with(".gd")) or file == "test_case.gd":
			continue
		if not only.is_empty() and not only.has(file.get_basename()):
			continue
		var script := load("res://tests/" + file) as GDScript
		if script == null or not script.can_instantiate():
			failed += 1
			printerr("FAIL %s: skrypt się nie kompiluje" % file)
			continue
		for method: Dictionary in script.get_script_method_list():
			var name: String = method["name"]
			if not name.begins_with("test_"):
				continue
			var case := script.new() as TestCase
			var finished: Variant = case.call(name)
			if finished != true:
				case.failures.append("test nie dobiegł końca (błąd wykonania albo brak `return true`)")
			if case.failures.is_empty():
				passed += 1
				print("  ok   %s.%s" % [file.get_basename(), name])
			else:
				failed += 1
				for f: String in case.failures:
					printerr("FAIL %s.%s: %s" % [file.get_basename(), name, f])
	print("Testy: %d zaliczone, %d nieudane" % [passed, failed])
	if passed + failed == 0:
		printerr("Nie znaleziono żadnych testów")
		quit(1)
		return
	quit(1 if failed > 0 else 0)
