extends Node3D

# 街。オープンワールドの世界観づくり。
# - メインの街(中央)+ 各駅のそばの小さな集落
# - 駅前広場(噴水・ベンチ・街灯)、街路樹
# - 線路と道が交わる踏切(遮断機・警報機)
# 見た目は全部スクリプト生成、配置は seed 固定で毎回同じ。窓・街灯・水は光る。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const TOWN_SEED: int = 2025

@export var railway_path: NodePath = NodePath("../Railway")
var _railway: Node

# 集落の中心(広域マップ内のクリア地。線路網と重ならない位置に手配置)
const VILLAGE_CENTERS: Array = [
	Vector2(150.0, 45.0),    # メインの街(やまのて線の内側)
	Vector2(-70.0, 70.0),
	Vector2(-40.0, -110.0),
	Vector2(120.0, -150.0),
]
# 踏切を置く { ルート, 全長比 }(地表を走るループの上)
const CROSSINGS: Array = [
	{ "slug": "komachi", "ratio": 0.0 },
	{ "slug": "komachi", "ratio": 0.25 },
	{ "slug": "e235_yamanote", "ratio": 0.5 },
]

const WALL_COLORS: Array = [
	Color(1.0, 0.85, 0.85), Color(0.85, 0.92, 1.0), Color(1.0, 0.97, 0.8),
	Color(0.85, 1.0, 0.88), Color(1.0, 0.9, 0.8), Color(0.92, 0.85, 1.0),
]
const ROOF_COLORS: Array = [
	Color(0.9, 0.4, 0.45), Color(0.4, 0.6, 0.85), Color(0.5, 0.75, 0.45),
	Color(0.95, 0.7, 0.35), Color(0.7, 0.5, 0.8),
]
const AWNING_COLORS: Array = [Color(0.95, 0.45, 0.5), Color(0.45, 0.7, 0.95), Color(0.5, 0.78, 0.5)]
const WINDOW_COLOR: Color = Color(0.55, 0.85, 1.0)
const DOOR_COLOR: Color = Color(0.5, 0.33, 0.2)
const PAVE: Color = Color(0.82, 0.8, 0.76)
const WATER_B: Color = Color(0.45, 0.78, 0.95)
const LAMP_C: Color = Color(1.0, 0.95, 0.6)
const BENCH_C: Color = Color(0.62, 0.43, 0.28)
const POLE_C: Color = Color(0.32, 0.32, 0.35)
const RED_C: Color = Color(0.95, 0.25, 0.25)
const YELLOW_C: Color = Color(1.0, 0.85, 0.2)


func _ready() -> void:
	_railway = get_node_or_null(railway_path)
	seed(TOWN_SEED)
	# メインの街 + いくつかの集落(広域マップのクリア地)
	for i in range(VILLAGE_CENTERS.size()):
		_build_village(VILLAGE_CENTERS[i], 9 if i == 0 else 4, i == 0)
	# 踏切(地表ループの線路上に横断道路)
	if _railway and _railway.has_method("get_route_sample"):
		for c in CROSSINGS:
			_build_crossing_on(String(c["slug"]), float(c["ratio"]))


# === 集落 ===

func _build_village(center: Vector2, count: int, big: bool) -> void:
	for i in range(count):
		var ang: float = randf() * TAU
		var dist: float = randf_range(7.0, 17.0)
		var x: float = center.x + cos(ang) * dist
		var z: float = center.y + sin(ang) * dist
		var roll: int = randi() % 10
		if roll < 5:
			_build_house(x, z)
		elif roll < 8:
			_build_shop(x, z)
		else:
			_build_tower(x, z)
		if randi() % 3 == 0:
			_build_tree(x + randf_range(-3, 3), z + randf_range(-3, 3))

	if big:
		_build_plaza(center)
	else:
		_build_lamp(center.x, center.y)
		_build_bench(center.x + 2.0, center.y, 0.0)


# === 駅前広場 ===

func _build_plaza(center: Vector2) -> void:
	# 舗装の円
	var pave := CylinderMesh.new()
	pave.top_radius = 6.5
	pave.bottom_radius = 6.5
	pave.height = 0.12
	var root := _new_root(center.x, center.y)
	root.rotation.y = 0.0
	_mesh(root, pave, Vector3(0, 0.06, 0), PAVE, 0.95)
	_build_fountain(center.x, center.y)
	_build_bench(center.x + 4.0, center.y, 0.0)
	_build_bench(center.x - 4.0, center.y, PI)
	_build_lamp(center.x + 5.5, center.y + 5.5)
	_build_lamp(center.x - 5.5, center.y - 5.5)


