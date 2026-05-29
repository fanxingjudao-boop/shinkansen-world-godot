extends StaticBody3D

# 地形シーン。ArrayMesh で起伏ある地形を動的生成、HeightMapShape3D で衝突を提供。
# 高さ・色のロジックは TerrainHeight(scripts/world/terrain_height.gd)に分離。

const COLLISION_SAMPLE_STEP: float = 2.0  # コリジョンの格子間隔(視覚 120 分割とは独立)

@onready var _terrain_mesh: MeshInstance3D = $TerrainMesh
@onready var _terrain_collision: CollisionShape3D = $TerrainCollision
@onready var _lake_mesh: MeshInstance3D = $LakeMesh


func _ready() -> void:
	_generate_terrain()
	_generate_lake()


# 任意座標の地形高さを取得する公開 API(Railway 等から呼ばれる)。
func height_at(x: float, z: float) -> float:
	return TerrainHeight.compute_height(x, z)


# === Godot 操作層 ===

func _generate_terrain() -> void:
	var arrays: Array = _build_mesh_arrays()
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_terrain_mesh.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# vertex_color_is_srgb は Godot の頂点カラーが sRGB か Linear かのヒント。
	# Compatibility レンダラーで挙動が不安定なため false(Linear 扱い)で渡す
	mat.vertex_color_is_srgb = false
	mat.roughness = 0.9
	mat.metallic = 0.0
	_terrain_mesh.material_override = mat

	var shape: HeightMapShape3D = _build_height_shape()
	_terrain_collision.shape = shape
	# HeightMapShape3D は格子間隔 1.0 固定なので、scale で実際の間隔を吸収
	_terrain_collision.scale = Vector3(COLLISION_SAMPLE_STEP, 1.0, COLLISION_SAMPLE_STEP)


func _generate_lake() -> void:
	var lake_pos: Vector2 = TerrainHeight.LAKE_POS
	# 湖の谷は中心が約 -3.5m、縁が約 +1.7m。
	# 水面を縁から少し下に置いて湖らしく(railway.gd と共有の compute_water_y)
	var lake_y: float = TerrainHeight.compute_water_y()
	_lake_mesh.transform.origin = Vector3(lake_pos.x, lake_y, lake_pos.y)

	# PlaneMesh + subdivide で水面メッシュを作る(自作 ArrayMesh より確実)
	# 湖周囲の山が壁になって余分な部分は隠れるので、少し大きめの正方形で OK
	var plane := PlaneMesh.new()
	plane.size = Vector2(TerrainHeight.LAKE_RADIUS * 2 + 4, TerrainHeight.LAKE_RADIUS * 2 + 4)
	plane.subdivide_width = 32
	plane.subdivide_depth = 32
	_lake_mesh.mesh = plane
	_lake_mesh.material_override = _load_water_material()


# === メッシュ構築(頂点・色・法線・インデックスを直接組み立て) ===

func _build_mesh_arrays() -> Array:
	var subdiv: int = TerrainHeight.MESH_SUBDIV
	var size: float = TerrainHeight.WORLD_SIZE
	var step: float = size / float(subdiv)
	var vert_per_side: int = subdiv + 1
	var vert_count: int = vert_per_side * vert_per_side

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	vertices.resize(vert_count)
	normals.resize(vert_count)
	colors.resize(vert_count)

	for iz in range(vert_per_side):
		for ix in range(vert_per_side):
			var x: float = -size * 0.5 + float(ix) * step
			var z: float = -size * 0.5 + float(iz) * step
			var y: float = TerrainHeight.compute_height(x, z)
			var idx: int = iz * vert_per_side + ix
			vertices[idx] = Vector3(x, y, z)
			colors[idx] = TerrainHeight.compute_vertex_color(y)
			normals[idx] = _normal_at(x, z, step)

	# 各セルを 2 三角形に分割(CCW = 上から見て反時計回り、Godot は CCW が表面)
	for iz in range(subdiv):
		for ix in range(subdiv):
			var i0: int = iz * vert_per_side + ix
			var i1: int = i0 + 1
			var i2: int = i0 + vert_per_side
			var i3: int = i2 + 1
			indices.append(i0); indices.append(i1); indices.append(i2)
			indices.append(i1); indices.append(i3); indices.append(i2)

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _build_height_shape() -> HeightMapShape3D:
	var size: float = TerrainHeight.WORLD_SIZE
	var sample_count: int = int(size / COLLISION_SAMPLE_STEP) + 1

	var data := PackedFloat32Array()
	data.resize(sample_count * sample_count)
	for iz in range(sample_count):
		for ix in range(sample_count):
			var x: float = -size * 0.5 + float(ix) * COLLISION_SAMPLE_STEP
			var z: float = -size * 0.5 + float(iz) * COLLISION_SAMPLE_STEP
			data[iz * sample_count + ix] = TerrainHeight.compute_height(x, z)

	var shape := HeightMapShape3D.new()
	shape.map_width = sample_count
	shape.map_depth = sample_count
	shape.map_data = data
	return shape


# 湖の water シェーダーマテリアル(波 + スペキュラ反射)を生成
static func _load_water_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/water.gdshader")
	return mat


# 中心差分で法線を求める(地形の勾配ベース、ライティングが滑らかになる)
static func _normal_at(x: float, z: float, step: float) -> Vector3:
	var h_l: float = TerrainHeight.compute_height(x - step, z)
	var h_r: float = TerrainHeight.compute_height(x + step, z)
	var h_d: float = TerrainHeight.compute_height(x, z - step)
	var h_u: float = TerrainHeight.compute_height(x, z + step)
	var nx: float = (h_l - h_r) / (2.0 * step)
	var nz: float = (h_d - h_u) / (2.0 * step)
	return Vector3(nx, 1.0, nz).normalized()
