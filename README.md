# Castle Defender

Mobilna gra 2D pixelart (Android) z asynchronicznym PvP. Gracze rozbudowują zamki od wałów ziemnych do twierdzy z końca wojen napoleońskich i atakują zamki innych graczy. Cała grafika jest rysowana kodem, bez zewnętrznych assetów.

**Stack:** Godot 4.7 (GDScript), renderer GL Compatibility, eksport na Androida. Backend PvP (Supabase) dojdzie w etapie 8.

## Stan: etap 1 z planu MVP

Etap 1 to „projekt w Godot 4, viewport 320×180, testowy APK na telefon”. W repozytorium jest:

- `project.godot`: viewport 320×180, okno 1280×720, skalowanie całkowite (`integer`), filtr `Nearest`, przyciąganie do pikseli, orientacja pozioma, emulacja dotyku myszą.
- `scenes/main.tscn` + `scripts/main.gd`: scena testowa z terenem, palisadą i dwiema chatami wygenerowanymi przy starcie (`Image.set_pixel` → `ImageTexture`). Tapnięcie zostawia czerwony znacznik, a w rogu widać rozdzielczość i FPS, żeby sprawdzić dotyk i wydajność na telefonie.
- `scripts/gfx/palette.gd`: paleta epoki I.
- `scripts/gfx/pixel_canvas.gd`: deterministyczny `hash2(x, y)` i pierwsze funkcje rysujące.
- `export_presets.cfg`: preset „Android (debug APK)” (arm64-v8a, `com.shivetay.castledefender`).

## Uruchomienie

1. Zainstaluj [Godot 4.7.2](https://godotengine.org/download) (wersja standardowa, nie .NET).
2. W Godocie: **Import** → wskaż `project.godot`.
3. **F5** uruchamia scenę testową na komputerze.

## Testowy APK na telefon

Jednorazowa konfiguracja:

1. Zainstaluj JDK 17 (np. `brew install --cask zulu@17`) i Android SDK (najprościej przez Android Studio: SDK Platform-Tools, Build-Tools, SDK Platform 34+).
2. W Godocie: **Editor → Manage Export Templates → Download and Install**.
3. **Editor Settings → Export → Android**: ustaw ścieżkę do JDK i Android SDK. Debug keystore Godot tworzy sam przy pierwszym eksporcie.
4. Na telefonie włącz opcje programisty i debugowanie USB.

Potem:

- **Project → Export → Android (debug APK) → Export Project** zapisuje `build/castle_defender.apk`, albo
- ikona Androida w prawym górnym rogu edytora (**Remote Deploy**) instaluje i uruchamia grę na podłączonym telefonie jednym kliknięciem.

## Struktura

```
scenes/          sceny Godota
scripts/         logika gry
scripts/gfx/     rysowanie proceduralne i palety
build/           eksportowane APK (ignorowane przez git)
```

## Następny etap

Etap 2: generator terenu 64×64 kratki (8×8 px) i siatka budowy z kamerą (przeciąganie, zoom 1×/2×/4×).
