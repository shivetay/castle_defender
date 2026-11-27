@tool
extends EditorPlugin
## Wtyczka edytora DunholdPush (#30, ADR 0012): rejestruje eksport, który dokłada AAR wtyczki Androida,
## Firebase Messaging i konfigurację Firebase do eksportu na Androida.

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = preload("res://addons/dunhold_push/export_plugin.gd").new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
