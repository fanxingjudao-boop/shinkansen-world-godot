extends Node3D

# 街。線路の内側の区画に、かわいい低ポリの建物(家・お店・ビル)を並べる。
# 窓は UNSHADED の水色で、夜は Glow と相まって街の灯りのように光る。
# 建物の見た目は全部スクリプト生成。配置は seed 固定で毎回同じ(子供が街を覚えられる)。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const GRID_COLS: int = 5
const GRID_ROWS: int = 4
const SPACING: float = 14.0
const ORIGIN: Vector2 = Vector2(18.0, -48.0)  # 街の左奥(線路内側・プレイヤー前方)
const TOWN_SEED: int = 2025

# パステルの壁・屋根色
const WALL_COLORS: Array = [
	Color(1.0, 0.85, 0.85), Color(0.85, 0.92, 1.0), Color(1.0, 0.97, 0.8),
	Color(0.85, 1.0, 0.88), Color(1.0, 0.9, 0.8), Color(0.92, 0.85, 1.0),
]
const ROOF_COLORS: Array = [
	Color(0.9, 0.4, 0.45), Color(0.4, 0.6, 0.85), Color(0.5, 0.75, 0.45),
	Color(0.95, 0.7, 0.35), Color(0.7, 0.5, 0.8),
]
const WINDOW_COLOR: Color = Color(0.55, 0.85, 1.0)
const DOOR_COLOR: Color = Color(0.5, 0.33, 0.2)
const AWNING_COLORS: Array = [Color(0.95, 0.45, 0.5), Color(0.45, 0.7, 0.95), Color(0.5, 0.78, 0.5)]


func _ready() -> void:
	seed(TOWN_SEED)
	for r in range(GRID_ROWS):
		for c in range(GRID_COLS):
			# 真ん中の列は「通り」として空ける(街に道を通す)
			if c == 2 and r != 0:
				continue
			var x: float = ORIGIN.x + c * SPACING + randf_range(-1.5, 1.5)
			var z: float = ORIGIN.y + r * SPACING + randf_range(-1.5, 1.5)
			var roll: int = randi() % 10
			if roll < 5:
				_build_house(x, z)
			elif roll < 8:
				_build_shop(x, z)
			else:
				_build_tower(x, z)
	# 街路樹
	for i in range(5):
		var tx: float = ORIGIN.x + randf_range(0, (GRID_COLS - 1) * SPACING)
		var tz: float = ORIGIN.y + randf_range(0, (GRID_ROWS - 1) * SPACING)
		_build_tree(tx + 6.0, tz + 6.0)


# === 建物 ===

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
	# 壁
	_box(root, Vector3(3.0, 2.4, 3.0), Vector3(0, 1.2, 0), wall, 0.9)
	# 三角屋根
	var prism := PrismMesh.new()
	prism.size = Vector3(3.5, 1.4, 3.5)
	_mesh(root, prism, Vector3(0, 3.1, 0), roof, 0.85)
	# ドア(正面 -Z)
	_box(root, Vector3(0.7, 1.2, 0.12), Vector3(0, 0.6, -1.52), DOOR_COLOR, 0.8)
	# 窓 ×2(光る)
	for sx in [-0.85, 0.85]:
		_window(root, Vector3(sx, 1.5, -1.52))


func _build_shop(x: float, z: float) -> void:
	var root := _new_root(x, z)
	var wall: Color = WALL_COLORS[randi() % WALL_COLORS.size()]
	var awning: Color = AWNING_COLORS[randi() % AWNING_COLORS.size()]
	_box(root, Vector3(3.2, 2.2, 3.0), Vector3(0, 1.1, 0), wall, 0.9)
	# 平屋根
	_box(root, Vector3(3.5, 0.25, 3.3), Vector3(0, 2.35, 0), ROOF_COLORS[1], 0.8)
	# 日よけ(正面)
	_box(root, Vector3(3.3, 0.14, 0.8), Vector3(0, 1.7, -1.7), awning, 0.7)
	# 看板
	_box(root, Vector3(1.9, 0.5, 0.1), Vector3(0, 2.15, -1.55), awning, 0.6)
	# 大きな窓 + ドア
	_window(root, Vector3(-0.75, 1.0, -1.52))
	_box(root, Vector3(0.8, 1.4, 0.12), Vector3(0.75, 0.7, -1.52), DOOR_COLOR, 0.8)


func _build_tower(x: float, z: float) -> void:
	var root := _new_root(x, z)
	var wall: Color = WALL_COLORS[randi() % WALL_COLORS.size()]
	var floors: int = 3 + randi() % 2
	var h: float = floors * 1.8
	_box(root, Vector3(3.0, h, 3.0), Vector3(0, h * 0.5, 0), wall, 0.85)
	# 屋上
	_box(root, Vector3(3.2, 0.3, 3.2), Vector3(0, h + 0.1, 0), ROOF_COLORS[3], 0.8)
	# 窓格子(正面)
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
	mi.mesh = b
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
