extends Node3D

# エントリーポイント。Phase 0 では InputMap の動的設定とログのみ。
# 将来は TitleScreen <-> World の遷移管理ここで。

func _enter_tree() -> void:
	_register_input_actions()

func _ready() -> void:
	print("[Main] しんかんせんワールド Phase 0 — シーン準備完了")

# InputMap を動的に登録。
# project.godot に直接書く代わりにスクリプトで登録することで、
# 改善さんが Godot エディタを触らずにキーバインドを変更できる。
func _register_input_actions() -> void:
	var actions: Dictionary = {
		"move_forward": [KEY_W, KEY_UP],
		"move_back":    [KEY_S, KEY_DOWN],
		"move_left":    [KEY_A, KEY_LEFT],
		"move_right":   [KEY_D, KEY_RIGHT],
		"jump":         [KEY_SPACE],
		"interact":     [KEY_E, KEY_ENTER],
	}
	for action_name in actions.keys():
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name, 0.2)
		for keycode in actions[action_name]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			InputMap.action_add_event(action_name, ev)
