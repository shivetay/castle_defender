class_name Ages
extends RefCounted
## Epoki i rok na pasku. Rok nie płynie sam: wynika z poziomu Dworu, czyli z rozwoju zamku.
## Epoka I zaczyna się w roku 550. Kolejne epoki dojdą z przejściem I → II (#34).

const NAMES: Array[String] = ["Epoka I"]
## Rok dla poziomów Dworu 1–5 w każdej epoce.
const YEARS: Array = [[550, 600, 650, 700, 750]]


static func year(age: int, manor_level: int) -> int:
	var years: Array = YEARS[clampi(age, 0, YEARS.size() - 1)]
	return years[clampi(manor_level, 1, years.size()) - 1]


## Napis na pasku, np. „Epoka I · 550 r.”.
static func label(age: int, manor_level: int) -> String:
	return "%s · %d r." % [NAMES[clampi(age, 0, NAMES.size() - 1)], year(age, manor_level)]
