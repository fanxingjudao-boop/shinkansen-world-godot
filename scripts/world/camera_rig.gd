extends Node3D

# プレイヤーを追従する三人称カメラ(固定アングル)。
# 以前オービット(指で回す)を試したが画面酔いするとのフィードバックで、
# 固定の見下ろしアングルに戻した。カメラは動かさず、プレイヤーに滑らかについていくだけ。

@export var target_path: NodePath
@export var distance: float = 9.5
@export var height: float = 1.0
@export var smoothness: float = 8.0
@export var look_offset: Vector3 = Vector3(0, 1.0, 0)

# 固定アングル(プレイヤーの斜め後ろ上)
const FIXED_YAW: float = 0.0
const FIXED_PITCH: float = 0.5

var _target: Node3D
var _camera: Camera3D


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
	var target_pos: Vector3 = _target.global_position
	var desired: Vector3 = target_pos + _offset(distance) + Vector3(0, height, 0)
	var t: float = clamp(smoothness * delta, 0.0, 1.0)
	global_position = global_position.lerp(desired, t)
	if _camera:
		_camera.look_at(target_pos + look_offset, Vector3.UP)


# === ロジック層(言語非依存・テスト可能) ===

static func _offset(dist: float) -> Vector3:
	return Vector3(
		sin(FIXED_YAW) * cos(FIXED_PITCH),
		sin(FIXED_PITCH),
		cos(FIXED_YAW) * cos(FIXED_PITCH)
	) * dist
