extends Node3D

# class_name TerrainHeight は Godot エディタが project をスキャンするまで CLI で
# 認識されないため、preload で同名参照を作って両対応にする
const TerrainHeight = preload("res://scripts/world/terrain_height.gd")
const RouteSpecs = preload("res://scripts/world/route_data.gd")

# 線路シーン。楕円形 Path3D を地形高さに追従させて配置し、
# レール 2 本(ArrayMesh 1 つに統合)と枕木(MultiMeshInstance3D)を構築する。
# 楕円の数値計算ロジックは static func で分離(Phase 2 の Train で再利用)。
# 湖の上では水面より上に線路を浮かせる(_ground_or_water_y)。

const RAIL_OFFSET: float = 0.75  # 中心線からのレール ±ずれ
const RAIL_RADIUS: float = 0.14
const RAIL_CROSS_SEGMENTS: int = 8
const RAIL_HEIGHT_OFFSET: float = 0.3
const RAIL_SEG_SPACING: float = 3.8  # レール断面リングの弧長間隔(m)
const TIE_SIZE: Vector3 = Vector3(2.6, 0.16, 0.34)  # 本格化: やや細く・実物に近い枕木
const TIE_HEIGHT_OFFSET: float = 0.18
const TIE_SPACING: float = 1.8       # 枕木の弧長間隔(m)。本格化で密に(旧 3.8)

const RAIL_COLOR: Color = Color(0.62, 0.63, 0.66)  # 鋼のメタリック灰
const TIE_COLOR: Color = Color(0.40, 0.27, 0.16)   # 茶(まくらぎ)
const PIER_COLOR: Color = Color(0.72, 0.72, 0.76)  # 高架・橋脚のコンクリ灰
const PIER_MIN_H: float = 2.5                       # この高さ以上で橋脚を立てる

# バラスト(砂利の道床)。本格的な線路の土台。1 ルート 1 枚の ArrayMesh(軽量)。
const BALLAST_WIDTH: float = 3.2
const BALLAST_DROP: float = 0.34     # レール面(curve Y)からの下げ
const BALLAST_COLOR: Color = Color(0.52, 0.49, 0.46)  # 砂利のグレー

@export var terrain_path: NodePath

var _terrain: Node

# slug -> { path: Path3D, length: float, start_offset: float, stops: Array }
var _routes: Dictionary = {}
var _routes_root: Node3D


func _ready() -> void:
	if not terrain_path.is_empty():
		_terrain = get_node_or_null(terrain_path)
	if _terrain == null or not _terrain.has_method("height_at"):
		push_warning("[Railway] terrain_path が未設定または height_at() を持たない")
		return
	# 旧単一楕円ノードは未使用に(空にしておく)。線路網は _routes_root 配下に動的生成。
	_routes_root = Node3D.new()
	_routes_root.name = "Routes"
	add_child(_routes_root)
	for spec in RouteSpecs.specs():
		_build_route(spec)


# 1 ルート分を構築: ウェイポイント → Curve3D → Path3D + レール + 枕木。
func _build_route(spec: Dictionary) -> void:
	var wps: Array = _ring_waypoints(spec)
	var elev_all: Array = []
	var elevation: float = spec.get("elevation", 0.0)
	if elevation != 0.0:
		for i in range(wps.size()):
			elev_all.append(elevation)
	var curve := _build_curve_from_waypoints(wps, elev_all, true)
	var length: float = curve.get_baked_length()

	var path := Path3D.new()
	path.name = String(spec["slug"])
	path.curve = curve
	_routes_root.add_child(path)

	# バラスト(砂利の道床)を まず敷く(レール・枕木より下)。
	var ballast := MeshInstance3D.new()
	_routes_root.add_child(ballast)
	_build_ballast_for(curve, ballast, true)

	var rails := MeshInstance3D.new()
	_routes_root.add_child(rails)
	_build_rails_for(curve, rails, true)

	var ties := MultiMeshInstance3D.new()
	_routes_root.add_child(ties)
	_build_ties_for(curve, ties, true)

	# 橋脚(柱)は立てない。改善さん要望: 柱が視界をさえぎって見えにくいため撤去。
	# 高架・水上の線路は支柱なしで宙に浮かせる(子供向けの「空にうかぶ せんろ」表現)。
	# ※ _build_piers_for() は将来のために残すが呼ばない。

	var stops: Array = []
	for s in spec.get("stops", []):
		stops.append({
			"offset": float(s["ratio"]) * length,
			"kind": String(s.get("kind", "dwell")),
			"seconds": float(s.get("seconds", 3.0)),
		})

	_routes[String(spec["slug"])] = {
		"path": path,
		"length": length,
		"start_offset": float(spec.get("start_ratio", 0.0)) * length,
		"stops": stops,
		"center": spec.get("center", Vector2.ZERO),
	}


# 楕円リングのウェイポイント列(XZ, 重複なし、rot_deg 回転)。
# wave_amp/wave_freq があれば半径を sin で波打たせる(本線の蛇行)。
func _ring_waypoints(spec: Dictionary) -> Array:
	var wps: Array = []
	var center: Vector2 = spec["center"]
	var rx: float = spec["rx"]
	var rz: float = spec["rz"]
	var rot: float = deg_to_rad(spec.get("rot_deg", 0.0))
	var n: int = int(spec.get("wp_count", 48))
	var amp: float = spec.get("wave_amp", 0.0)
	var freq: float = spec.get("wave_freq", 0.0)
	for i in range(n):
		var a: float = float(i) / float(n) * TAU
		var rmul: float = 1.0 + amp * sin(freq * a)
		var local := Vector2(rx * rmul * cos(a), rz * rmul * sin(a)).rotated(rot)
		wps.append(center + local)
	return wps


