class_name PlayerProfile
extends RefCounted
## Profil gracza w user://player.json, osobno od zapisu zamku. Trzyma seed gracza: losuje się raz,
## przy pierwszym uruchomieniu, i zostaje na stałe, także gdy zapis zamku zniknie albo gracz zacznie
## od nowa. Z seeda gracza wynika seed zamku (WorldSeed.first_playable), więc ten sam gracz zawsze
## dostaje ten sam teren. Od etapu 8 seed przejdzie na konto w Supabase.
## Od #228 profil trzyma też tożsamość z onboardingu: imię gracza, nazwę zamku i władcę
## (domyślny bez premii, Rulers). Zacznij od nowa jej nie kasuje, bo to dalej ten sam gracz.

const PATH := "user://player.json"
## Wersja 2 dodała tożsamość (#228); profil w wersji 1 ma tylko seed i przechodzi przez onboarding.
const VERSION := 2

## Długość imienia gracza i nazwy zamku po przycięciu spacji. Imię mieści się w `players.nickname`
## (1–20 znaków), a oba w polu na 320 px fontem 8 px (najszerszy znak ma 5 px + 1 px odstępu).
const NAME_MIN := 3
const NAME_MAX := 12
const CASTLE_MIN := 3
const CASTLE_MAX := 16

## Wynik sprawdzenia nazwy.
enum NameError { OK, TOO_SHORT, TOO_LONG, BAD_CHAR }
const NAME_ERRORS := {
	NameError.TOO_SHORT: "za krótkie (min. %d znaki)",
	NameError.TOO_LONG: "za długie (maks. %d znaków)",
	NameError.BAD_CHAR: "tylko litery, cyfry, spacja i -",
}

## Tożsamość gracza z onboardingu.
class Identity:
	extends RefCounted
	var player_name := ""
	var castle_name := ""
	var ruler := Rulers.DEFAULT

	## Czy imię i nazwa przechodzą walidację, a władca jest znany.
	func is_complete() -> bool:
		return PlayerProfile.check_name(player_name, PlayerProfile.NAME_MIN, PlayerProfile.NAME_MAX) \
				== PlayerProfile.NameError.OK \
				and PlayerProfile.check_name(castle_name, PlayerProfile.CASTLE_MIN, PlayerProfile.CASTLE_MAX) \
				== PlayerProfile.NameError.OK \
				and Rulers.is_known(ruler)

	func to_dict() -> Dictionary:
		return {"player_name": player_name, "castle_name": castle_name, "ruler": ruler}

	## Tożsamość ze słownika (profil albo w przyszłości wiersz z serwera, #23); nazwy są czyszczone,
	## a nieznany władca wraca do domyślnego.
	static func from_dict(d: Dictionary) -> Identity:
		var out := Identity.new()
		out.player_name = PlayerProfile.clean_name(str(d.get("player_name", "")))
		out.castle_name = PlayerProfile.clean_name(str(d.get("castle_name", "")))
		var ruler_id := str(d.get("ruler", Rulers.DEFAULT))
		out.ruler = ruler_id if Rulers.is_known(ruler_id) else Rulers.DEFAULT
		return out


## Nazwa bez spacji na brzegach i z pojedynczymi spacjami w środku.
static func clean_name(text: String) -> String:
	return " ".join(text.strip_edges().split(" ", false))


## Czy znak można wpisać w imię albo nazwę: litera, którą zna PixelFont (także polska), cyfra,
## spacja albo łącznik.
static func is_allowed_char(ch: String) -> bool:
	if ch == " " or ch == "-":
		return true
	var up := ch.to_upper()
	if PixelFont.ACCENTED.has(up):
		return true
	# litera (ma małą wersję, np. Ł) albo cyfra; znaki interpunkcyjne fontu odpadają
	return PixelFont.GLYPHS.has(up) and (up.to_lower() != up or up.is_valid_int())


## Sprawdza oczyszczoną nazwę: długość od `min_len` do `max_len` i dozwolone znaki.
static func check_name(text: String, min_len: int, max_len: int) -> int:
	var cleaned := clean_name(text)
	for ch in cleaned:
		if not is_allowed_char(ch):
			return NameError.BAD_CHAR
	if cleaned.length() < min_len:
		return NameError.TOO_SHORT
	if cleaned.length() > max_len:
		return NameError.TOO_LONG
	return NameError.OK


## Komunikat błędu nazwy dla UI, np. „Imię: za krótkie (min. 3 znaki)”.
static func error_text(label: String, err: int, min_len: int, max_len: int) -> String:
	if err == NameError.OK:
		return ""
	var text := str(NAME_ERRORS[err])
	if err == NameError.TOO_SHORT:
		text = text % min_len
	elif err == NameError.TOO_LONG:
		text = text % max_len
	return "%s: %s" % [label, text]


## Cały profil z pliku (pusty słownik, gdy go nie ma).
static func read(path: String) -> Dictionary:
	return SaveGame.read(path)


