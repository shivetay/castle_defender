class_name TestCase
extends RefCounted
## Baza dla plików tests/test_*.gd. Każda metoda `test_*` musi kończyć się `return true`:
## jeśli test padnie w połowie na błędzie wykonania, call() zwróci null i runner policzy porażkę.

var failures: PackedStringArray = []
var checks := 0


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s: oczekiwano %s, jest %s" % [label, str(expected), str(actual)])


func assert_true(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append("%s: oczekiwano prawdy" % label)
