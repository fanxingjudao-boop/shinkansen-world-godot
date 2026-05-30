extends Node3D

# 動物 NPC。animal_data に応じて見た目を組み立て、ホーム周辺をふらふら歩き回る。
# - 見た目は species ごとにスクリプト生成(体+頭+目+耳/鼻/しっぽ)。丸っこいデフォルメ
# - 簡易ステートマシン(IDLE ⇄ WALK)でホーム半径内をぴょこぴょこ移動
# - 地形高さに追従(衝突なし=子供向けにすり抜けOK)
# - なかよし(タッチ)は competition 調停が要るため別ステップ。今は歩くだけ

const AnimalData = preload("res://scripts/entities/animal_data.gd")
const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

@export var animal_data: AnimalData

const SPEED: float = 1.4
const WANDER_RADIUS: float = 8.0
const TURN_SPEED: float = 5.0
const BOUNCE_AMP: float = 0.12
const BOUNCE_FREQ: float = 8.0

enum St { IDLE, WALK }

var _state: int = St.IDLE
var _state_timer: float = 0.0
var _heading: float = 0.0          # 進行方向(yaw, ラジアン)
var _home: Vector2 = Vector2.ZERO
var _visual: Node3D
var _bounce_phase: float = 0.0
var _base_visual_y: float = 0.0
var _befriended: bool = false
var _celebrating: bool = false


func _ready() -> void:
	if animal_data == null:
		push_warning("[Animal] animal_data が未設定")
		return
	_home = Vector2(global_position.x, global_position.z)
	_visual = Node3D.new()
	add_child(_visual)
	_visual.scale = Vector3.ONE * animal_data.scale_factor
	_build_visual()
	_base_visual_y = 0.0
	_settle_y()
	_pick_new_state()


func _process(delta: float) -> void:
	if animal_data == null:
		return
	if _celebrating:
		return  # なかよしの喜びジャンプ中は移動・バウンスを止める
	_state_timer -= delta
	if _state_timer <= 0.0:
		_pick_new_state()

	if _state == St.WALK:
		var dir := Vector3(sin(_heading), 0.0, cos(_heading))
		var next := global_position + dir * SPEED * delta
		# ホームから離れすぎたら向きをホームへ寄せる
		var from_home := Vector2(next.x, next.z) - _home
		if from_home.length() > WANDER_RADIUS:
			_heading = atan2(_home.x - global_position.x, _home.y - global_position.z)
		global_position.x = next.x
		global_position.z = next.z
		_settle_y()
		# 進行方向へ滑らかに向く
		rotation.y = lerp_angle(rotation.y, _heading, TURN_SPEED * delta)
		# ぴょこぴょこ
		_bounce_phase += delta * BOUNCE_FREQ
		_visual.position.y = _base_visual_y + abs(sin(_bounce_phase)) * BOUNCE_AMP
	else:
		_visual.position.y = lerp(_visual.position.y, _base_visual_y, clamp(8.0 * delta, 0.0, 1.0))


# === なかよし(AnimalManager から呼ばれる) ===

func is_befriended() -> bool:
	return _befriended

func get_display_name() -> String:
	return animal_data.display_name if animal_data else ""

func get_slug() -> String:
	return animal_data.slug if animal_data else ""

# なかよし成立: 立ち止まってぴょんと喜ぶ
func befriend() -> void:
	if _befriended:
		return
	_befriended = true
	_state = St.IDLE
	_celebrating = true
	var tw := create_tween()
	tw.tween_property(_visual, "position:y", _base_visual_y + 0.7, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "position:y", _base_visual_y, 0.32) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _celebrating = false)


# === AI(ロジック層に近い簡易ステートマシン) ===

func _pick_new_state() -> void:
	if _state == St.WALK:
		_state = St.IDLE
		_state_timer = randf_range(1.0, 2.5)
	else:
		_state = St.WALK
		_state_timer = randf_range(1.5, 3.5)
		_heading = randf_range(0.0, TAU)


func _settle_y() -> void:
	global_position.y = TerrainHeight.compute_height(global_position.x, global_position.z)


# === 見た目構築(Godot 操作層) ===

func _build_visual() -> void:
	var body_c := animal_data.body_color
	var accent_c := animal_data.accent_color
	var belly_c := animal_data.belly_color

	# 体(少し縦長の球)
	var body := _ball(0.42, body_c, 0.85)
	body.scale = Vector3(1.0, 1.05, 1.15)
	body.position = Vector3(0, 0.42, 0)
	_visual.add_child(body)

	# おなか(前面の明るい色)
	var belly := _ball(0.3, belly_c, 0.85)
	belly.scale = Vector3(0.9, 1.0, 0.7)
	belly.position = Vector3(0, 0.38, -0.22)
	_visual.add_child(belly)

	# 頭(前上)
	var head_y := 0.72
	var head_z := -0.28
	var head := _ball(0.3, body_c, 0.85)
	head.position = Vector3(0, head_y, head_z)
	_visual.add_child(head)

	# 目(共通)
	for sx in [-1.0, 1.0]:
		var eye := _ball(0.055, Color(0.08, 0.06, 0.05), 0.4, true)
		eye.position = Vector3(sx * 0.12, head_y + 0.05, head_z - 0.24)
		_visual.add_child(eye)

	_build_species_parts(head_y, head_z, accent_c, body_c, belly_c)