## Zapisuje profil z bieżącą wersją, zachowując pola, których zapis nie zmienia.
static func _write(path: String, changes: Dictionary) -> Error:
	var d := read(path)
	d.merge(changes, true)
	d["version"] = VERSION
	return SaveGame.write(path, d)


## Seed gracza z profilu albo 0, gdy profilu nie ma lub jest niepoprawny.
static func read_seed(path: String) -> int:
	var d := read(path)
	var value := int(d.get("player_seed", 0))
	return value if value > 0 and value <= WorldSeed.MAX_SEED else 0


static func write_seed(path: String, player_seed: int) -> Error:
	return _write(path, {"player_seed": player_seed})


## Seed gracza: z profilu, a gdy go nie ma, `fallback` (np. seed ze starego zapisu zamku) albo
## nowy losowy. Nowy seed od razu trafia do profilu.
static func ensure_seed(path: String, fallback: int = 0) -> int:
	var value := read_seed(path)
	if value == 0:
		value = fallback if fallback > 0 and fallback <= WorldSeed.MAX_SEED else WorldSeed.random_seed()
		write_seed(path, value)
	return value


## Tożsamość z profilu albo null, gdy jej nie ma albo jest niepełna (wtedy gra pokazuje onboarding).
static func read_identity(path: String) -> Identity:
	var d := read(path)
	var raw: Variant = d.get("identity", null)
	if not raw is Dictionary:
		return null
	var id := Identity.from_dict(raw as Dictionary)
	return id if id.is_complete() else null


static func has_identity(path: String) -> bool:
	return read_identity(path) != null


## Zapisuje tożsamość (po czyszczeniu nazw). ERR_INVALID_DATA, gdy nie przechodzi walidacji.
static func write_identity(path: String, id: Identity) -> Error:
	var clean := Identity.from_dict(id.to_dict())
	if not clean.is_complete():
		return ERR_INVALID_DATA
	return _write(path, {"identity": clean.to_dict()})


## Tożsamość na serwerze (#23): `nickname` to kolumna `players.nickname`, a cała tożsamość jedzie też
## w `castles.data.profile` (`CastleSync.castle_data`), żeby wróciła po reinstalacji. Żadnych innych
## danych o graczu.
static func sync_fields(id: Identity) -> Dictionary:
	return {"nickname": id.player_name, "castle_name": id.castle_name, "ruler": id.ruler}


## Stan mini-samouczka (#251, TutorialHints.State): czy gracz go wyłączył albo już ukończył. Zostaje
## w profilu, więc Zacznij od nowa nie pokazuje samouczka komuś, kto już przeszedł 5 fal. Bez pola
## (stary profil, pierwsze uruchomienie): jeszcze nie zapytano.
static func read_tutorial(path: String) -> int:
	return TutorialHints.state_from(str(read(path).get("tutorial", "")))


static func write_tutorial(path: String, state: int) -> Error:
	return _write(path, {"tutorial": TutorialHints.state_name(state)})


## Koniec ostatnio obejrzanej obrony (#328, unix s): obrony po nim są nowe (okienko po połączeniu
## i kropka nad Obroną). Tylko na telefonie, bez serwera; bez pola wszystkie obrony są nowe.
static func read_seen_defense(path: String) -> int:
	var v: Variant = read(path).get("seen_defense_s", 0)
	return maxi(0, int(v)) if v is int or v is float else 0


static func write_seen_defense(path: String, at_s: int) -> Error:
	return _write(path, {"seen_defense_s": maxi(0, at_s)})


## Zgoda na powiadomienia z okienka w grze (#30, PushNotifications.Consent) i czas ostatniej odmowy
## (unix s). Tylko na telefonie. Bez pól: jeszcze nie pytano.
static func read_push_consent(path: String) -> int:
	return PushNotifications.consent_from(str(read(path).get("push_consent", "")))


static func read_push_declined(path: String) -> int:
	var v: Variant = read(path).get("push_declined_s", 0)
	return maxi(0, int(v)) if v is int or v is float else 0


## Zapis zgody; przy odmowie także jej czas (po 7 dniach gra pyta znowu).
static func write_push_consent(path: String, consent: int, now_s: int) -> Error:
	var changes := {"push_consent": PushNotifications.consent_name(consent)}
	if consent == PushNotifications.Consent.DECLINED:
		changes["push_declined_s"] = maxi(0, now_s)
	return _write(path, changes)


## Przełączniki powiadomień w Ustawieniach (#30): „Ataki” i „Koniec budowy”, domyślnie włączone.
static func read_push_attacks(path: String) -> bool:
	return read(path).get("push_attacks", true) != false


static func read_push_build(path: String) -> bool:
	return read(path).get("push_build", true) != false


static func write_push_switches(path: String, attacks: bool, build: bool) -> Error:
	return _write(path, {"push_attacks": attacks, "push_build": build})


## Usuwa profil (w testach).
static func delete(path: String) -> void:
	SaveGame.delete(path)
