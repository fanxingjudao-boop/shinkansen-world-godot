extends Node3D

# class_name DayNightCycle / TerrainHeight を CLI 起動でも参照できるよう preload
const DayNightCycle = preload("res://scripts/world/day_night_cycle.gd")
const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

# 夜空に光る星 12 個。
# 地形上のランダム位置に固定配置(seed で毎回同じ → 子供が「あの星」と認識できる)。
# 昼は visible=false で隠れ、夜だけ表示される。

const STAR_COUNT: int = 12
const STAR_SIZE: float = 0.55
const STAR_COLOR: Color = Color(1.0, 0.88, 0.4)
const STAR_PLACE_RADIUS: float = 150.0
const STAR_HEIGHT_MIN: float = 1.8
const STAR_HEIGHT_MAX: float = 2.3
const STAR_NIGHT_LO: float = 0.22   # この時刻より前 = 夜
const STAR_NIGHT_HI: float = 0.80   # この時刻より後 = 夜へ
const STAR_SPIN_SPEED: float = 0.5  # rad/s、ゆっくり回転して光る感じに

const STAR_SEED: int = 42

@export var day_night_path: NodePath
@export var terrain_path: NodePath

var _stars: Array[MeshInstance3D] = []
var _day_night: Node
var _terrain: Node


func _ready() -> void:
	if not day_night_path.is_empty():
		_day_night = get_node_or_null(day_night_path)
	if not terrain_path.is_empty():
		_terrain = get_node_or_null(terrain_path)

	seed(STAR_SEED)
	var mat: StandardMaterial3D = _make_star_material()
	for i in range(STAR_COUNT):
		var star := _make_star(mat)
		var x: float = randf_range(-STAR_PLACE_RADIUS, STAR_PLACE_RADIUS)
		var z: float = randf_range(-STAR_PLACE_RADIUS, STAR_PLACE_RADIUS)
		var ground_y: float = 0.0
		if _terrain and _terrain.has_method("height_at"):
			ground_y = _terrain.height_at(x, z)
		var y: float = ground_y + randf_range(STAR_HEIGHT_MIN, STAR_HEIGHT_MAX)
		star.position = Vector3(x, y, z)
		add_child(star)
		_stars.append(star)


func _process(delta: float) -> void:
	var night_visible: bool = _is_night_now()
	for star in _stars:
		star.visible = night_visible
		if night_visible:
			star.rotate_y(STAR_SPIN_SPEED * delta)


# === ロジック ===

func _is_night_now() -> bool:
	if _day_night == null:
		return true
	var t: float = _day_night.time_of_day
	return t < STAR_NIGHT_LO or t > STAR_NIGHT_HI


# === メッシュ構築 ===

func _make_star_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = STAR_COLOR
	mat.emission_enabled = true
	mat.emission = STAR_COLOR
	mat.emission_energy_multiplier = 2.5
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat


func _make_star(mat: StandardMaterial3D) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = STAR_SIZE
	sphere.height = STAR_SIZE * 2.0
	sphere.radial_segments = 6  # 8 面体っぽくキラキラ感
	sphere.rings = 4
	var mi := MeshInstance3D.new()
	mi.mesh = sphere
	mi.material_override = mat
	return mi
