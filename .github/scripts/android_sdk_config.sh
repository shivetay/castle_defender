#!/usr/bin/env bash
# Wskazuje Godotowi Android SDK z runnera GitHuba ($ANDROID_HOME) i JDK ($JAVA_HOME).
set -euo pipefail

test -d "$ANDROID_HOME/platform-tools" && ls "$ANDROID_HOME/build-tools"
mkdir -p ~/.config/godot
cat > ~/.config/godot/editor_settings-4.7.tres <<TRES
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$ANDROID_HOME"
export/android/java_sdk_path = "$JAVA_HOME"
TRES
