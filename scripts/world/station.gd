extends Node3D

# 駅シーン。station_data に応じて線路脇に駅を組み立てる。
# - 楕円トラック上 track_t の位置を Railway.ellipse_point で求め、外側にプラットフォーム
# - プラットフォーム + 屋根(柱4本+屋根板)+ 看板(Label3D, 常に読める Y ビルボード)+ 固有装飾
# - 見た目は全部スクリプト生成(駅ごとに色・装飾が変わるので静的シーン化しない、Train と同方針)

const StationData = preload("res://scripts/world/station_data.gd")
const TerrainHeight = preload("res://scripts/world/terrain_height.gd")
const Railway = preload("res://scripts/world/railway.gd")

@export var station_data: StationData

const PLATFORM_LEN: float = 12.0    # 線路沿いの長さ(ローカル Z)
const PLATFORM_DEPTH: float = 4.0   # 線路からの奥行(ローカル X)
const PLATFORM_THICK: float = 0.5
const SIDE_OFFSET: float = 4.4      # 線路中心からプラットフォーム中心まで
const PILLAR_H: float = 3.0
const PILLAR_R: float = 0.12


func _ready() -> void:
	if station_data == null:
		push_warning("[Station] station_data が未設定")
		return
	_build()


func _build() -> void:
	var t: float = station_data.track_t
	var center: Vector2 = Railway.ellipse_point(t)
	var tangent: Vector2 = Railway.ellipse_tangent(t)
	var perp: Vector2 = Vector2(-tangent.y, tangent.x)
	if perp.dot(center) < 0.0:
		perp = -perp  # 楕円の外向き(線路の外側にプラットフォームを置く)
	var plat2: Vector2 = center + perp * SIDE_OFFSET
	var ground: float = TerrainHeight.compute_height(plat2.x, plat2.y)
	# 湖の上の区間では線路と同様に水面以上へ持ち上げる(沈み防止)
	var lake_d: float = (center - TerrainHeight.LAKE_POS).length()
	if lake_d < TerrainHeight.LAKE_RADIUS:
		ground = max(ground, TerrainHeight.compute_water_y())
	position = Vector3(plat2.x, ground, plat2.y)
	# ローカル -Z を線路接線方向へ(プラットフォーム長辺 Z が線路に沿う)
	rotation.y = atan2(tangent.x, tangent.y)

	_build_platform()
	_build_roof()
	_build_sign()
	_build_decor()


# === パーツ構築(Godot 操作層) ===

func _build_platform() -> void:
	var plat := BoxMesh.new()
	plat.size = Vector3(PLATFORM_DEPTH, PLATFORM_THICK, PLATFORM_LEN)
	var mi := MeshInstance3D.new()
	mi.mesh = plat
	mi.material_override = _mat(station_data.main_color.lightened(0.55), 0.85)
	mi.position = Vector3(0, PLATFORM_THICK * 0.5, 0)
	add_child(mi)

	# 縁取り(アクセント色の薄い帯)
	var edge := BoxMesh.new()
	edge.size = Vector3(PLATFORM_DEPTH + 0.2, 0.12, PLATFORM_LEN + 0.2)
	var emi := MeshInstance3D.new()
	emi.mesh = edge
	emi.material_override = _mat(station_data.accent_color, 0.7)
	emi.position = Vector3(0, PLATFORM_THICK - 0.02, 0)
	add_child(emi)


func _build_roof() -> void:
	var top: float = PLATFORM_THICK
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var pillar := CylinderMesh.new()
			pillar.top_radius = PILLAR_R
			pillar.bottom_radius = PILLAR_R
			pillar.height = PILLAR_H
			var pmi := MeshInstance3D.new()
			pmi.mesh = pillar
			pmi.material_override = _mat(station_data.accent_color, 0.6)
			pmi.position = Vector3(
				sx * (PLATFORM_DEPTH * 0.5 - 0.5),
				top + PILLAR_H * 0.5,
				sz * (PLATFORM_LEN * 0.5 - 0.8)
			)
			add_child(pmi)

	# 屋根板(少しオーバーハング)
	var roof := BoxMesh.new()
	roof.size = Vector3(PLATFORM_DEPTH + 0.8, 0.3, PLATFORM_LEN + 0.8)
	var rmi := MeshInstance3D.new()
	rmi.mesh = roof
	rmi.material_override = _mat(station_data.main_color, 0.6)
	rmi.position = Vector3(0, top + PILLAR_H + 0.15, 0)
	add_child(rmi)


func _build_sign() -> void:
	var top: float = PLATFORM_THICK + PILLAR_H + 0.3
	# 駅名(大)
	var name_label := Label3D.new()
	name_label.text = station_data.display_name
	name_label.font_size = 130
	name_label.pixel_size = 0.01
	name_label.modulate = Color.WHITE
	name_label.outline_size = 28
	name_label.outline_modulate = station_data.main_color.darkened(0.45)
	name_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	name_label.no_depth_test = false
	name_label.position = Vector3(0, top + 1.5, 0)
	add_child(name_label)

	# サブテキスト(小)
	if station_data.sub_text != "":
		var sub_label := Label3D.new()
		sub_label.text = station_data.sub_text
		sub_label.font_size = 70
		sub_label.pixel_size = 0.01
		sub_label.modulate = station_data.main_color.darkened(0.3)
		sub_label.outline_size = 18
		sub_label.outline_modulate = Color.WHITE
		sub_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		sub_label.position = Vector3(0, top + 0.85, 0)
		add_child(sub_label)


