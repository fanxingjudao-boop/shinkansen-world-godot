extends MultiMeshInstance3D

# 草の房を MultiMesh(=1 draw call)で草原に敷く。
# 大量の個別 MeshInstance を避けるため MultiMesh を使う(性能ガードレール)。
# メッシュは X 字クロス(2枚直交)なので、どの向きから見ても草が見えて立体的=リアル。
# 草原(高さ -1〜9m・湖の外)だけに生やし、向き・大きさ・色をランダムにして自然に見せる。
# 揺れは grass.gdshader が TIME で行う(CPU 負荷なし)。
# ※ 範囲を広げて「まんべんなく」生やす。iPad 実機の fps を見て BLADE_COUNT/FIELD_RADIUS を調整する。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")
const GRASS_SHADER = preload("res://assets/shaders/grass.gdshader")

const BLADE_COUNT: int = 4200      # 生成を試みる株数(草原外はスキップされ実数は減る)
const FIELD_RADIUS: float = 170.0  # 中央からこの半径に散らす(広めにまんべんなく)
const BLADE_W: float = 0.42
const BLADE_H: float = 0.62
const GRASS_SEED: int = 1337       # 毎回同じ配置(チラつき防止)


func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mat.set_shader_parameter("blade_height", BLADE_H)
	var mesh := _build_blade_mesh()
	mesh.surface_set_material(0, mat)

	var transforms: Array = []
	seed(GRASS_SEED)
	for i in range(BLADE_COUNT):
		var ang: float = randf() * TAU
		var r: float = sqrt(randf()) * FIELD_RADIUS  # 一様分布
		var x: float = cos(ang) * r
		var z: float = sin(ang) * r
		var h: float = TerrainHeight.compute_height(x, z)
		if h < -1.0 or h > 9.0:
			continue  # 砂浜・雪山には生やさない(草原だけ)
		var lake_d: float = Vector2(x - TerrainHeight.LAKE_POS.x, z - TerrainHeight.LAKE_POS.y).length()
		if lake_d < TerrainHeight.LAKE_RADIUS:
			continue  # 湖の上はスキップ
		var t := Transform3D()
		t = t.rotated(Vector3.UP, randf() * TAU)
		var s: float = randf_range(0.7, 1.35)
		t = t.scaled(Vector3(s, randf_range(0.8, 1.5), s))
		t.origin = Vector3(x, h, z)
		transforms.append(t)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	multimesh = mm


# X 字クロス(2枚の直交クアッド)。下端を y=0 にして地面から生やす。
# cull_disabled なので両面見える(裏表の向きは気にしない)。
func _build_blade_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw: float = BLADE_W * 0.5
	# 板1(X方向の幅)
	_add_quad(st, Vector3(-hw, 0.0, 0.0), Vector3(hw, 0.0, 0.0), Vector3(hw, BLADE_H, 0.0), Vector3(-hw, BLADE_H, 0.0))
	# 板2(Z方向の幅・直交)
	_add_quad(st, Vector3(0.0, 0.0, -hw), Vector3(0.0, 0.0, hw), Vector3(0.0, BLADE_H, hw), Vector3(0.0, BLADE_H, -hw))
	st.generate_normals()
	return st.commit()


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(a)
	st.set_uv(Vector2(1.0, 1.0)); st.add_vertex(b)
	st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(c)
	st.set_uv(Vector2(0.0, 1.0)); st.add_vertex(a)
	st.set_uv(Vector2(1.0, 0.0)); st.add_vertex(c)
	st.set_uv(Vector2(0.0, 0.0)); st.add_vertex(d)
