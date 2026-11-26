class_name VerifyMain
extends SceneTree
## Punkt wejścia workera Godot headless (#284 / #303): czyta `--job`, woła VerifyJob.verify, zapisuje
## `--out`, kończy 0 (sukces) albo 1 (błąd / złe argumenty). Bez sieci — DB tylko przez wrapper Python.
##
##   godot --headless --path . --script res://server/verify_main.gd -- --job in.json --out out.json
##   godot --headless --main-pack packs/verify_<sim_version>.pck -- --job in.json --out out.json
##   godot --headless --main-pack packs/verify_<sim_version>.pck -- --check   (wypisuje sim_version packa)
## W packu (preset „Verifier”, cecha `verifier`) to główna pętla gry: `run/main_loop_type.verifier`
## w project.godot, a `server/verify_main.tscn` to pusta scena główna, bo bez niej Godot nie wystartuje.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--check"):
		print("sim_version=%d" % VerifyJob.project_sim_version())
		quit(0)
		return
	var job_path := _arg_value(args, "--job")
	var out_path := _arg_value(args, "--out")
	if job_path.is_empty() or out_path.is_empty():
		printerr("verify_main: usage -- --job <path> --out <path>")
		quit(1)
		return
	var job := _read_json_object(job_path)
	if job.is_empty():
		printerr("verify_main: invalid job file")
		quit(1)
		return
	var result := VerifyJob.verify(job)
	if not _write_json(out_path, result):
		printerr("verify_main: cannot write out file")
		quit(1)
		return
	if result.has(VerifyJob.ERROR_KEY):
		printerr("verify_main: %s" % str(result[VerifyJob.ERROR_KEY]))
		quit(1)
		return
	quit(0)


static func _arg_value(args: PackedStringArray, flag: String) -> String:
	for i in args.size():
		if args[i] == flag and i + 1 < args.size():
			return args[i + 1]
	return ""


static func _read_json_object(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed as Dictionary if parsed is Dictionary else {}


static func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true
