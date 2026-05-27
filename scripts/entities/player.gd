extends CharacterBody3D

# プレイヤー操作スクリプト。
# 設計方針: ロジック層(pure 関数)と Godot 操作層を明確に分離し、
# 将来 C# 移植時のコストを抑える(docs/ARCHITECTURE.md 参照)。

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 6.5
const ROTATION_SPEED: float = 12.0

signal jumped

func _ready() -> void:
	if not is_in_group("player"):
		add_to_group("player")

func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)

	# === ロジック層: 水平速度を pure 関数で計算 ===
	var horiz: Vector3 = _compute_horizontal_velocity(input_dir, SPEED)
	velocity.x = horiz.x
	velocity.z = horiz.z

	# === Godot 操作層 ===
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		jumped.emit()

	move_and_slide()

	# 進行方向に体を向ける(滑らかに)
	if input_dir.length() > 0.01:
		var target_yaw: float = _compute_yaw(input_dir)
		rotation.y = lerp_angle(rotation.y, target_yaw, ROTATION_SPEED * delta)


# === ロジック層(言語非依存・テスト可能) ===

static func _compute_horizontal_velocity(input_dir: Vector2, speed: float) -> Vector3:
	# input_dir: x=左右, y=前後(Godot 標準: -Y が前方)
	var dir: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	return dir * speed

static func _compute_yaw(input_dir: Vector2) -> float:
	# Godot は -Z 方向が forward なので、input.y=-1(前)で yaw=0(画面奥向き)
	return atan2(-input_dir.x, -input_dir.y)
