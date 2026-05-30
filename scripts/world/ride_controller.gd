extends Node3D

# 乗車システムの中核。歩行中 / 乗車中の状態を管理し、
# interact(タッチ / E / Enter)のトグルで乗降を制御する。
#
# 設計方針(docs/ARCHITECTURE.md):
# - Autoload を使わず Main 直下のノードに状態を集約。
#   Train / Player / Camera / HUD は「操作される側」に徹する。
# - interact は touch_hud.gd が action_press するのみで誰も消費していない。
#   このノードが唯一の is_action_just_pressed("interact") 消費者になる。
# - 乗車カメラは電車の PathFollow3D(ROTATION_ORIENTED, -Z が進行方向)の子に
#   ローカル固定 transform で置くので、進行方向に追従しつつ一切揺れない。
# - カメラ切替の瞬間はやさしいフェードで隠す(怖くない・酔わない)。
# - 判定ロジックは static な純粋関数に分離(C# 移植配慮)。

# class_name は CLI スキャン前に認識されないため preload で型解決(train_data.gd と同方針)
const TerrainHeight = preload("res://scripts/world/terrain_height.gd")
const Train = preload("res://scripts/entities/train.gd")
const TouchHud = preload("res://scripts/ui/touch_hud.gd")

enum State { WALKING, RIDING }

const RIDE_RANGE: float = 14.0          # この距離内の電車に乗れる(編成全長 ~26m の半分強)
const TOGGLE_DEBOUNCE: float = 0.4      # 乗降トグルのクールダウン(乗った直後の即降車防止)
const FADE_TIME: float = 0.25           # フェード片道の秒数
const LANDING_OFFSET: float = 6.0       # 降車時に線路中心から外側へずらす距離(電車・レールに重ならない)
const PLAYER_GROUND_OFFSET: float = 1.5 # 降車時の地形からの足元オフセット(main.gd と同値)

# 乗車カメラのローカル配置(屋根の上から見下ろす視点・決定済み)
const RIDE_CAM_POS: Vector3 = Vector3(0.0, 6.0, 6.0)     # 車両上 6m・後方 +Z 6m
const RIDE_CAM_PITCH: float = -28.0                       # 進行方向 -Z を見下ろす角度(度)
const RIDE_CAM_FOV: float = 60.0

@export var player_path: NodePath
@export var trains_path: NodePath
@export var camera_rig_path: NodePath
@export var hud_path: NodePath
@export var game_state_path: NodePath

signal boarded(train_display_name: String)
signal alighted()

var _state: int = State.WALKING
var _current_train: Train = null
var _ride_camera: Camera3D = null
var _toggle_cooldown: float = 0.0

var _player: CharacterBody3D
var _trains: Node3D
var _camera_rig: Node3D
var _hud: TouchHud
var _game_state: Node


func _ready() -> void:
	_player = get_node_or_null(player_path) as CharacterBody3D
	_trains = get_node_or_null(trains_path) as Node3D
	_camera_rig = get_node_or_null(camera_rig_path) as Node3D
	_hud = get_node_or_null(hud_path) as TouchHud
	_game_state = get_node_or_null(game_state_path)
	if _player == null:
		push_warning("[RideController] player_path が未解決")
	if _trains == null:
		push_warning("[RideController] trains_path が未解決")


func _process(delta: float) -> void:
	if _toggle_cooldown > 0.0:
		_toggle_cooldown = max(0.0, _toggle_cooldown - delta)

	# 歩行中は最寄りの乗れる電車を案内表示
	if _state == State.WALKING:
		_update_prompt()

	if Input.is_action_just_pressed("interact") and _toggle_cooldown <= 0.0:
		if _state == State.WALKING:
			var train := _find_nearest_ridable()
			if train != null:
				_board(train)
				_toggle_cooldown = TOGGLE_DEBOUNCE
		else:
			_alight()
			_toggle_cooldown = TOGGLE_DEBOUNCE


# === 乗れる電車の検出 ===

func _find_nearest_ridable() -> Train:
	if _player == null or _trains == null:
		return null
	var trains := _trains.get_children()
	var positions: Array = []
	for t in trains:
		positions.append((t as Train).get_ride_anchor_position())
	var idx := _nearest_index(_player.global_position, positions, RIDE_RANGE)
	if idx < 0:
		return null
	return trains[idx] as Train


