extends Node3D

# 遠くの空にかかる虹。7 色のアーチ。
# 半透明 + emission で、Glow と相まってふんわり光る。
# (将来 雨システムができたら「雨上がりに出る」連動にする。今は常時うっすら表示)

const COLORS: Array = [
	Color(1.0, 0.4, 0.4),   # あか
	Color(1.0, 0.65, 0.3),  # だいだい
	Color(1.0, 0.92, 0.35), # きいろ
	Color(0.45, 0.85, 0.45),# みどり
	Color(0.4, 0.72, 1.0),  # あお
	Color(0.45, 0.5, 0.9),  # あい
	Color(0.72, 0.5, 0.92), # むらさき
]

const RADIUS_BASE: float = 64.0
const BAND: float = 2.6


func _ready() -> void:
	for i in range(COLORS.size()):
		var torus := TorusMesh.new()
		torus.inner_radius = RADIUS_BASE + i * BAND
		torus.outer_radius = RADIUS_BASE + i * BAND + BAND
		torus.rings = 48
		torus.ring_segments = 8
		var mi := MeshInstance3D.new()
		mi.mesh = torus
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(COLORS[i].r, COLORS[i].g, COLORS[i].b, 0.4)
		mat.emission_enabled = true
		mat.emission = COLORS[i]
		mat.emission_energy_multiplier = 0.8
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		mi.rotate_x(PI * 0.5)  # 水平リング → 縦アーチに立てる
		add_child(mi)
