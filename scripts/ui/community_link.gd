class_name CommunityLink
extends RefCounted
## Link do serwera Discord społeczności gry (#360), wspólny dla ekranu tytułowego i Ustawień.
## Otwiera go przeglądarka albo aplikacja Discord telefonu; gra niczego nie wysyła.

const DISCORD_URL := "https://discord.gg/uYcFAhaHq"
const LABEL := "Discord"
const OPENING := "Otwieram Discorda..."
const FAILED := "Nie udało się otworzyć linku"


## Otwiera link w systemie; zwraca komunikat dla gracza.
static func open_discord() -> String:
	return OPENING if OS.shell_open(DISCORD_URL) == OK else FAILED