func _build_fountain(x: float, z: float) -> void:
	var root := _new_root(x, z)
	root.rotation.y = 0.0
	# 下の水盤
	var basin := CylinderMesh.new()
	basin.top_radius = 2.0
	basin.bottom_radius = 2.1
	basin.height = 0.6
	_mesh(root, basin, Vector3(0, 0.3, 0), PAVE, 0.9)
	# 水(半透明・少し光る)
	_water_disk(root, 1.8, Vector3(0, 0.55, 0))
	# 中央の柱と上皿
	var col := CylinderMesh.new()
	col.top_radius = 0.18
	col.bottom_radius = 0.22
	col.height = 1.1
	_mesh(root, col, Vector3(0, 1.0, 0), PAVE, 0.9)
	var top := CylinderMesh.new()
	top.top_radius = 0.7
	top.bottom_radius = 0.6
	top.height = 0.16
	_mesh(root, top, Vector3(0, 1.5, 0), PAVE, 0.9)
	_water_disk(root, 0.55, Vector3(0, 1.6, 0))


func _water_disk(root: Node3D, radius: float, pos: Vector3) -> void:
	var disk := CylinderMesh.new()
	disk.top_radius = radius
	disk.bottom_radius = radius
	disk.height = 0.12
	var mi := MeshInstance3D.new()
	mi.mesh = disk
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(WATER_B.r, WATER_B.g, WATER_B.b, 0.8)
	mat.emission_enabled = true
	mat.emission = WATER_B
	mat.emission_energy_multiplier = 0.4
	mat.roughness = 0.2
	mat.metallic = 0.3
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)


func _build_lamp(x: float, z: float) -> void:
	var root := _new_root(x, z)
	root.rotation.y = 0.0
	var pole := CylinderMesh.new()
	pole.top_radius = 0.07
	pole.bottom_radius = 0.09
	pole.height = 2.6
	_mesh(root, pole, Vector3(0, 1.3, 0), POLE_C, 0.6)
	# 光る玉(夜は Glow で街灯に)
	var bulb := SphereMesh.new()
	bulb.radius = 0.22
	bulb.height = 0.44
	var mi := MeshInstance3D.new()
	mi.mesh = bulb
	var mat := StandardMaterial3D.new()
	mat.albedo_color = LAMP_C
	mat.emission_enabled = true
	mat.emission = LAMP_C
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = Vector3(0, 2.7, 0)
	root.add_child(mi)


func _build_bench(x: float, z: float, rot: float) -> void:
	var root := _new_root(x, z)
	root.rotation.y = rot
	_box(root, Vector3(1.5, 0.12, 0.5), Vector3(0, 0.45, 0), BENCH_C, 0.8)
	_box(root, Vector3(1.5, 0.5, 0.12), Vector3(0, 0.7, 0.19), BENCH_C, 0.8)
	for sx in [-0.6, 0.6]:
		_box(root, Vector3(0.1, 0.45, 0.45), Vector3(sx, 0.22, 0), POLE_C, 0.7)


# === 踏切 ===

func _build_crossing_on(slug: String, ratio: float) -> void:
	var s: Dictionary = _railway.get_route_sample(slug, ratio)
	if s.is_empty():
		return
	var pos: Vector3 = s["position"]
	var fwd: Vector3 = s["forward"]
	var g: float = TerrainHeight.compute_height(pos.x, pos.z) + 0.32
	var root := Node3D.new()
	root.position = Vector3(pos.x, g, pos.z)
	# ローカル -Z を線路方向へ(道はローカル X 方向に線路を横断)
	root.rotation.y = atan2(fwd.x, fwd.z)
	add_child(root)

	# 道(線路を横切る板)
	_box(root, Vector3(9.0, 0.08, 3.4), Vector3(0, 0, 0), Color(0.6, 0.6, 0.62), 0.95)

	# 両脇に警報機+遮断機
	for sx in [-1.0, 1.0]:
		var base_x: float = sx * 3.6
		# ポール
		_box(root, Vector3(0.22, 2.4, 0.22), Vector3(base_x, 1.2, 0), POLE_C, 0.6)
		# 赤い警報ライト(光る)
		var light := SphereMesh.new()
		light.radius = 0.18
		light.height = 0.36
		var mi := MeshInstance3D.new()
		mi.mesh = light
		var mat := StandardMaterial3D.new()
		mat.albedo_color = RED_C
		mat.emission_enabled = true
		mat.emission = RED_C
		mat.emission_energy_multiplier = 2.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
		mi.position = Vector3(base_x, 2.5, 0)
		root.add_child(mi)
		# 遮断機バー(黄色、線路側へ水平に伸ばす)
		var bar := BoxMesh.new()
		bar.size = Vector3(2.6, 0.14, 0.14)
		_box_node(root, bar, Vector3(base_x - sx * 1.5, 1.7, 0), YELLOW_C)