func _update_prompt() -> void:
	if _hud == null:
		return
	var train := _find_nearest_ridable()
	if train != null:
		_hud.show_board_prompt(train.get_display_name())
	else:
		_hud.hide_board_prompt()


# === 乗車 / 降車 ===

func _board(train: Train) -> void:
	_transition(func() -> void: _do_board(train))


func _do_board(train: Train) -> void:
	_state = State.RIDING
	_current_train = train

	if _player:
		_player.velocity = Vector3.ZERO
		_player.set_physics_process(false)
		_player.visible = false

	var mount := train.get_ride_mount()
	if mount:
		_ride_camera = _make_ride_camera(mount)
		_ride_camera.current = true

	if _hud:
		_hud.hide_board_prompt()
		_hud.set_riding(true)
		_hud.show_notice("%sに のったよ!" % train.get_display_name())

	if _game_state:
		_game_state.add_boarded(train.get_slug())

	boarded.emit(train.get_display_name())


func _alight() -> void:
	_transition(func() -> void: _do_alight())


func _do_alight() -> void:
	var train := _current_train
	if _player and train:
		var anchor: Vector3 = train.get_ride_anchor_position()
		var fwd: Vector3 = train.get_ride_forward()
		fwd.y = 0.0
		if fwd.length() > 0.001:
			fwd = fwd.normalized()
		else:
			fwd = Vector3.FORWARD
		var xz := _compute_landing(anchor, fwd, LANDING_OFFSET)
		var gy := TerrainHeight.compute_height(xz.x, xz.y) + PLAYER_GROUND_OFFSET
		_player.global_position = Vector3(xz.x, gy, xz.y)
		_player.visible = true
		_player.set_physics_process(true)

	# 乗車カメラを破棄し、元の追従カメラに戻す
	if _camera_rig:
		var main_cam := _camera_rig.get_node_or_null("Camera3D") as Camera3D
		if main_cam:
			main_cam.current = true
	if _ride_camera:
		_ride_camera.queue_free()
		_ride_camera = null

	_state = State.WALKING
	_current_train = null

	if _hud:
		_hud.set_riding(false)

	alighted.emit()


# === カメラ生成(Godot 操作層) ===

# 屋根の上から見下ろす乗車カメラを mount(PathFollow3D)の子に生成。
# ローカル固定 transform なので進行方向に追従しつつ揺れない。
func _make_ride_camera(mount: Node3D) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = RIDE_CAM_FOV
	mount.add_child(cam)
	cam.position = RIDE_CAM_POS
	cam.rotation = Vector3(deg_to_rad(RIDE_CAM_PITCH), 0.0, 0.0)
	return cam


# === フェード遷移(Godot 操作層) ===

# やさしいフェードを噛ませ、中点で midpoint を実行してカメラ切替の瞬間を隠す。
func _transition(midpoint: Callable) -> void:
	if _hud == null:
		midpoint.call()
		return
	var tw := create_tween()
	tw.tween_method(Callable(_hud, "set_fade_alpha"), 0.0, 1.0, FADE_TIME)
	tw.tween_callback(midpoint)
	tw.tween_method(Callable(_hud, "set_fade_alpha"), 1.0, 0.0, FADE_TIME)


# === ロジック層(言語非依存・テスト可能) ===

# positions の中で player_pos に最も近く、かつ max_range 以内の index。無ければ -1。
static func _nearest_index(player_pos: Vector3, positions: Array, max_range: float) -> int:
	var best: int = -1
	var best_d: float = max_range * max_range
	for i in range(positions.size()):
		var d: float = player_pos.distance_squared_to(positions[i])
		if d <= best_d:
			best_d = d
			best = i
	return best


# 降車地点(x, z)を計算。線路中心 anchor から進行方向 forward に直交する向きで、
# 楕円中心(原点)から離れる外側へ side_offset ずらす(電車・レール・枕木に埋まらない)。
static func _compute_landing(anchor: Vector3, forward: Vector3, side_offset: float) -> Vector2:
	var perp: Vector3 = forward.cross(Vector3.UP).normalized()
	var perp_xz: Vector2 = Vector2(perp.x, perp.z)
	var anchor_xz: Vector2 = Vector2(anchor.x, anchor.z)
	var outward: Vector3 = perp if perp_xz.dot(anchor_xz) >= 0.0 else -perp
	var landing: Vector3 = anchor + outward * side_offset
	return Vector2(landing.x, landing.z)
