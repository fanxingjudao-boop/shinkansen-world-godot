extends Node3D

# プレイヤーを追従する三人称カメラ。
# 既定は固定の見下ろしアングル。以前フリーのオービット(指でぐりぐり)は画面酔いする
# とのフィードバックで外したが、改善さんの要望で「ボタンで向きを変える」段階回転を追加。
# ボタン 1 押しで一定角だけ、なめらかに(ゆっくり)回るので酔いにくい。

@export var target_path: NodePath
@export var distance: float = 9.5
@export var height: float = 1.0
@export var smoothness: float = 8.0
@export var look_offset: Vector3 = Vector3(0, 1.0, 0)

# アングル(プレイヤーの斜め後ろ上)
const START_YAW: float = 0.0
const FIXED_PITCH: float = 0.5
const ROTATE_STEP: float = PI / 4.0    # ボタン 1 押しで 45 度
const YAW_SMOOTH: float = 6.0          # 目標角へ寄る速さ(小さいほどゆっくり=酔いにくい)

var _target: Node3D
var _camera: Camera3D
var _yaw: float = START_YAW             # 現在のカメラ方位角
var _yaw_target: float = START_YAW      # 目標方位角(ボタンで増減)
# 月の惑星モードで「上」を球面法線に合わせる(地上/空では UP のまま=従来と完全一致)。
var _surface_up: Vector3 = Vector3.UP
var _surface_fwd: Vector3 = Vector3(0.0, 0.0, 1.0)  # 接平面上の安定した前方(平行移送)


func _ready() -> void:
	if has_node("Camera3D"):
		_camera = $Camera3D
	if not target_path.is_empty():
		var node := get_node_or_null(target_path)
		if node is Node3D:
			_target = node


func _process(delta: float) -> void:
	if _target == null:
		return
	# 目標方位へなめらかに回す(段階回転)
	_yaw = lerp_angle(_yaw, _yaw_target, clamp(YAW_SMOOTH * delta, 0.0, 1.0))
	var target_pos: Vector3 = _target.global_position
	var desired: Vector3 = target_pos + _surface_offset(distance) + _surface_up * height
	var t: float = clamp(smoothness * delta, 0.0, 1.0)
	global_position = global_position.lerp(desired, t)
	if _camera:
		_camera.look_at(target_pos + _surface_up * look_offset.y, _surface_up)


# === 公開 API(TouchHUD のカメラボタンから呼ばれる) ===

# dir = +1(右ボタン)/-1(左ボタン)。改善さんの要望で左右ボタンの回る向きを反転
# (右ボタンで左側が見える=見える範囲が反対)。
func rotate_view(dir: int) -> void:
	_yaw_target -= float(dir) * ROTATE_STEP


# ターゲット位置へカメラを即座にスナップ(月へのワープなど、遠距離テレポート後に
# なめらか追従だと長くパンしてしまうのを防ぐ)。フェードの中で呼ぶ前提。
func snap_to_target() -> void:
	if _target == null:
		return
	_yaw = _yaw_target
	global_position = _target.global_position + _surface_offset(distance) + _surface_up * height
	if _camera:
		_camera.look_at(_target.global_position + _surface_up * look_offset.y, _surface_up)


# 月の惑星モードから「上」を設定(UP に戻すと従来の見下ろしに復帰)。
func set_surface_up(up: Vector3) -> void:
	if up.length() < 0.01:
		_surface_up = Vector3.UP
	else:
		_surface_up = up.normalized()


# === ロジック層 ===

# 「上」が UP のときは従来の _offset と完全一致。惑星モードでは up を球面法線に合わせ、
# 接平面上の前方(平行移送で安定化)+ ボタン方位角で カメラ位置を決める。
func _surface_offset(dist: float) -> Vector3:
	var up := _surface_up
	# 前方を接平面へ射影して保持(向きが飛ばないよう平行移送)
	var f := _surface_fwd - up * _surface_fwd.dot(up)
	if f.length() < 0.001:
		f = Vector3.FORWARD - up * Vector3.FORWARD.dot(up)
	f = f.normalized()
	_surface_fwd = f
	var yawed := f.rotated(up, _yaw)
	return (yawed * cos(FIXED_PITCH) + up * sin(FIXED_PITCH)) * dist