# === 建物(集落から呼ぶ) ===

func _new_root(x: float, z: float) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(x, TerrainHeight.compute_height(x, z), z)
	n.rotation.y = (randi() % 4) * PI * 0.5
	add_child(n)
	return n


func _build_house(x: float, z: float) -> void:
	var root := _new_root(x, z)
	var wall: Color = WALL_COLORS[randi() % WALL_COLORS.size()]
	var roof: Color = ROOF_COLORS[randi() % ROOF_COLORS.size()]
	_box(root, Vector3(3.0, 2.4, 3.0), Vector3(0, 1.2, 0), wall, 0.9)
	var prism := PrismMesh.new()
	prism.size = Vector3(3.5, 1.4, 3.5)
	_mesh(root, prism, Vector3(0, 3.1, 0), roof, 0.85)
	_box(root, Vector3(0.7, 1.2, 0.12), Vector3(0, 0.6, -1.52), DOOR_COLOR, 0.8)
	for sx in [-0.85, 0.85]:
		_window(root, Vector3(sx, 1.5, -1.52))


func _build_shop(x: float, z: float) -> void:
	var root := _new_root(x, z)
	var wall: Color = WALL_COLORS[randi() % WALL_COLORS.size()]
	var awning: Color = AWNING_COLORS[randi() % AWNING_COLORS.size()]
	_box(root, Vector3(3.2, 2.2, 3.0), Vector3(0, 1.1, 0), wall, 0.9)
	_box(root, Vector3(3.5, 0.25, 3.3), Vector3(0, 2.35, 0), ROOF_COLORS[1], 0.8)
	_box(root, Vector3(3.3, 0.14, 0.8), Vector3(0, 1.7, -1.7), awning, 0.7)
	_box(root, Vector3(1.9, 0.5, 0.1), Vector3(0, 2.15, -1.55), awning, 0.6)
	_window(root, Vector3(-0.75, 1.0, -1.52))
	_box(root, Vector3(0.8, 1.4, 0.12), Vector3(0.75, 0.7, -1.52), DOOR_COLOR, 0.8)


func _build_tower(x: float, z: float) -> void:
	var root := _new_root(x, z)
	var wall: Color = WALL_COLORS[randi() % WALL_COLORS.size()]
	var floors: int = 3 + randi() % 2
	var h: float = floors * 1.8
	_box(root, Vector3(3.0, h, 3.0), Vector3(0, h * 0.5, 0), wall, 0.85)
	_box(root, Vector3(3.2, 0.3, 3.2), Vector3(0, h + 0.1, 0), ROOF_COLORS[3], 0.8)
	for fl in range(floors):
		for sx in [-0.8, 0.0, 0.8]:
			_window(root, Vector3(sx, 1.0 + fl * 1.8, -1.52), Vector3(0.5, 0.7, 0.1))


func _build_tree(x: float, z: float) -> void:
	var root := _new_root(x, z)
	root.rotation.y = 0.0
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.24
	trunk.height = 1.6
	_mesh(root, trunk, Vector3(0, 0.8, 0), Color(0.45, 0.3, 0.16), 0.9)
	for i in range(2):
		var leaf := SphereMesh.new()
		leaf.radius = 0.95 - i * 0.2
		leaf.height = leaf.radius * 2.0
		_mesh(root, leaf, Vector3(0, 1.9 + i * 0.5, 0), Color(0.4, 0.72, 0.38), 0.85)


# === メッシュヘルパー ===

func _box(root: Node3D, size: Vector3, pos: Vector3, color: Color, rough: float) -> void:
	var b := BoxMesh.new()
	b.size = size
	_mesh(root, b, pos, color, rough)


func _box_node(root: Node3D, mesh: Mesh, pos: Vector3, color: Color) -> void:
	_mesh(root, mesh, pos, color, 0.7)


func _window(root: Node3D, pos: Vector3, size: Vector3 = Vector3(0.6, 0.7, 0.1)) -> void:
	var b := BoxMesh.new()
	b.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WINDOW_COLOR
	mat.emission_enabled = true
	mat.emission = WINDOW_COLOR
	mat.emission_energy_multiplier = 1.2
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)


func _mesh(root: Node3D, mesh: Mesh, pos: Vector3, color: Color, rough: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = 0.0
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
