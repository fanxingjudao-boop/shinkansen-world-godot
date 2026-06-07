extends Node3D

# エントリーポイント。Phase 0 では InputMap の動的設定とログのみ。
# 将来は TitleScreen <-> World の遷移管理ここで。

func _enter_tree() -> void:
	_register_input_actions()

func _ready() -> void:
	_settle_player_on_terrain()
	# 遊び心の小ネタ(PLAYFUL_DETAILS)を Main 直下に生成。
	# Main.tscn を編集せず、起動時に load + add_child で足す(load_steps を増やさない)。
	# この時点で Player / GameState / TouchHUD は すでに居るので、各本体が自分で参照を探す。
	_spawn_extra("HideAndSeek", "res://scripts/world/hide_and_seek.gd")    # B-1 かくれんぼ動物
	_spawn_extra("MagicSteps", "res://scripts/fx/magic_steps.gd")         # B-6 きらきらふみいし
	_spawn_extra("Interactables", "res://scripts/world/interactables.gd") # B-2 たたくと反応するもの
	_spawn_extra("TrainGreeters", "res://scripts/world/train_greeters.gd") # A-5 乗客が手を振る
	_spawn_extra("Instruments", "res://scripts/world/instruments.gd")      # B-5 楽器(押すと音)
	_spawn_extra("RareTrain", "res://scripts/world/rare_train.gd")         # B-7 かくれた でんしゃ(夜)
	_spawn_extra("GingaRailway", "res://scripts/world/ginga_railway.gd")   # 銀河鉄道(星空ワールド)
	_spawn_extra("Minimap", "res://scripts/ui/minimap.gd")                 # ミニマップ(ちず)

# 指定スクリプトの Node3D を Main 直下に 1 つだけ 足す(同名が居れば 何もしない)。
func _spawn_extra(node_name: String, script_path: String) -> void:
	if has_node(node_name):
		return
	var scr := load(script_path)
	if scr == null:
		return
	var node: Node = scr.new()   # Node3D でも CanvasLayer でも可(ミニマップ等)
	node.name = node_name
	add_child(node)

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
