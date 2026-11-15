# Stack technologiczny

Rekomendacja: **Godot 4 (GDScript)**, eksport na Androida, cała grafika rysowana kodem w niskiej rozdzielczości i skalowana pikselowo.

| Warstwa | Wybór | Dlaczego |
| --- | --- | --- |
| Silnik | Godot 4.x (stabilna wersja) | Darmowy, lekki, natywny 2D, gotowy eksport APK/AAB, brak opłat |
| Język | GDScript | Szybki do nauki, wystarcza dla gry ekonomiczno-obronnej |
| Grafika | `_draw()`, `Image.set_pixel()`, `ImageTexture` generowane przy starcie | Zero zewnętrznych assetów: każdy budynek to funkcja rysująca piksele z palety |
| Pixelart | Viewport 320×180, skalowanie całkowite, filtr `Nearest` | Ostre piksele na każdym ekranie |
| Mapa zamku | `TileMapLayer` z kafelkami generowanymi proceduralnie | Siatka budowy, warstwy |
| Dźwięk | `AudioStreamGenerator` (prosty syntezator) lub cisza w MVP | Też bez assetów |
| Zapis | `FileAccess` + JSON w `user://` | Prosty, offline |
| Testy | Godot Remote Debug przez USB/Wi-Fi | Podgląd na telefonie jednym kliknięciem |

Alternatywa dla TypeScript: Phaser 3 + Capacitor. Odradzana jako główna ścieżka (wolniejszy WebView, dodatkowa warstwa).

Backend do PvP: [[Backend PvP]] (Supabase).

Powiązane: [[Widok zamku]], [[Plan MVP]]