func _build_species_parts(head_y: float, head_z: float, accent_c: Color, body_c: Color, belly_c: Color) -> void:
	match animal_data.species:
		"rabbit":
			for sx in [-1.0, 1.0]:
				var ear := _box(Vector3(0.1, 0.42, 0.06), accent_c)
				ear.position = Vector3(sx * 0.12, head_y + 0.42, head_z + 0.02)
				ear.rotate_x(-0.2)
				_visual.add_child(ear)
			_add_tail(_ball(0.16, accent_c, 0.9))
		"bear":
			for sx in [-1.0, 1.0]:
				var ear := _ball(0.13, body_c, 0.85)
				ear.position = Vector3(sx * 0.2, head_y + 0.26, head_z)
				_visual.add_child(ear)
			_add_nose(head_y, head_z, Color(0.2, 0.13, 0.1))
		"fox":
			for sx in [-1.0, 1.0]:
				var ear := _cone(0.1, 0.3, accent_c)
				ear.position = Vector3(sx * 0.16, head_y + 0.28, head_z)
				_visual.add_child(ear)
			var tail := _ball(0.2, accent_c, 0.9)
			tail.scale = Vector3(0.9, 0.9, 1.6)
			_add_tail(tail)
		"cat":
			for sx in [-1.0, 1.0]:
				var ear := _cone(0.09, 0.2, body_c)
				ear.position = Vector3(sx * 0.15, head_y + 0.24, head_z)
				_visual.add_child(ear)
			var tail := _box(Vector3(0.08, 0.08, 0.5), body_c)
			tail.position = Vector3(0, 0.5, 0.45)
			tail.rotate_x(-0.6)
			_visual.add_child(tail)
		"panda":
			for sx in [-1.0, 1.0]:
				var ear := _ball(0.12, accent_c, 0.85)
				ear.position = Vector3(sx * 0.2, head_y + 0.26, head_z)
				_visual.add_child(ear)
			# 目の周りの黒(パッチ)
			for sx in [-1.0, 1.0]:
				var patch := _ball(0.1, accent_c, 0.7)
				patch.scale = Vector3(0.9, 1.2, 0.5)
				patch.position = Vector3(sx * 0.12, head_y + 0.04, head_z - 0.2)
				_visual.add_child(patch)
		"dog":
			for sx in [-1.0, 1.0]:
				var ear := _box(Vector3(0.09, 0.26, 0.05), accent_c)
				ear.position = Vector3(sx * 0.22, head_y + 0.1, head_z)
				ear.rotate_z(sx * 0.3)
				_visual.add_child(ear)
			_add_nose(head_y, head_z, Color(0.15, 0.1, 0.08))
			_add_tail(_box(Vector3(0.08, 0.08, 0.34), body_c))
		"penguin":
			# くちばし
			var beak := _cone(0.08, 0.18, Color(1.0, 0.7, 0.2))
			beak.position = Vector3(0, head_y, head_z - 0.28)
			beak.rotate_x(PI * 0.5)
			_visual.add_child(beak)
			# 羽(両脇)
			for sx in [-1.0, 1.0]:
				var wing := _box(Vector3(0.08, 0.34, 0.18), body_c)
				wing.position = Vector3(sx * 0.42, 0.42, 0)
				wing.rotate_z(sx * 0.25)
				_visual.add_child(wing)
		"pig":
			for sx in [-1.0, 1.0]:
				var ear := _cone(0.08, 0.16, accent_c)
				ear.position = Vector3(sx * 0.16, head_y + 0.24, head_z + 0.05)
				ear.rotate_x(0.3)
				_visual.add_child(ear)
			# 丸い鼻
			var snout := _cyl(0.12, 0.1, accent_c)
			snout.position = Vector3(0, head_y, head_z - 0.28)
			snout.rotate_x(PI * 0.5)
			_visual.add_child(snout)
			# くるんとした尾
			_add_tail(_ball(0.1, accent_c, 0.85))
		_:
			pass


func _add_tail(tail: MeshInstance3D) -> void:
	tail.position = Vector3(0, 0.42, 0.5)
	_visual.add_child(tail)


func _add_nose(head_y: float, head_z: float, c: Color) -> void:
	var nose := _ball(0.07, c, 0.5)
	nose.position = Vector3(0, head_y - 0.02, head_z - 0.26)
	_visual.add_child(nose)


# === メッシュヘルパー ===

func _ball(radius: float, color: Color, rough: float, unshaded: bool = false) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 8
	return _mi(s, color, rough, unshaded)


func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mi(b, color, 0.85, false)


func _cone(bottom_r: float, height: float, color: Color) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = bottom_r
	c.height = height
	c.radial_segments = 10
	return _mi(c, color, 0.85, false)


func _cyl(radius: float, height: float, color: Color) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 12
	return _mi(c, color, 0.7, false)


func _mi(mesh: Mesh, color: Color, rough: float, unshaded: bool) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = 0.0
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	return mi
