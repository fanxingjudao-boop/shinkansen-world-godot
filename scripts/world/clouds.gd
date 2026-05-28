extends Node3D

# 雲 18 個を生成し、空をゆっくり水平に流す。
# 各雲は 6 個の SphereMesh の集合(Three.js プロトタイプの makeCloud 移植)。
# マテリアルは UNSHADED で常に白(ライト変化の影響を受けない)。

const CLOUD_COUNT: int = 18
const CLOUD_HEIGHT_MIN: float = 35.0
const CLOUD_HEIGHT_MAX: float = 60.0
const CLOUD_X_RANGE: float = 220.0
const CLOUD_Z_RANGE: float = 200.0
const CLOUD_SPEED_MIN: float = 0.6
const CLOUD_SPEED_MAX: float = 1.2
const CLOUD_SPHERE_COUNT: int = 6
const CLOUD_SPHERE_RADIUS_BASE: float = 2.2
const CLOUD_SCALE_MIN: float = 0.9
const CLOUD_SCALE_MAX: float = 1.5
const CLOUD_SQUASH_Y: float = 0.55  # 雲を Y 方向に潰す(平たい形)

const CLOUD_SEED: int = 7  # 配置を毎回同じに(子供が「あの雲」と認識できる)

var _clouds: Array[Node3D] = []
var _speeds: Array[float] = []
var _shared_material: StandardMaterial3D


func _ready() -> void:
	seed(CLOUD_SEED)
	_shared_material = _make_cloud_material()
	for i in range(CLOUD_COUNT):
		var cloud := _make_cloud()
		cloud.position = Vector3(
			randf_range(-CLOUD_X_RANGE, CLOUD_X_RANGE),
			randf_range(CLOUD_HEIGHT_MIN, CLOUD_HEIGHT_MAX),
			randf_range(-CLOUD_Z_RANGE, CLOUD_Z_RANGE)
		)
		var s: float = randf_range(CLOUD_SCALE_MIN, CLOUD_SCALE_MAX)
		cloud.scale = Vector3(s, s * CLOUD_SQUASH_Y, s)
		add_child(cloud)
		_clouds.append(cloud)
		_speeds.append(randf_range(CLOUD_SPEED_MIN, CLOUD_SPEED_MAX))


func _process(delta: float) -> void:
	for i in range(_clouds.size()):
		var cloud := _clouds[i]
		cloud.position.x += _speeds[i] * delta
		if cloud.position.x > CLOUD_X_RANGE:
			cloud.position.x = -CLOUD_X_RANGE


# === メッシュ構築 ===

func _make_cloud_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 1, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _make_cloud() -> Node3D:
	var cloud := Node3D.new()
	for c in range(CLOUD_SPHERE_COUNT):
		var sphere := SphereMesh.new()
		var r: float = CLOUD_SPHERE_RADIUS_BASE + randf()
		sphere.radius = r
		sphere.height = r * 2.0
		sphere.radial_segments = 8
		sphere.rings = 6
		var mi := MeshInstance3D.new()
		mi.mesh = sphere
		mi.material_override = _shared_material
		mi.position = Vector3(
			randf_range(-2.5, 2.5),
			randf_range(-0.6, 0.6),
			randf_range(-2.5, 2.5)
		)
		cloud.add_child(mi)
	return cloud
