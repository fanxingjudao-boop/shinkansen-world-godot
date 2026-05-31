extends Node3D

# 線路の見どころ。Main 直下のノード。
# - トンネル: 「つばさ」ルート(山B のふもとをめぐる)の一区間にレンガ坑口+かまぼこ天井。
# - 鉄橋(湖)は railway の自動橋脚(線路が水上に出る所)で表現されるのでここでは作らない。
# 位置は railway のルートサンプル(線路上の点+進行方向)に沿わせる。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const STONE_C: Color = Color(0.62, 0.6, 0.56)    # 石(天井)
const BRICK_C: Color = Color(0.68, 0.42, 0.38)   # レンガ(坑口)

@export var railway_path: NodePath = NodePath("../Railway")
var _railway: Node


func _ready() -> void:
	_railway = get_node_or_null(railway_path)
	if _railway == null or not _railway.has_method("get_route_sample"):
		return
	# つばさルートの一区間にトンネル(山B を抜ける見立て)
	_build_tunnel_on("tsubasa", 0.55, 0.80)


# === トンネル ===

func _build_tunnel_on(slug: String, r0: float, r1: float) -> void:
	_portal_at(slug, r0)
	_portal_at(slug, r1)
	# かまぼこ天井(坑口の間を覆う)
	var m: int = 6
	for i in range(1, m):
		var rr: float = lerpf(r0, r1, float(i) / float(m))
		var s: Dictionary = _railway.get_route_sample(slug, rr)
		if s.is_empty():
			continue
		var pos: Vector3 = s["position"]
		var fwd: Vector3 = s["forward"]
		var yaw: float = atan2(fwd.x, fwd.z)
		var perp: Vector3 = fwd.cross(Vector3.UP).normalized()
		# 天井
		_box(Vector3(4.8, 0.5, 4.0), Vector3(pos.x, pos.y + 3.3, pos.z), yaw, STONE_C)
		# 側壁
		for sgn in [-1.0, 1.0]:
			_box(Vector3(0.5, 3.6, 4.0),
				Vector3(pos.x + perp.x * 2.2 * sgn, pos.y + 1.7, pos.z + perp.z * 2.2 * sgn),
				yaw, STONE_C)


func _portal_at(slug: String, ratio: float) -> void:
	var s: Dictionary = _railway.get_route_sample(slug, ratio)
	if s.is_empty():
		return
	var pos: Vector3 = s["position"]
	var fwd: Vector3 = s["forward"]
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = atan2(fwd.x, fwd.z)
	add_child(root)
	# 左右の柱(レンガ)
	for sgn in [-1.0, 1.0]:
		_box_local(root, Vector3(1.1, 4.6, 1.8), Vector3(sgn * 2.5, 2.0, 0), BRICK_C)
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
