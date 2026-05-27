extends Node3D

# プレイヤーを追従する三人称カメラリグ。
# CameraRig 自体が追従位置に lerp し、子の Camera3D がターゲットを look_at する。

@export var target_path: NodePath
@export var offset: Vector3 = Vector3(0, 5, 8)
@export var smoothness: float = 5.0
@export var look_offset: Vector3 = Vector3(0, 0.8, 0)

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

	# === ロジック層: 追従先を計算 ===
	var desired: Vector3 = _compute_follow_position(_target.global_position, offset)

	# === Godot 操作層: lerp で滑らかに追従 ===
	var t: float = clamp(smoothness * delta, 0.0, 1.0)
	global_position = global_position.lerp(desired, t)

	if _camera:
		_camera.look_at(_target.global_position + look_offset, Vector3.UP)


# === ロジック層 ===

static func _compute_follow_position(target_pos: Vector3, offset: Vector3) -> Vector3:
	return target_pos + offset
