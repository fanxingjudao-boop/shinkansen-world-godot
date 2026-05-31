extends MultiMeshInstance3D

# 草の房を MultiMesh(=1 draw call)で中央エリアに敷く。
# 大量の個別 MeshInstance を避けるため MultiMesh を使う(性能ガードレール)。
# 草原(高さ -1〜9m・湖の外)だけに生やし、向き・大きさをランダムにして自然に見せる。
# 揺れは grass.gdshader が TIME で行う(CPU 負荷なし)。
# ※ 中央(スポーン周辺)を覆う固定配置。iPad 実機の fps を見て BLADE_COUNT/FIELD_RADIUS を調整する。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")
const GRASS_SHADER = preload("res://assets/shaders/grass.gdshader")

const BLADE_COUNT: int = 1400      # 生成を試みる株数(草原外はスキップされ実数は減る)
const FIELD_RADIUS: float = 95.0   # 中央からこの半径に散らす
const BLADE_W: float = 0.5
const BLADE_H: float = 0.6
const GRASS_SEED: int = 1337       # 毎回同じ配置(チラつき防止)


func _ready() -> void:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(BLADE_W, BLADE_H)
	mesh.center_offset = Vector3(0, BLADE_H * 0.5, 0)  # 下端を y=0 にして地面から生える
	var mat := ShaderMaterial.new()
	mat.shader = GRASS_SHADER
	mesh.material = mat

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
		var s: float = randf_range(0.7, 1.3)
		t = t.scaled(Vector3(s, randf_range(0.8, 1.4), s))
		t.origin = Vector3(x, h, z)
		transforms.append(t)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in range(transforms.size()):
		mm.set_instance_transform(i, transforms[i])
	multimesh = mm
