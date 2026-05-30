extends GPUParticles3D

# 夜のホタル。プレイヤーの周りに黄緑の光がふわふわ浮かぶ(夜だけ)。
# 昼は emitting=false で消える。Glow と相乗して優しく光る。

const DayNightCycle = preload("res://scripts/world/day_night_cycle.gd")

const NIGHT_LO: float = 0.22
const NIGHT_HI: float = 0.80

@export var day_night_path: NodePath

var _dn: Node


func _ready() -> void:
	_dn = get_node_or_null(day_night_path)
	_build()
	emitting = false


func _process(_delta: float) -> void:
	var is_night: bool = true
	if _dn:
		var t: float = _dn.time_of_day
		is_night = t < NIGHT_LO or t > NIGHT_HI
	emitting = is_night


func _build() -> void:
	amount = 28
	lifetime = 5.0
	preprocess = 2.0
	randomness = 1.0
	local_coords = false

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 3, 14)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.gravity = Vector3.ZERO
	pm.initial_velocity_min = 0.15
	pm.initial_velocity_max = 0.5
	pm.scale_min = 0.5
	pm.scale_max = 1.0
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.4
	pm.turbulence_noise_scale = 1.2
	# ほんのり点滅(alpha が時間で揺れる)
	var ag := Gradient.new()
	ag.set_color(0, Color(0.7, 1.0, 0.4, 0.0))
	ag.add_point(0.2, Color(0.8, 1.0, 0.5, 1.0))
	ag.add_point(0.8, Color(0.8, 1.0, 0.5, 1.0))
	ag.set_color(ag.get_point_count() - 1, Color(0.7, 1.0, 0.4, 0.0))
	var agt := GradientTexture1D.new()
	agt.gradient = ag
	pm.color_ramp = agt
	process_material = pm

	var qm := QuadMesh.new()
	qm.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 1.0, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(0.7, 1.0, 0.4)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	draw_pass_1 = qm
