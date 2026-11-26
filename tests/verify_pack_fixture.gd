extends SceneTree
## Fikstura dla sprawdzenia packa weryfikacji (#305): zapisuje job (jak z `claim_verification`)
## i wynik oczekiwany policzony ze źródeł przez VerifyJob. Job i zgodność z bitwą atakującego biorą się
## z tych samych helperów co `test_verify_job.gd`, więc pack liczy dokładnie fiksturę z testów.
##   godot --headless --path . --script res://tests/verify_pack_fixture.gd -- --dir build/verifier
## Kod wyjścia 0: pliki `job.json` i `expected.json` zapisane. 1: błąd fikstury albo rozjazd ze źródłem.

const VERIFY_TEST := preload("res://tests/test_verify_job.gd")
const REPLAY := preload("res://tests/test_replay.gd")
const TECHS := ["A7", "A1", "G2"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var dir := ""
	for i in args.size():
		if args[i] == "--dir" and i + 1 < args.size():
			dir = args[i + 1]
	if dir.is_empty():
		printerr("verify_pack_fixture: usage -- --dir <path>")
		quit(1)
		return
	var helper := VERIFY_TEST.new() as TestCase
	var plan := REPLAY._plan(REPLAY._keep_cell())
	var pc := REPLAY._attacker(plan, TECHS)
	if pc == null:
		printerr("verify_pack_fixture: attacker copy failed")
		quit(1)
		return
	var live := pc.create_battle()
	var attacker: Dictionary = helper.call("_run_to_result", live)
	var job: Dictionary = helper.call("_job", plan, TECHS, pc.result_of(live))
	var expected := VerifyJob.verify(job)
	if expected.has(VerifyJob.ERROR_KEY) or expected.get("checksum") != attacker.get("checksum"):
		printerr("verify_pack_fixture: source VerifyJob differs from attacker battle")
		quit(1)
		return
	if not _write(dir.path_join("job.json"), job) or not _write(dir.path_join("expected.json"), expected):
		printerr("verify_pack_fixture: cannot write files")
		quit(1)
		return
	print("verify_pack_fixture: checksum=%d sim_version=%d" % [int(expected["checksum"]),
			int(expected["sim_version"])])
	quit(0)


static func _write(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	return true
