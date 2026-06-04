extends Node3D

# エントリーポイント。Phase 0 では InputMap の動的設定とログのみ。
# 将来は TitleScreen <-> World の遷移管理ここで。

func _enter_tree() -> void:
	_register_input_actions()

func _ready() -> void:
	_settle_player_on_terrain()
	_spawn_hide_and_seek()
	print("[Main] しんかんせんワールド Phase 1 — シーン準備完了")

# かくれんぼ動物(PLAYFUL_DETAILS B-1)を Main 直下に生成。
# Main.tscn を編集せず、起動時に load + add_child で足す(load_steps を増やさない)。
# この時点で Player / GameState / TouchHUD は すでに居るので、本体が自分で参照を探す。
func _spawn_hide_and_seek() -> void:
	if has_node("HideAndSeek"):
		return
	var hs_script := load("res://scripts/world/hide_and_seek.gd")
	if hs_script == null:
		return
	var hs: Node3D = hs_script.new()
	hs.name = "HideAndSeek"
	add_child(hs)

# Player の初期 Y 座標を地形高さに合わせる。
# .tscn 上の Y は適当(空中)で良く、ここで確実に地形に着地させる。
func _settle_player_on_terrain() -> void:
	var player := get_node_or_null("Player") as Node3D
	if player == null:
		return
	var p := player.global_position
	var ground_y := TerrainHeight.compute_height(p.x, p.z)
	player.global_position = Vector3(p.x, ground_y + 1.5, p.z)

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
