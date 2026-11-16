class_name BattleRng
extends RefCounted
## Własny generator liczb losowych bitwy (#14): xorshift32 na liczbach całkowitych. Ten sam seed
## daje ten sam ciąg na każdej platformie i w każdej wersji silnika, co jest warunkiem powtórek
## i weryfikacji bitwy na serwerze (notatka Backend PvP).

const MASK := 0xffffffff

var _state := 1


func _init(seed_value: int = 1) -> void:
	_state = seed_value & MASK
	if _state == 0:
		_state = 0x9e3779b9


## Następna liczba 0..2^32-1.
func next_u32() -> int:
	var x := _state
	x ^= (x << 13) & MASK
	x ^= x >> 17
	x ^= (x << 5) & MASK
	_state = x & MASK
	return _state


## Liczba z przedziału lo..hi (włącznie).
func range_int(lo: int, hi: int) -> int:
	if hi <= lo:
		return lo
	return lo + next_u32() % (hi - lo + 1)
