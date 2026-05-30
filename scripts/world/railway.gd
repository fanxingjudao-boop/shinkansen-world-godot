extends Node3D

# class_name TerrainHeight は Godot エディタが project をスキャンするまで CLI で
# 認識されないため、preload で同名参照を作って両対応にする
const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

# 線路シーン。楕円形 Path3D を地形高さに追従させて配置し、
# レール 2 本(ArrayMesh 1 つに統合)と枕木(MultiMeshInstance3D)を構築する。
# 楕円の数値計算ロジックは static func で分離(Phase 2 の Train で再利用)。
# 湖の上では水面より上に線路を浮かせる(_ground_or_water_y)。

const TRACK_R_X: float = 135.0   # 楕円の X 半径(オープンワールド化で拡大)
const TRACK_R_Z: float = 105.0   # 楕円の Z 半径
const TRACK_SEGMENTS: int = 200  # 分割数(拡大に合わせ枕木間隔を維持)
const RAIL_OFFSET: float = 0.75  # 中心線からのレール ±ずれ
const RAIL_RADIUS: float = 0.14
const RAIL_CROSS_SEGMENTS: int = 8
const RAIL_HEIGHT_OFFSET: float = 0.3
const TIE_SIZE: Vector3 = Vector3(2.5, 0.18, 0.5)
const TIE_HEIGHT_OFFSET: float = 0.18

const RAIL_COLOR: Color = Color(0.6, 0.6, 0.6)    # #999999 メタリック灰
const TIE_COLOR: Color = Color(0.42, 0.27, 0.14)  # #6b4423 茶

@export var terrain_path: NodePath

var _terrain: Node
@onready var _track_path: Path3D = $TrackPath
@onready var _rails_mesh: MeshInstance3D = $Rails
@onready var _ties_multi: MultiMeshInstance3D = $Ties


func _ready() -> void:
	if not terrain_path.is_empty():
		_terrain = get_node_or_null(terrain_path)
	if _terrain == null or not _terrain.has_method("height_at"):
		push_warning("[Railway] terrain_path が未設定または height_at() を持たない")
		return
	_build_track_path()
	_build_rails()
	_build_ties()


# 公開 API: 楕円トラックの Path3D ノードを返す(Train が PathFollow3D を add_child するため)
func get_track_path() -> Path3D:
	return _track_path


# === ロジック層(static、純粋関数) ===

# 楕円トラック上、パラメータ t (0..TAU) の点の (x, z)
static func ellipse_point(t: float) -> Vector2:
	return Vector2(cos(t) * TRACK_R_X, sin(t) * TRACK_R_Z)


# 楕円トラック上、パラメータ t の接線(正規化済み、(x, z))
static func ellipse_tangent(t: float) -> Vector2:
	return Vector2(-sin(t) * TRACK_R_X, cos(t) * TRACK_R_Z).normalized()


# === Godot 操作層 ===

# 線路の Y を取得。湖の上では水面以上に上げて「橋」のように渡す。
func _ground_or_water_y(x: float, z: float) -> float:
	var ground_y: float = _terrain.height_at(x, z)
	var lake_dist: float = Vector2(x - TerrainHeight.LAKE_POS.x, z - TerrainHeight.LAKE_POS.y).length()
	if lake_dist < TerrainHeight.LAKE_RADIUS:
		return max(ground_y, TerrainHeight.compute_water_y())
	return ground_y


func _build_track_path() -> void:
	var curve := Curve3D.new()
	for ip in range(TRACK_SEGMENTS + 1):
		var t: float = float(ip) / float(TRACK_SEGMENTS) * TAU
		var p: Vector2 = ellipse_point(t)
		var y: float = _ground_or_water_y(p.x, p.y) + RAIL_HEIGHT_OFFSET
		curve.add_point(Vector3(p.x, y, p.y))
	_track_path.curve = curve


func _build_rails() -> void:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for rail_idx in range(2):
		var offset_sign: float = 1.0 if rail_idx == 0 else -1.0
		var base_idx: int = vertices.size()

		for ip in range(TRACK_SEGMENTS + 1):
			var t: float = float(ip) / float(TRACK_SEGMENTS) * TAU
			var center: Vector2 = ellipse_point(t)
			var tangent2: Vector2 = ellipse_tangent(t)

			var rail_y: float = _ground_or_water_y(center.x, center.y) + RAIL_HEIGHT_OFFSET

			# tangent に直交する水平方向(レールの左右ずれ)
			var perp: Vector2 = Vector2(-tangent2.y, tangent2.x)
			var rail_center := Vector3(
				center.x + perp.x * RAIL_OFFSET * offset_sign,
				rail_y,
				center.y + perp.y * RAIL_OFFSET * offset_sign
			)

			# 断面 8 角形の各頂点(tangent に垂直な平面上)
			var tangent3 := Vector3(tangent2.x, 0.0, tangent2.y)
			var right3: Vector3 = tangent3.cross(Vector3.UP).normalized()
			var up3: Vector3 = Vector3.UP
			for ic in range(RAIL_CROSS_SEGMENTS):
				var angle: float = float(ic) / float(RAIL_CROSS_SEGMENTS) * TAU
				var off: Vector3 = (up3 * sin(angle) + right3 * cos(angle)) * RAIL_RADIUS
				vertices.append(rail_center + off)
				normals.append(off.normalized())

		# インデックス(円柱の側面を三角形分割)
		for ip in range(TRACK_SEGMENTS):
			for ic in range(RAIL_CROSS_SEGMENTS):
				var ic_next: int = (ic + 1) % RAIL_CROSS_SEGMENTS
				var i00: int = base_idx + ip * RAIL_CROSS_SEGMENTS + ic
				var i01: int = base_idx + ip * RAIL_CROSS_SEGMENTS + ic_next
				var i10: int = base_idx + (ip + 1) * RAIL_CROSS_SEGMENTS + ic
				var i11: int = base_idx + (ip + 1) * RAIL_CROSS_SEGMENTS + ic_next
				indices.append(i00); indices.append(i10); indices.append(i01)
				indices.append(i01); indices.append(i10); indices.append(i11)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_rails_mesh.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = RAIL_COLOR
	mat.metallic = 0.6
	mat.roughness = 0.4
	_rails_mesh.material_override = mat


func _build_ties() -> void:
	var box := BoxMesh.new()
	box.size = TIE_SIZE

	var tie_mat := StandardMaterial3D.new()
	tie_mat.albedo_color = TIE_COLOR
	tie_mat.roughness = 0.85
	box.material = tie_mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = TRACK_SEGMENTS

	for ip in range(TRACK_SEGMENTS):
		var t: float = float(ip) / float(TRACK_SEGMENTS) * TAU
		var center: Vector2 = ellipse_point(t)
		var tangent2: Vector2 = ellipse_tangent(t)
		var tie_y: float = _ground_or_water_y(center.x, center.y) + TIE_HEIGHT_OFFSET

		# 枕木の長辺(BoxMesh の X 軸 = 2.5m)を線路の接線に直交させる。
		# atan2(tangent.x, tangent.z) で接線方向の yaw が取れて、それで Basis を作ると
		# ローカル X が接線と直交する向きになる(過去に + PI*0.5 を入れていたが
		# それだと枕木がレールと平行=縦になってしまっていた)
		var yaw: float = atan2(tangent2.x, tangent2.y)
		var basis := Basis(Vector3.UP, yaw)
		var origin := Vector3(center.x, tie_y, center.y)
		mm.set_instance_transform(ip, Transform3D(basis, origin))

	_ties_multi.multimesh = mm
