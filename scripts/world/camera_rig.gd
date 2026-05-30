extends Node3D

# プレイヤーを中心に回り込める三人称オービットカメラ。
# - タッチ: 何もない所をドラッグして見回す(D-pad/ボタンは HUD が吸収)
# - PC: 矢印キー、またはマウス左ドラッグで見回す
# yaw(水平回転)/ pitch(見上げ・見下ろし)を入力で変え、距離は固定。
# 過去フィードバック「カメラを動かせない」への対応。

@export var target_path: NodePath
@export var distance: float = 9.5
@export var height: float = 1.0
@export var smoothness: float = 8.0
@export var look_offset: Vector3 = Vector3(0, 1.0, 0)

const PITCH_MIN: float = 0.05
const PITCH_MAX: float = 1.3
const DRAG_SENS: float = 0.006
const KEY_SPEED: float = 1.8

var _target: Node3D
var _camera: Camera3D
var _yaw: float = 0.0
var _pitch: float = 0.5


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

	# キーボード(矢印)でカメラを回す
	var cam_x: float = Input.get_axis("cam_left", "cam_right")
	var cam_y: float = Input.get_axis("cam_up", "cam_down")
	if cam_x != 0.0:
		_yaw -= cam_x * KEY_SPEED * delta
	if cam_y != 0.0:
		_pitch = clamp(_pitch + cam_y * KEY_SPEED * delta, PITCH_MIN, PITCH_MAX)

	# === ロジック層: 追従先を計算 ===
	var target_pos: Vector3 = _target.global_position
	var desired: Vector3 = target_pos + _orbit_offset(_yaw, _pitch, distance) + Vector3(0, height, 0)

	# === Godot 操作層: lerp で滑らかに追従 ===
	var t: float = clamp(smoothness * delta, 0.0, 1.0)
	global_position = global_position.lerp(desired, t)

	if _camera:
		_camera.look_at(target_pos + look_offset, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		_apply_drag(event.relative)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_apply_drag(event.relative)


func _apply_drag(rel: Vector2) -> void:
	_yaw -= rel.x * DRAG_SENS
	_pitch = clamp(_pitch - rel.y * DRAG_SENS, PITCH_MIN, PITCH_MAX)


# === ロジック層(言語非依存・テスト可能) ===

# yaw / pitch / 距離 から、ターゲットからのカメラオフセットを返す。
# yaw=0 で +Z(プレイヤーの背後)、pitch で上下。
static func _orbit_offset(yaw: float, pitch: float, dist: float) -> Vector3:
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * dist