# 高架・水上区間の橋脚を自動生成(線路面が地面より PIER_MIN_H 以上高い所に柱を立てる)。
# 1 ルートぶんを 1 個の MultiMesh にまとめてドローコールを抑える。
func _build_piers_for(curve: Curve3D) -> void:
	var length: float = curve.get_baked_length()
	if length <= 0.0:
		return
	var step: float = 6.0
	var n: int = int(length / step)
	# まず橋脚が要る位置と高さを集める
	var xforms: Array = []
	for i in range(n):
		var off: float = float(i) * step
		var p: Vector3 = curve.sample_baked(off, true)
		var gy: float = _terrain.height_at(p.x, p.z)
		var h: float = p.y - RAIL_HEIGHT_OFFSET - gy  # レール下端〜地面の高さ
		if h > PIER_MIN_H:
			var basis := Basis().scaled(Vector3(1.2, h, 1.2))
			xforms.append(Transform3D(basis, Vector3(p.x, gy + h * 0.5, p.z)))
	if xforms.is_empty():
		return

	var box := BoxMesh.new()
	box.size = Vector3(1.0, 1.0, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = PIER_COLOR
	mat.roughness = 0.85
	box.material = mat

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = xforms.size()
	for i in range(xforms.size()):
		mm.set_instance_transform(i, xforms[i])

	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_routes_root.add_child(mmi)


# === 公開 API(Train が自分のルートを取得する) ===

# 編成 slug 専用の Path3D(Train が PathFollow3D を add_child する)
func get_route_path(slug: String) -> Path3D:
	if _routes.has(slug):
		return _routes[slug]["path"]
	return null

# 編成 slug の停車点 [{ offset(弧長), kind, seconds }]
func get_route_stops(slug: String) -> Array:
	if _routes.has(slug):
		return _routes[slug]["stops"]
	return []

# 編成 slug の初期位置(弧長)
func get_route_start_offset(slug: String) -> float:
	if _routes.has(slug):
		return _routes[slug]["start_offset"]
	return 0.0

# 編成 slug のルート一周の弧長(m)。分岐ワープで乗り換え先の弧長・速度換算に使う。
func get_route_length(slug: String) -> float:
	if _routes.has(slug):
		return _routes[slug]["length"]
	return 0.0

# ルート上 ratio(0..1)の { position(Vector3), forward(進行方向), outward(ループ中心と反対=外向き) }。
# 駅・名所などを線路脇に置くのに使う。
func get_route_sample(slug: String, ratio: float) -> Dictionary:
	if not _routes.has(slug):
		return {}
	var r: Dictionary = _routes[slug]
	var curve: Curve3D = r["path"].curve
	var length: float = r["length"]
	var off: float = fposmod(ratio * length, length)
	var pos: Vector3 = curve.sample_baked(off, true)
	var ahead: Vector3 = curve.sample_baked(fposmod(off + 0.5, length), true)
	var fwd: Vector3 = ahead - pos
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length() > 0.0001 else Vector3(0, 0, 1)
	var c: Vector2 = r["center"]
	var outward := Vector3(pos.x - c.x, 0.0, pos.z - c.y)
	outward = outward.normalized() if outward.length() > 0.0001 else Vector3(1, 0, 0)
	return { "position": pos, "forward": fwd, "outward": outward }


# === Godot 操作層 ===

# 線路の Y を取得。湖の上では水面以上に上げて「橋」のように渡す。
func _ground_or_water_y(x: float, z: float) -> float:
	var ground_y: float = _terrain.height_at(x, z)
	var lake_dist: float = Vector2(x - TerrainHeight.LAKE_POS.x, z - TerrainHeight.LAKE_POS.y).length()
	if lake_dist < TerrainHeight.LAKE_RADIUS:
		return max(ground_y, TerrainHeight.compute_water_y())
	return ground_y


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
	mat.metallic = 0.8
	mat.roughness = 0.28   # 本格化: 鋼らしい てかり
	mesh_inst.material_override = mat


# 指定 Curve3D に沿って バラスト(砂利の道床)の帯を ArrayMesh で生成し mesh_inst に設定。
# レール・枕木の下に やや幅広の グレーの帯を敷いて「本格的な線路」の土台にする。
func _build_ballast_for(curve: Curve3D, mesh_inst: MeshInstance3D, loop: bool) -> void:
	var length: float = curve.get_baked_length()
	if length <= 0.0:
		return
	var segs: int = max(int(length / RAIL_SEG_SPACING), 12)
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var half: float = BALLAST_WIDTH * 0.5
	for ip in range(segs + 1):
		var off: float = length * float(ip) / float(segs)
		var center: Vector3 = curve.sample_baked(min(off, length), true)
		var tan3: Vector3 = _curve_tangent(curve, off, length, loop)
		var perp: Vector3 = Vector3(-tan3.z, 0.0, tan3.x)
		var y: float = center.y - BALLAST_DROP
		verts.append(Vector3(center.x + perp.x * half, y, center.z + perp.z * half))   # left
		verts.append(Vector3(center.x - perp.x * half, y, center.z - perp.z * half))   # right
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	for ip in range(segs):
		var a: int = ip * 2
		var b: int = ip * 2 + 1
		var c2: int = (ip + 1) * 2
		var d: int = (ip + 1) * 2 + 1
		indices.append(a); indices.append(c2); indices.append(b)
		indices.append(b); indices.append(c2); indices.append(d)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_inst.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = BALLAST_COLOR
	mat.roughness = 0.98
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # 帯なので両面(巻き方向の事故回避)
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
