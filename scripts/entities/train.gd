extends Node3D

# class_name は Godot エディタが project をスキャンするまで CLI で
# 認識されないため preload 両対応
const TrainData = preload("res://scripts/entities/train_data.gd")

# 列車本体スクリプト。
# - _ready で railway の Path3D を取得し、PathFollow3D を動的に add_child
# - _process で楕円パラメータ t を進めて PathFollow3D の progress_ratio を更新
# - 見た目は train_data に応じてスクリプトで全部組み立て
#
# 設計方針: ロジック層と Godot 操作層を分離(player.gd 等と同じパターン)

@export var train_data: TrainData
@export var railway_path: NodePath

# === 車両構成定数 ===
const LEAD_LENGTH: float = 5.5
const MID_LENGTH: float = 4.5
const CAR_WIDTH: float = 1.9
const CAR_HEIGHT: float = 1.5
const ACCENT_BAND_HEIGHT: float = 0.25
const WINDOW_BAND_HEIGHT: float = 0.5
const WHEEL_RADIUS: float = 0.32
const WHEEL_HEIGHT_OFFSET: float = -0.5
const WINDOW_COLOR: Color = Color(0.4, 0.8, 1.0)  # #66ccff
const WHEEL_COLOR: Color = Color(0.13, 0.13, 0.13)
const HEADLIGHT_COLOR: Color = Color(1.0, 1.0, 0.8)

var _path_follow: PathFollow3D
var _t: float = 0.0


func _ready() -> void:
	if train_data == null:
		push_warning("[Train] train_data が未設定")
		return
	if railway_path.is_empty():
		push_warning("[Train] railway_path が未設定")
		return
	var path_node := get_node_or_null(railway_path) as Path3D
	if path_node == null:
		push_warning("[Train] railway_path の参照先が Path3D でない")
		return
	_t = train_data.initial_t
	_path_follow = PathFollow3D.new()
	_path_follow.loop = true
	_path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	var visual := _build_visual()
	_path_follow.add_child(visual)
	path_node.add_child(_path_follow)
	_update_progress()


func _process(delta: float) -> void:
	if _path_follow == null or train_data == null:
		return
	_t = fmod(_t + train_data.speed * delta, TAU)
	_update_progress()


# === ロジック層 ===

func _update_progress() -> void:
	if _path_follow:
		_path_follow.progress_ratio = _t / TAU


# === メッシュ構築(Godot 操作層) ===

func _build_visual() -> Node3D:
	var root := Node3D.new()
	# PathFollow3D ローカル座標: -Z が進行方向(先頭)、+Z が後方(末尾)
	var lead := _build_car(LEAD_LENGTH, "lead")
	lead.position = Vector3(0, 1.1, -(LEAD_LENGTH * 0.5 + MID_LENGTH * 0.5))
	root.add_child(lead)

	var mid := _build_car(MID_LENGTH, "mid")
	mid.position = Vector3(0, 1.1, 0)
	root.add_child(mid)

	var tail := _build_car(LEAD_LENGTH, "tail")
	tail.position = Vector3(0, 1.1, LEAD_LENGTH * 0.5 + MID_LENGTH * 0.5)
	tail.rotate_y(PI)  # 末尾は逆向き
	root.add_child(tail)

	return root


func _build_car(car_len: float, role: String) -> Node3D:
	var car := Node3D.new()

	# 本体(BoxMesh)
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(CAR_WIDTH, CAR_HEIGHT, car_len)
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = body_mesh
	body_mi.material_override = _make_material(train_data.body_color, 0.5)
	car.add_child(body_mi)

	# アクセント帯
	var accent_mesh := BoxMesh.new()
	accent_mesh.size = Vector3(CAR_WIDTH + 0.05, ACCENT_BAND_HEIGHT, car_len - 0.2)
	var accent_mi := MeshInstance3D.new()
	accent_mi.mesh = accent_mesh
	accent_mi.material_override = _make_material(train_data.accent_color, 0.4)
	accent_mi.position = Vector3(0, 0.05, 0)
	car.add_child(accent_mi)

	# 窓帯(unshaded 水色)
	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3(CAR_WIDTH + 0.06, WINDOW_BAND_HEIGHT, car_len - 0.6)
	var window_mi := MeshInstance3D.new()
	window_mi.mesh = window_mesh
	window_mi.material_override = _make_unshaded_material(WINDOW_COLOR)
	window_mi.position = Vector3(0, 0.35, 0)
	car.add_child(window_mi)

	# 車輪 4 個
	var wheel_positions: Array[Vector3] = [
		Vector3(0.75, WHEEL_HEIGHT_OFFSET, car_len * 0.4),
		Vector3(-0.75, WHEEL_HEIGHT_OFFSET, car_len * 0.4),
		Vector3(0.75, WHEEL_HEIGHT_OFFSET, -car_len * 0.4),
		Vector3(-0.75, WHEEL_HEIGHT_OFFSET, -car_len * 0.4),
	]
	for wp in wheel_positions:
		var wheel := _build_wheel()
		wheel.position = wp
		car.add_child(wheel)

	# 役割別パーツ
	if role == "lead" or role == "tail":
		_attach_nose_and_headlight(car, car_len)
	elif role == "mid" and train_data.has_pantograph:
		_attach_pantograph(car)

	return car


