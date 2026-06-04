extends Node3D

# きらきら ふみいし(PLAYFUL_DETAILS B-6)。
# 地面の 決まった場所を 踏むと、足元が きらっと 光って 花/星が ぽぽっと 咲く。
# 「ここ踏むと 光る!」を 覚えて 何度も通る = 歩く こと自体が 楽しくなる。
#
# 設計(SPEC.md の方針):
# - Main 直下に 1 つ置く小さなノード(main.gd が起動時に生成)。
# - 何度でも 光る(再発火・クールダウンつき)。セーブしない・通信しない。
# - 必ず 良いことだけ(怖くない・地味でも「自分が 光らせた」感)。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const STEP_RANGE: float = 1.9     # この距離まで 近づく(踏む)と 光る
const COOLDOWN: float = 1.6       # 一度 光ったら 少し おいて また 光る

# ふみいしの場所(やさしい 一本道っぽく 点在)。色は ひとつずつ ちがう。
const SPOTS: Array = [
	{"pos": Vector2(6.0, 10.0),  "color": Color(1.0, 0.85, 0.4)},
	{"pos": Vector2(11.0, 16.0), "color": Color(1.0, 0.65, 0.78)},
	{"pos": Vector2(15.0, 23.0), "color": Color(0.6, 0.85, 1.0)},
	{"pos": Vector2(20.0, 29.0), "color": Color(0.7, 0.95, 0.7)},
	{"pos": Vector2(26.0, 34.0), "color": Color(0.85, 0.72, 1.0)},
	{"pos": Vector2(33.0, 38.0), "color": Color(1.0, 0.8, 0.5)},
	{"pos": Vector2(40.0, 41.0), "color": Color(1.0, 0.6, 0.7)},
]

var _player: Node3D
var _stones: Array = []      # [{root, mat, base_pos, color, cool}]
var _ready_done: bool = false


func _ready() -> void:
	_player = get_tree().root.find_child("Player", true, false) as Node3D
	for spot in SPOTS:
		_stones.append(_build_stone(spot))
	_ready_done = true


func _build_stone(spot: Dictionary) -> Dictionary:
	var pos: Vector2 = spot.pos
	var gy: float = TerrainHeight.compute_height(pos.x, pos.y)
	var root := Node3D.new()
	root.position = Vector3(pos.x, gy + 0.04, pos.y)
	add_child(root)
	# うっすら 光る まる(踏む目印)。ふだんは 控えめ、踏むと パッと 強くなる。
	var disc := CylinderMesh.new()
	disc.top_radius = 0.6
	disc.bottom_radius = 0.6
	disc.height = 0.05
	disc.radial_segments = 16
	var mi := MeshInstance3D.new()
	mi.mesh = disc
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(spot.color.r, spot.color.g, spot.color.b, 0.5)
	mat.emission_enabled = true
	mat.emission = spot.color
	mat.emission_energy_multiplier = 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	root.add_child(mi)
	return {"root": root, "mat": mat, "mi": mi, "color": spot.color, "cool": 0.0}


func _process(delta: float) -> void:
	if not _ready_done or _player == null:
		return
	var pp: Vector3 = _player.global_position
	for s in _stones:
		if s.cool > 0.0:
			s.cool -= delta
			continue
		if s.root.global_position.distance_to(pp) < STEP_RANGE:
			_sparkle_step(s)


func _sparkle_step(s: Dictionary) -> void:
	s.cool = COOLDOWN
	# 目印が ぱっと 明るく ふくらんで もどる。
	var mi: MeshInstance3D = s.mi
	var mat: StandardMaterial3D = s.mat
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(mi, "scale", Vector3(1.5, 1.0, 1.5), 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(mat, "emission_energy_multiplier", 3.0, 0.16)
	tw.chain().set_parallel(true)
	tw.tween_property(mi, "scale", Vector3.ONE, 0.5)
	tw.tween_property(mat, "emission_energy_multiplier", 0.6, 0.5)
	# 花/星が ぽぽっと 咲いて 舞い上がる。
	_spawn_bloom(s.root.global_position + Vector3(0, 0.2, 0), s.color)


func _spawn_bloom(pos: Vector3, color: Color) -> void:
	var p := GPUParticles3D.new()
	p.amount = 12
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 55.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 2.6
	pm.gravity = Vector3(0, -1.6, 0)
	pm.scale_min = 0.16
	pm.scale_max = 0.34
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.4
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)
