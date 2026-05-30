extends Node3D

# 線路の見どころ。Main 直下のノード。
# - 鉄橋: 湖を渡る区間に赤いトラス橋(橋脚+主桁+上弦+斜材)
# - トンネル: 山を抜ける区間にレンガの坑口+かまぼこ天井
# 線路の楕円パラメータ(t)に合わせて配置。Y は railway と同じく湖上では水面以上に。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")
const Railway = preload("res://scripts/world/railway.gd")

const RAIL_OFF: float = 0.3  # railway.RAIL_HEIGHT_OFFSET と同じ
const BRIDGE_C: Color = Color(0.82, 0.34, 0.3)   # 赤い鉄橋
const PIER_C: Color = Color(0.6, 0.6, 0.63)      # 橋脚(コンクリ)
const STONE_C: Color = Color(0.62, 0.6, 0.56)    # 石
const BRICK_C: Color = Color(0.68, 0.42, 0.38)   # レンガ


func _ready() -> void:
	_build_bridge(1.85, 2.18, 6)   # 湖(-50,80)を渡る区間
	_build_tunnel(3.62, 3.98)      # 山B(-110,-70)を抜ける区間


# 線路面の Y(湖の上では水面以上に持ち上がる)
func _rail_y(x: float, z: float) -> float:
	var g: float = TerrainHeight.compute_height(x, z)
	var ld: float = Vector2(x - TerrainHeight.LAKE_POS.x, z - TerrainHeight.LAKE_POS.y).length()
	if ld < TerrainHeight.LAKE_RADIUS:
		return max(g, TerrainHeight.compute_water_y()) + RAIL_OFF
	return g + RAIL_OFF


# === 鉄橋 ===

func _build_bridge(t0: float, t1: float, n: int) -> void:
	# 橋脚
	for i in range(n + 1):
		var t: float = lerpf(t0, t1, float(i) / n)
		var p: Vector2 = Railway.ellipse_point(t)
		var ry: float = _rail_y(p.x, p.y)
		var gy: float = TerrainHeight.compute_height(p.x, p.y)
		var h: float = ry - gy
		if h > 0.6:
			_box(Vector3(1.6, h, 1.6), Vector3(p.x, gy + h * 0.5, p.y), 0.0, PIER_C)

	# 主桁・上弦・斜材(赤いトラス)
	for i in range(n):
		var ta: float = lerpf(t0, t1, float(i) / n)
		var tb: float = lerpf(t0, t1, float(i + 1) / n)
		var pa: Vector2 = Railway.ellipse_point(ta)
		var pb: Vector2 = Railway.ellipse_point(tb)
		var mid: Vector2 = (pa + pb) * 0.5
		var ry: float = _rail_y(mid.x, mid.y)
		var seg: float = pa.distance_to(pb)
		var tangent: Vector2 = (pb - pa).normalized()
		var yaw: float = atan2(tangent.x, tangent.y)
		var perp: Vector2 = Vector2(-tangent.y, tangent.x)
		for s in [-1.0, 1.0]:
			var gx: float = mid.x + perp.x * 1.1 * s
			var gz: float = mid.y + perp.y * 1.1 * s
			# 主桁(線路の下)
			_box(Vector3(0.3, 0.5, seg + 0.4), Vector3(gx, ry - 0.3, gz), yaw, BRIDGE_C)
			# 上弦(線路の上)
			_box(Vector3(0.24, 0.24, seg + 0.4), Vector3(gx, ry + 1.7, gz), yaw, BRIDGE_C)
			# 斜材
			_box(Vector3(0.16, 2.1, 0.16), Vector3(gx, ry + 0.7, gz), yaw, BRIDGE_C)


# === トンネル ===

func _build_tunnel(t0: float, t1: float) -> void:
	_portal(t0)
	_portal(t1)
	# かまぼこ天井(坑口の間を覆う)
	var m: int = 5
	for i in range(1, m):
		var t: float = lerpf(t0, t1, float(i) / m)
		var p: Vector2 = Railway.ellipse_point(t)
		var tangent: Vector2 = Railway.ellipse_tangent(t)
		var ry: float = _rail_y(p.x, p.y)
		var yaw: float = atan2(tangent.x, tangent.y)
		var perp: Vector2 = Vector2(-tangent.y, tangent.x)
		# 天井
		_box(Vector3(4.8, 0.5, 3.0), Vector3(p.x, ry + 3.3, p.y), yaw, STONE_C)
		# 側壁
		for s in [-1.0, 1.0]:
			_box(Vector3(0.5, 3.6, 3.0),
				Vector3(p.x + perp.x * 2.2 * s, ry + 1.7, p.y + perp.y * 2.2 * s), yaw, STONE_C)


func _portal(t: float) -> void:
	var p: Vector2 = Railway.ellipse_point(t)
	var tangent: Vector2 = Railway.ellipse_tangent(t)
	var ry: float = _rail_y(p.x, p.y)
	var root := Node3D.new()
	root.position = Vector3(p.x, ry, p.y)
	root.rotation.y = atan2(tangent.x, tangent.y)
	add_child(root)
	# 左右の柱(レンガ)
	for s in [-1.0, 1.0]:
		_box_local(root, Vector3(1.1, 4.6, 1.8), Vector3(s * 2.5, 2.0, 0), BRICK_C)
	# 上の梁
	_box_local(root, Vector3(6.2, 1.2, 1.8), Vector3(0, 4.3, 0), BRICK_C)
	# アーチ飾り(石)
	_box_local(root, Vector3(4.6, 0.6, 1.9), Vector3(0, 3.5, 0), STONE_C)


# === ヘルパー ===

func _box(size: Vector3, pos: Vector3, yaw: float, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(color)
	mi.position = pos
	mi.rotation.y = yaw
	add_child(mi)


func _box_local(root: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(color)
	mi.position = pos
	root.add_child(mi)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	m.metallic = 0.0
	return m