func _build_wheel() -> Node3D:
	var cyl := CylinderMesh.new()
	cyl.top_radius = WHEEL_RADIUS
	cyl.bottom_radius = WHEEL_RADIUS
	cyl.height = 0.18
	var mi := MeshInstance3D.new()
	mi.mesh = cyl
	mi.material_override = _make_material(WHEEL_COLOR, 0.8)
	# 車輪を横向きに(X 軸方向に回転 90°)
	mi.rotate_z(PI * 0.5)
	return mi


func _attach_nose_and_headlight(car: Node3D, car_len: float) -> void:
	# ノーズは先端(-Z 方向)に取り付ける
	var nose_z: float = -car_len * 0.5 - 0.5
	var nose := _build_nose(train_data.nose_type)
	nose.position = Vector3(0, 0.0, nose_z)
	car.add_child(nose)

	# ヘッドライト(sharp/rounded のみ、steam は省略)
	if train_data.nose_type != "steam":
		for x in [-0.5, 0.5]:
			var hl := SphereMesh.new()
			hl.radius = 0.15
			hl.height = 0.3
			hl.radial_segments = 8
			hl.rings = 4
			var hl_mi := MeshInstance3D.new()
			hl_mi.mesh = hl
			hl_mi.material_override = _make_emission_material(HEADLIGHT_COLOR)
			hl_mi.position = Vector3(x, 0.0, nose_z - 0.3)
			car.add_child(hl_mi)


func _build_nose(nose_type: String) -> Node3D:
	var nose := Node3D.new()
	if nose_type == "sharp":
		# SphereMesh を長く尖らせる
		var sm := SphereMesh.new()
		sm.radius = 0.9
		sm.height = 1.8
		sm.radial_segments = 10
		sm.rings = 6
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = _make_material(train_data.body_color, 0.5)
		mi.scale = Vector3(1.0, 0.7, 2.5)
		nose.add_child(mi)
	elif nose_type == "rounded":
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		sm.radial_segments = 10
		sm.rings = 6
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.material_override = _make_material(train_data.body_color, 0.5)
		mi.scale = Vector3(0.95, 0.85, 1.5)
		nose.add_child(mi)
	elif nose_type == "steam":
		# SL ボディ(横向きの大きな円柱)+ 縦の煙突
		var body := CylinderMesh.new()
		body.top_radius = 0.8
		body.bottom_radius = 0.8
		body.height = 1.5
		var body_mi := MeshInstance3D.new()
		body_mi.mesh = body
		body_mi.material_override = _make_material(train_data.body_color, 0.8)
		body_mi.rotate_x(PI * 0.5)  # 横向き
		nose.add_child(body_mi)

		var stack := CylinderMesh.new()
		stack.top_radius = 0.25
		stack.bottom_radius = 0.3
		stack.height = 0.8
		var stack_mi := MeshInstance3D.new()
		stack_mi.mesh = stack
		stack_mi.material_override = _make_material(train_data.body_color, 0.8)
		stack_mi.position = Vector3(0, 0.8, 0.3)
		nose.add_child(stack_mi)
	return nose


func _attach_pantograph(car: Node3D) -> void:
	var roof_y: float = CAR_HEIGHT * 0.5 + 0.05
	var base := BoxMesh.new()
	base.size = Vector3(0.8, 0.04, 0.1)
	var base_mi := MeshInstance3D.new()
	base_mi.mesh = base
	base_mi.material_override = _make_material(WHEEL_COLOR, 0.5)
	base_mi.position = Vector3(0, roof_y + 0.02, 0)
	car.add_child(base_mi)

	var arm := CylinderMesh.new()
	arm.top_radius = 0.04
	arm.bottom_radius = 0.04
	arm.height = 0.7
	var arm_mi := MeshInstance3D.new()
	arm_mi.mesh = arm
	arm_mi.material_override = _make_material(WHEEL_COLOR, 0.5)
	arm_mi.position = Vector3(0, roof_y + 0.4, 0)
	arm_mi.rotate_x(0.3)
	car.add_child(arm_mi)


# === マテリアル生成 ===

func _make_material(color: Color, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = roughness
	mat.metallic = 0.05
	return mat


func _make_unshaded_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _make_emission_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat
