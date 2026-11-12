#!/usr/bin/env bash
# Instaluje Godota (Linux x86_64) do $GODOT_DIR i linkuje go jako `godot` w $BIN_DIR.
# Z argumentem --templates instaluje też szablony eksportu (potrzebne do APK, ok. 1,3 GB).
# Sumy SHA-512 są przypięte: przy zmianie wersji zaktualizuj je z SHA512-SUMS.txt z wydania Godota.
set -euo pipefail

VERSION="4.7.2"
EDITOR_SHA512="9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65"
TEMPLATES_SHA512="ca4d71c4d7b81dfc15d1a98baa07534aa95b03fdda78a0075b06672e1648d2e5f40980c9adc28d23e1b92e732ee7bf3461997aa804af74ec2fcd7a93ccb84079"

BASE="https://github.com/godotengine/godot/releases/download/${VERSION}-stable"
GODOT_DIR="${GODOT_DIR:-$HOME/godot}"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
EDITOR_ZIP="Godot_v${VERSION}-stable_linux.x86_64.zip"
TEMPLATES_TPZ="Godot_v${VERSION}-stable_export_templates.tpz"

mkdir -p "$GODOT_DIR" "$BIN_DIR"
cd "$GODOT_DIR"

fetch() {  # fetch <plik> <sha512>; pobiera tylko, jeśli nie ma go w cache albo suma się nie zgadza
	local file="$1" sum="$2"
	if [[ -f "$file" ]] && echo "$sum  $file" | sha512sum --check --status; then
		echo "z cache: $file"
		return
	fi
	curl -fsSL --retry 3 -o "$file" "$BASE/$file"
	echo "$sum  $file" | sha512sum --check
}

fetch "$EDITOR_ZIP" "$EDITOR_SHA512"
unzip -oq "$EDITOR_ZIP"
ln -sf "$GODOT_DIR/Godot_v${VERSION}-stable_linux.x86_64" "$BIN_DIR/godot"

if [[ "${1:-}" == "--templates" ]]; then
	fetch "$TEMPLATES_TPZ" "$TEMPLATES_SHA512"
	dest="$HOME/.local/share/godot/export_templates/${VERSION}.stable"
	mkdir -p "$dest"
	unzip -oq "$TEMPLATES_TPZ" -d "$GODOT_DIR/tpl"
	cp -r "$GODOT_DIR/tpl/templates/." "$dest/"
	rm -rf "$GODOT_DIR/tpl"
	echo "szablony eksportu: $dest"
fi

"$BIN_DIR/godot" --headless --version
