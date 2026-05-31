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
	var desired: Vector3 = target_pos + _offset(distance) + Vector3(0, height, 0)
	var t: float = clamp(smoothness * delta, 0.0, 1.0)
	global_position = global_position.lerp(desired, t)
	if _camera:
		_camera.look_at(target_pos + look_offset, Vector3.UP)


# === 公開 API(TouchHUD のカメラボタンから呼ばれる) ===

# dir = +1 で右回り、-1 で左回りに ROTATE_STEP だけ回す(なめらかに追従)
func rotate_view(dir: int) -> void:
	_yaw_target += float(dir) * ROTATE_STEP


# === ロジック層 ===

func _offset(dist: float) -> Vector3:
	return Vector3(
		sin(_yaw) * cos(FIXED_PITCH),
		sin(FIXED_PITCH),
		cos(_yaw) * cos(FIXED_PITCH)
	) * dist