# プラットフォーム端(線路沿いの外側)に固有装飾を 1 つ置く
func _build_decor() -> void:
	var base := Vector3(0, PLATFORM_THICK, PLATFORM_LEN * 0.5 + 2.0)
	match station_data.decor_type:
		"tree":
			_decor_tree(base)
		"flower":
			_decor_flower(base)
		"mountain":
			_decor_mountain(base)
		"lake":
			_decor_lake(base)
		"sweets":
			_decor_sweets(base)
		"rainbow":
			_decor_rainbow(base)
		_:
			_decor_tree(base)


func _decor_tree(base: Vector3) -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.2
	trunk.bottom_radius = 0.26
	trunk.height = 1.6
	_add_mesh(trunk, base + Vector3(0, 0.8, 0), _mat(Color(0.45, 0.3, 0.16), 0.9))
	for i in range(3):
		var leaf := SphereMesh.new()
		leaf.radius = 0.85 - i * 0.12
		leaf.height = leaf.radius * 2.0
		_add_mesh(leaf, base + Vector3(0, 1.7 + i * 0.55, 0), _mat(Color(0.36, 0.72, 0.34), 0.85))


func _decor_flower(base: Vector3) -> void:
	# 緑の小山 + カラフルな花玉
	var mound := SphereMesh.new()
	mound.radius = 1.0
	mound.height = 1.0
	_add_mesh(mound, base + Vector3(0, 0.05, 0), _mat(Color(0.45, 0.75, 0.4), 0.9))
	var colors := [
		Color(1.0, 0.42, 0.6), Color(1.0, 0.88, 0.4), Color(0.7, 0.55, 1.0),
		Color(1.0, 0.62, 0.35), Color(1.0, 1.0, 1.0),
	]
	for i in range(colors.size()):
		var a: float = float(i) / float(colors.size()) * TAU
		var petal := SphereMesh.new()
		petal.radius = 0.26
		petal.height = 0.52
		_add_mesh(petal, base + Vector3(cos(a) * 0.7, 0.7, sin(a) * 0.7), _mat(colors[i], 0.6))


func _decor_mountain(base: Vector3) -> void:
	var mtn := CylinderMesh.new()
	mtn.top_radius = 0.0
	mtn.bottom_radius = 1.3
	mtn.height = 2.6
	_add_mesh(mtn, base + Vector3(0, 1.3, 0), _mat(Color(0.5, 0.62, 0.72), 0.9))
	# 雪の頂
	var snow := CylinderMesh.new()
	snow.top_radius = 0.0
	snow.bottom_radius = 0.5
	snow.height = 1.0
	_add_mesh(snow, base + Vector3(0, 2.1, 0), _mat(Color(0.97, 1.0, 1.0), 0.7))


func _decor_lake(base: Vector3) -> void:
	var pond := CylinderMesh.new()
	pond.top_radius = 1.4
	pond.bottom_radius = 1.4
	pond.height = 0.18
	var mat := _mat(Color(0.45, 0.78, 0.95), 0.25)
	mat.metallic = 0.3
	_add_mesh(pond, base + Vector3(0, 0.1, 0), mat)


func _decor_sweets(base: Vector3) -> void:
	# 三色だんご(串 + 3 玉)
	var stick := CylinderMesh.new()
	stick.top_radius = 0.05
	stick.bottom_radius = 0.05
	stick.height = 2.0
	_add_mesh(stick, base + Vector3(0, 1.0, 0), _mat(Color(0.8, 0.6, 0.35), 0.8))
	var dango := [Color(1.0, 0.7, 0.8), Color(1.0, 1.0, 0.95), Color(0.6, 0.85, 0.5)]
	for i in range(dango.size()):
		var ball := SphereMesh.new()
		ball.radius = 0.38
		ball.height = 0.76
		_add_mesh(ball, base + Vector3(0, 0.7 + i * 0.62, 0), _mat(dango[i], 0.55))


func _decor_rainbow(base: Vector3) -> void:
	# 3 本のアーチ(虹)。TorusMesh を立てて半分を地中に
	var arc_colors := [
		Color(1.0, 0.45, 0.5), Color(1.0, 0.85, 0.4), Color(0.5, 0.7, 1.0),
	]
	for i in range(arc_colors.size()):
		var torus := TorusMesh.new()
		torus.inner_radius = 1.5 + i * 0.35
		torus.outer_radius = 1.7 + i * 0.35
		var mi := MeshInstance3D.new()
		mi.mesh = torus
		mi.material_override = _mat(arc_colors[i], 0.5)
		mi.position = base + Vector3(0, 0.2, 0)
		mi.rotate_x(PI * 0.5)  # 立ててアーチに
		add_child(mi)


# === ヘルパー ===

func _add_mesh(mesh: Mesh, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.0
	return m
