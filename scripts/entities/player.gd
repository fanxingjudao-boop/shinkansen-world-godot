extends CharacterBody3D

# プレイヤー操作スクリプト。
# 見た目は 3 頭身のかわいい「しんかんせんの うんてんしさん」をスクリプトで生成。
# 移動中は腕・足を振り、体が上下する歩行アニメ。
# ロジック層(pure 関数)と Godot 操作層を分離(docs/ARCHITECTURE.md、C# 移植配慮)。

const RIM_SHADER = preload("res://assets/shaders/rim.gdshader")

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 6.5
const ROTATION_SPEED: float = 12.0
const WALK_FREQ: float = 11.0
const WALK_SWING: float = 0.6

# 配色(子供と大人が一緒に見てかわいい)
const SKIN: Color = Color(1.0, 0.85, 0.72)
const HAIR: Color = Color(0.45, 0.3, 0.18)
const HAT: Color = Color(0.16, 0.41, 0.79)
const HAT_DARK: Color = Color(0.1, 0.28, 0.6)
const SHIRT: Color = Color(1.0, 0.85, 0.4)
const PANTS: Color = Color(0.42, 0.55, 0.85)
const SHOE: Color = Color(0.45, 0.3, 0.2)
const CHEEK: Color = Color(1.0, 0.6, 0.7)
const NOSE: Color = Color(1.0, 0.78, 0.68)
const EMBLEM: Color = Color(1.0, 0.85, 0.3)
const EYE_W: Color = Color(1.0, 1.0, 1.0)
const EYE_B: Color = Color(0.12, 0.1, 0.12)

signal jumped

var _visual: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _walk_phase: float = 0.0


func _ready() -> void:
	if not is_in_group("player"):
		add_to_group("player")
	_build_character()


func _physics_process(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)

	# === ロジック層 ===
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

	if input_dir.length() > 0.01:
		var target_yaw: float = _compute_yaw(input_dir)
		rotation.y = lerp_angle(rotation.y, target_yaw, ROTATION_SPEED * delta)

	_animate_walk(delta, input_dir.length() > 0.01)


# === 歩行アニメ ===

func _animate_walk(delta: float, moving: bool) -> void:
	if _visual == null:
		return
	if moving:
		_walk_phase += delta * WALK_FREQ
		var s: float = sin(_walk_phase) * WALK_SWING
		_arm_l.rotation.x = s
		_arm_r.rotation.x = -s
		_leg_l.rotation.x = -s
		_leg_r.rotation.x = s
		_visual.position.y = abs(sin(_walk_phase * 2.0)) * 0.06
	else:
		var t: float = clamp(10.0 * delta, 0.0, 1.0)
		_arm_l.rotation.x = lerp_angle(_arm_l.rotation.x, 0.0, t)
		_arm_r.rotation.x = lerp_angle(_arm_r.rotation.x, 0.0, t)
		_leg_l.rotation.x = lerp_angle(_leg_l.rotation.x, 0.0, t)
		_leg_r.rotation.x = lerp_angle(_leg_r.rotation.x, 0.0, t)
		_visual.position.y = lerp(_visual.position.y, 0.0, t)


# === ロジック層(言語非依存・テスト可能) ===

static func _compute_horizontal_velocity(input_dir: Vector2, speed: float) -> Vector3:
	var dir: Vector3 = Vector3(input_dir.x, 0.0, input_dir.y)
	if dir.length() > 1.0:
		dir = dir.normalized()
	return dir * speed

static func _compute_yaw(input_dir: Vector2) -> float:
	return atan2(-input_dir.x, -input_dir.y)


# === 見た目構築(Godot 操作層) ===

func _build_character() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	# 足(青ズボン+靴)
	_leg_l = _make_limb(Vector3(-0.15, 0.45, 0.0), 0.42, 0.11, PANTS, true)
	_leg_r = _make_limb(Vector3(0.15, 0.45, 0.0), 0.42, 0.11, PANTS, true)

	# 体(黄色いシャツ)
	var body := CapsuleMesh.new()
	body.radius = 0.26
	body.height = 0.72
	_add_part(body, Vector3(0, 0.76, 0), SHIRT, _visual)
	# えり / ボタン
	var collar := CylinderMesh.new()
	collar.top_radius = 0.2
	collar.bottom_radius = 0.27
	collar.height = 0.12
	_add_part(collar, Vector3(0, 1.06, 0), HAT, _visual)

	# 腕(肌色、肩を支点に振る)
	_arm_l = _make_limb(Vector3(-0.32, 1.02, 0.0), 0.4, 0.09, SKIN, false)
	_arm_r = _make_limb(Vector3(0.32, 1.02, 0.0), 0.4, 0.09, SKIN, false)

	_build_head()


# 手足: 支点 Node3D を pos に置き、その子にメッシュを下方向へ伸ばす(支点で回転=振り)
func _make_limb(pos: Vector3, length: float, radius: float, color: Color, is_leg: bool) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	_visual.add_child(pivot)
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length
	_add_part(cap, Vector3(0, -length * 0.5, 0), color, pivot)
	if is_leg:
		var shoe := BoxMesh.new()
		shoe.size = Vector3(0.2, 0.13, 0.3)
		_add_part(shoe, Vector3(0, -length - 0.02, -0.06), SHOE, pivot)
	else:
		# 手(まるい)
		var hand := SphereMesh.new()
		hand.radius = 0.11
		hand.height = 0.22
		_add_part(hand, Vector3(0, -length - 0.02, 0), SKIN, pivot)
	return pivot


func _build_head() -> void:
	var head := Node3D.new()
	head.position = Vector3(0, 1.5, 0)  # 頭の中心
	_visual.add_child(head)

	# 顔(大きい丸い頭=3頭身でかわいく)
	var face := SphereMesh.new()
	face.radius = 0.42
	face.height = 0.84
	_add_part(face, Vector3.ZERO, SKIN, head)

	# 後ろ髪(後頭部に少し)
	var hair := SphereMesh.new()
	hair.radius = 0.4
	hair.height = 0.8
	_add_part(hair, Vector3(0, 0.06, 0.14), HAIR, head).scale = Vector3(1.02, 0.9, 0.85)

	# 目(白目+黒目+ハイライト)。-Z が顔の正面
	for sx in [-1.0, 1.0]:
		var w := SphereMesh.new()
		w.radius = 0.11
		w.height = 0.22
		var wmi := _add_unshaded(w, Vector3(sx * 0.16, 0.05, -0.36), EYE_W, head)
		wmi.scale = Vector3(0.8, 1.1, 0.6)
		var b := SphereMesh.new()
		b.radius = 0.065
		b.height = 0.13
		_add_unshaded(b, Vector3(sx * 0.16, 0.04, -0.44), EYE_B, head)
		var hi := SphereMesh.new()
		hi.radius = 0.025
		hi.height = 0.05
		_add_unshaded(hi, Vector3(sx * 0.18, 0.09, -0.48), EYE_W, head)

	# ほっぺ(ピンク)
	for sx in [-1.0, 1.0]:
		var c := SphereMesh.new()
		c.radius = 0.09
		c.height = 0.18
		var cmi := _add_unshaded(c, Vector3(sx * 0.28, -0.08, -0.30), CHEEK, head)
		cmi.scale = Vector3(1.1, 0.8, 0.5)

	# 鼻(ちょこん)
	var nose := SphereMesh.new()
	nose.radius = 0.05
	nose.height = 0.1
	_add_part(nose, Vector3(0, -0.04, -0.42), NOSE, head)

	# 帽子(しんかんせんの うんてんしさん)
	var crown := CylinderMesh.new()
	crown.top_radius = 0.4
	crown.bottom_radius = 0.44
	crown.height = 0.34
	_add_part(crown, Vector3(0, 0.46, 0), HAT, head)
	var band := CylinderMesh.new()
	band.top_radius = 0.45
	band.bottom_radius = 0.45
	band.height = 0.08
	_add_part(band, Vector3(0, 0.3, 0), HAT_DARK, head)
	var brim := BoxMesh.new()
	brim.size = Vector3(0.56, 0.07, 0.3)
	_add_part(brim, Vector3(0, 0.3, -0.34), HAT_DARK, head)
	# エンブレム(金の星っぽい点)
	var emb := SphereMesh.new()
	emb.radius = 0.06
	emb.height = 0.12
	var emi := _add_unshaded(emb, Vector3(0, 0.42, -0.4), EMBLEM, head)
	emi.scale = Vector3(1.0, 1.0, 0.5)


# === パーツ生成ヘルパー ===

# リムライト付き(輪郭がふんわり光る)
func _add_part(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var sm := ShaderMaterial.new()
	sm.shader = RIM_SHADER
	sm.set_shader_parameter("albedo", color)
	sm.set_shader_parameter("roughness_val", 0.7)
	sm.set_shader_parameter("rim_color", Color(1, 1, 0.96))
	sm.set_shader_parameter("rim_power", 2.5)
	sm.set_shader_parameter("rim_strength", 0.5)
	mi.material_override = sm
	mi.position = pos
	parent.add_child(mi)
	return mi


# UNSHADED(目・ほっぺ・エンブレムなど、陰の影響を受けず鮮やかに)
func _add_unshaded(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
