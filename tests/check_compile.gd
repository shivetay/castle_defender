extends SceneTree
## Sprawdza, czy każdy skrypt .gd w projekcie się kompiluje (z zarejestrowanymi class_name).
## Uruchomienie (po `godot --headless --path . --import`):
##   godot --headless --path . --script res://tests/check_compile.gd
## Kod wyjścia 0: wszystko się kompiluje. 1: co najmniej jeden plik BROKEN (błąd parsera jest wyżej w logu).


func _initialize() -> void:
	var own: String = get_script().resource_path
	var total := 0
	var broken := 0
	for path: String in _gd_files("res://"):
		if path == own:
			continue
		total += 1
		var script := load(path) as Script
		if script == null or not script.can_instantiate():
			broken += 1
			printerr("BROKEN ", path)
	print("Skrypty: %d, błędne: %d" % [total, broken])
	quit(1 if broken > 0 else 0)


func _gd_files(dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file: String in DirAccess.get_files_at(dir):
		if file.get_extension() == "gd":
			out.append(dir.path_join(file))
	for sub: String in DirAccess.get_directories_at(dir):
		if not sub.begins_with("."):  # pomija .godot/, .claude/ itp.
			out.append_array(_gd_files(dir.path_join(sub)))
	return out
