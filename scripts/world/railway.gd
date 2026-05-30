extends Node3D

# class_name TerrainHeight は Godot エディタが project をスキャンするまで CLI で
# 認識されないため、preload で同名参照を作って両対応にする
const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

# 線路シーン。楕円形 Path3D を地形高さに追従させて配置し、
# レール 2 本(ArrayMesh 1 つに統合)と枕木(MultiMeshInstance3D)を構築する。
# 楕円の数値計算ロジックは static func で分離(Phase 2 の Train で再利用)。
# 湖の上では水面より上に線路を浮かせる(_ground_or_water_y)。

const TRACK_R_X: float = 135.0   # 楕円の X 半径(旧単一線路。Phase 2 で wp 化して再現)
const TRACK_R_Z: float = 105.0   # 楕円の Z 半径
const ELLIPSE_WP_COUNT: int = 64 # 楕円を再現する際のウェイポイント数(Catmull-Rom で滑らか)
const RAIL_OFFSET: float = 0.75  # 中心線からのレール ±ずれ
const RAIL_RADIUS: float = 0.14
const RAIL_CROSS_SEGMENTS: int = 8
const RAIL_HEIGHT_OFFSET: float = 0.3
const RAIL_SEG_SPACING: float = 3.8  # レール断面リングの弧長間隔(m)
const TIE_SIZE: Vector3 = Vector3(2.5, 0.18, 0.5)
const TIE_HEIGHT_OFFSET: float = 0.18
const TIE_SPACING: float = 3.8       # 枕木の弧長間隔(m)

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
	# Phase 2: 旧単一楕円を「ウェイポイント → Curve3D → レール/枕木」の一般経路で再現。
	# Phase 3 で複数ルート(RouteData)に拡張する土台。
	var curve := _build_curve_from_waypoints(_ellipse_waypoints(), [], true)
	_track_path.curve = curve
	_build_rails_for(curve, _rails_mesh, true)
	_build_ties_for(curve, _ties_multi, true)


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


# 楕円(旧単一線路)を再現するウェイポイント列(XZ, 重複なし)
func _ellipse_waypoints() -> Array:
	var wps: Array = []
	for i in range(ELLIPSE_WP_COUNT):
		var t: float = float(i) / float(ELLIPSE_WP_COUNT) * TAU
		wps.append(ellipse_point(t))
	return wps


# === 一般化: 任意のウェイポイント列 → Curve3D / レール / 枕木 ===

# XZ ウェイポイント列から滑らかな Curve3D を作る。
# Y は地形/水面に追従(_ground_or_water_y)+ RAIL_HEIGHT_OFFSET + elevations[i](立体交差用)。
# Catmull-Rom 風の接線(前点→次点 /6)で折れ線にせず連続曲線にする。loop=true で閉路。
func _build_curve_from_waypoints(wps: Array, elevations: Array, loop: bool) -> Curve3D:
	var pts: Array = []
	for i in range(wps.size()):
		var wp: Vector2 = wps[i]
		var e: float = elevations[i] if i < elevations.size() else 0.0
		var y: float = _ground_or_water_y(wp.x, wp.y) + RAIL_HEIGHT_OFFSET + e
		pts.append(Vector3(wp.x, y, wp.y))

	var curve := Curve3D.new()
	var n: int = pts.size()
	if n < 2:
		return curve
	var count: int = n + 1 if loop else n
	for i in range(count):
		var idx: int = i % n
		var prev_i: int
		var next_i: int
		if loop:
			prev_i = (i - 1 + n) % n
			next_i = (i + 1) % n
		else:
			prev_i = max(i - 1, 0)
			next_i = min(i + 1, n - 1)
		var tangent: Vector3 = (pts[next_i] - pts[prev_i]) * (1.0 / 6.0)
		curve.add_point(pts[idx], -tangent, tangent)
	return curve


# 弧長 off における水平接線(レール左右ずれ・枕木向きの基準)
func _curve_tangent(curve: Curve3D, off: float, length: float, loop: bool) -> Vector3:
	var eps: float = 0.5
	var a: float = off + eps
	var b: float = off - eps
	if loop:
		a = fposmod(a, length)
		b = fposmod(b, length)
	else:
		a = clampf(a, 0.0, length)
		b = clampf(b, 0.0, length)
	var t: Vector3 = curve.sample_baked(a, true) - curve.sample_baked(b, true)
	t.y = 0.0
	return t.normalized() if t.length() > 0.0001 else Vector3(0, 0, 1)


# 指定 Curve3D に沿ってレール 2 本(8 角形チューブ)を ArrayMesh で生成し mesh_inst に設定。
func _build_rails_for(curve: Curve3D, mesh_inst: MeshInstance3D, loop: bool) -> void:
	var length: float = curve.get_baked_length()
	if length <= 0.0:
		return
	var segs: int = max(int(length / RAIL_SEG_SPACING), 12)

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for rail_idx in range(2):
		var offset_sign: float = 1.0 if rail_idx == 0 else -1.0
		var base_idx: int = vertices.size()

		for ip in range(segs + 1):
			var off: float = length * float(ip) / float(segs)
			var center: Vector3 = curve.sample_baked(min(off, length), true)
			var tan3: Vector3 = _curve_tangent(curve, off, length, loop)
			var perp: Vector3 = Vector3(-tan3.z, 0.0, tan3.x)
			var rail_center: Vector3 = center + perp * (RAIL_OFFSET * offset_sign)

			var right3: Vector3 = tan3.cross(Vector3.UP).normalized()
			var up3: Vector3 = Vector3.UP
			for ic in range(RAIL_CROSS_SEGMENTS):
				var angle: float = float(ic) / float(RAIL_CROSS_SEGMENTS) * TAU
				var o: Vector3 = (up3 * sin(angle) + right3 * cos(angle)) * RAIL_RADIUS
				vertices.append(rail_center + o)
				normals.append(o.normalized())

		for ip in range(segs):
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
	mesh_inst.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = RAIL_COLOR
	mat.metallic = 0.6
	mat.roughness = 0.4
	mesh_inst.material_override = mat


# 指定 Curve3D に沿って枕木を MultiMesh で生成し mm_inst に設定。
func _build_ties_for(curve: Curve3D, mm_inst: MultiMeshInstance3D, loop: bool) -> void:
	var length: float = curve.get_baked_length()
	if length <= 0.0:
		return
	var count: int = max(int(length / TIE_SPACING), 1)

	var box := BoxMesh.new()
	box.size = TIE_SIZE
	var tie_mat := StandardMaterial3D.new()
	tie_mat.albedo_color = TIE_COLOR
	tie_mat.roughness = 0.85
	box.material = tie_mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = count

	# 枕木は線路面(curve Y)より少し下に(RAIL と TIE の高さオフセット差ぶん)
	var y_drop: float = RAIL_HEIGHT_OFFSET - TIE_HEIGHT_OFFSET
	for ip in range(count):
		var off: float = length * float(ip) / float(count)
		var center: Vector3 = curve.sample_baked(min(off, length), true)
		var tan3: Vector3 = _curve_tangent(curve, off, length, loop)
		# 枕木の長辺(BoxMesh の X 軸)を接線に直交させる
		var yaw: float = atan2(tan3.x, tan3.z)
		var origin := Vector3(center.x, center.y - y_drop, center.z)
		mm.set_instance_transform(ip, Transform3D(Basis(Vector3.UP, yaw), origin))

	mm_inst.multimesh = mm
