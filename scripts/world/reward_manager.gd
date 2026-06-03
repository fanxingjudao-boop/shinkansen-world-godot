extends Node3D

# 集めた ごほうび を まとめて司る(Main 直下 `RewardManager`)。
# - げんき → プレイヤーの speed を 永続的に少しずつ上げる(上限つき=怖くない)。
# - ほし   → 5こ毎に お祝い(通知+キラキラ+音+ほしのき が弾む)。
#            スポーン前方の「ほしのき」の 実が 集めた数だけ 光る(トロフィー)。
# どちらも GameState の値(energy / star_count)から都度計算=セーブ項目を増やさない。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const ENERGY_STEP: float = 0.03       # げんき 1こ で +3%
const ENERGY_MAX_BONUS: float = 0.5   # 上限 +50%(1.5倍)
const MILESTONE: int = 5              # ほし 5こ毎に お祝い
const STAR_TREE_POS := Vector2(6.0, -14.0)   # スポーン前方の見える所
const FRUIT_COUNT: int = 20           # ほしのきの 実(ほし)の数

const TRUNK_C := Color(0.5, 0.36, 0.24)
const LEAF_C := Color(0.36, 0.62, 0.4)
const LEAF_C2 := Color(0.46, 0.74, 0.46)
const FRUIT_DIM := Color(0.62, 0.6, 0.5)     # まだ の 実(くすんだ色)
const FRUIT_LIT := Color(1.0, 0.85, 0.3)     # 光った 実(金のほし)

var _player: Node3D
var _gs: Node
var _hud: Node
var _sfx: AudioStreamPlayer

var _fruits: Array = []               # [{mi, mat}] ほしのきの 実
var _topper: MeshInstance3D
var _tree_root: Node3D
var _last_milestone: int = 0          # これまで祝った 5の倍数(読込分は祝わない)
var _ready_done: bool = false


func _ready() -> void:
	var root := get_tree().root
	_player = root.find_child("Player", true, false) as Node3D
	_gs = root.find_child("GameState", true, false)
	_hud = root.find_child("TouchHUD", true, false)
	_ensure_audio()
	_build_star_tree()
	if _gs and _gs.has_signal("changed"):
		_gs.changed.connect(_on_changed)
	# セーブ読込が済んだ後に 一度 静かに同期(お祝いはしない)。
	call_deferred("_initial_sync")


func _initial_sync() -> void:
	_apply_energy_speed()
	if _gs:
		_last_milestone = int(_gs.star_count) / MILESTONE   # 読込分は祝わない
	_update_tree()
	_ready_done = true


func _on_changed() -> void:
	_apply_energy_speed()
	_update_tree()
	if not _ready_done:
		return
	_check_star_milestone()


# === げんき → スピードアップ(永続・上限つき) ===

func _apply_energy_speed() -> void:
	if _player == null or _gs == null:
		return
	var bonus: float = min(float(_gs.energy) * ENERGY_STEP, ENERGY_MAX_BONUS)
	_player.set("energy_speed_scale", 1.0 + bonus)


# === ほし → お祝い ===

func _check_star_milestone() -> void:
	if _gs == null:
		return
	var m: int = int(_gs.star_count) / MILESTONE
	if m <= _last_milestone:
		return
	_last_milestone = m
	if _hud and _hud.has_method("show_notice"):
		_hud.show_notice("ほし %dこ オメデトウ!" % (m * MILESTONE))
	if _tree_root:
		_spawn_burst(_tree_root.global_position + Vector3(0, 5.5, 0), FRUIT_LIT)
		_bounce_tree()
	if _sfx:
		_sfx.play()


func _bounce_tree() -> void:
	if _tree_root == null:
		return
	var tw := create_tween()
	tw.tween_property(_tree_root, "scale", Vector3(1.12, 1.18, 1.12), 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_tree_root, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# === ほしのき ===

func _build_star_tree() -> void:
	_tree_root = Node3D.new()
	add_child(_tree_root)
	var gy: float = TerrainHeight.compute_height(STAR_TREE_POS.x, STAR_TREE_POS.y)
	_tree_root.global_position = Vector3(STAR_TREE_POS.x, gy, STAR_TREE_POS.y)
	# 幹
	_lcyl(_tree_root, 0.45, 3.2, Vector3(0, 1.6, 0), TRUNK_C, 10)
	# 葉(三段の まるい かたまり)
	for k in range(3):
		var ry: float = 3.4 + float(k) * 1.1
		var rr: float = 2.6 - float(k) * 0.5
		_lsphere(_tree_root, rr, Vector3(0, ry, 0), LEAF_C if k % 2 == 0 else LEAF_C2).scale = Vector3(1.0, 0.8, 1.0)
	# 実(ほし)を 葉のまわりに ぐるりと配置
	_fruits.clear()
	for i in range(FRUIT_COUNT):
		var a: float = float(i) / float(FRUIT_COUNT) * TAU * 2.0
		var tier: int = i % 3
		var ry: float = 3.6 + float(tier) * 1.0
		var rr: float = 2.3 - float(tier) * 0.45
		var pos := Vector3(cos(a) * rr, ry + sin(a * 1.7) * 0.3, sin(a) * rr)
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = 0.26
		s.height = 0.52
		s.radial_segments = 10
		s.rings = 6
		mi.mesh = s
		var mat := StandardMaterial3D.new()
		mat.albedo_color = FRUIT_DIM
		mat.roughness = 0.6
		mi.material_override = mat
		mi.position = pos
		_tree_root.add_child(mi)
		_fruits.append({"mi": mi, "mat": mat})
	# てっぺんの ほし(全部 集めると 光る)
	_topper = _lemit(_tree_root, 0.5, Vector3(0, 6.4, 0), FRUIT_DIM)
	_topper.scale = Vector3(1.0, 1.0, 0.5)
	var tm := _topper.material_override as StandardMaterial3D
	tm.emission_enabled = false
	tm.albedo_color = FRUIT_DIM


func _update_tree() -> void:
	if _gs == null or _fruits.is_empty():
		return
	var n: int = int(_gs.star_count)
	for i in range(_fruits.size()):
		var mat: StandardMaterial3D = _fruits[i]["mat"]
		if i < n:
			mat.albedo_color = FRUIT_LIT
			mat.emission_enabled = true
			mat.emission = FRUIT_LIT
			mat.emission_energy_multiplier = 0.8
		else:
			mat.albedo_color = FRUIT_DIM
			mat.emission_enabled = false
	# 全部 集めたら てっぺんの ほしも 光る
	if _topper:
		var tm := _topper.material_override as StandardMaterial3D
		if n >= _fruits.size():
			tm.albedo_color = FRUIT_LIT
			tm.emission_enabled = true
			tm.emission = FRUIT_LIT
			tm.emission_energy_multiplier = 1.0
		else:
			tm.albedo_color = FRUIT_DIM
			tm.emission_enabled = false


# === キラキラ / 音 ===

func _spawn_burst(pos: Vector3, color: Color) -> void:
	var p := GPUParticles3D.new()
	p.amount = 20
	p.lifetime = 0.8
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 3.6
	pm.gravity = Vector3(0, -2.0, 0)
	pm.scale_min = 0.15
	pm.scale_max = 0.4
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.36, 0.36)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


func _ensure_audio() -> void:
	if _sfx == null:
		_sfx = AudioStreamPlayer.new()
		_sfx.stream = _make_tone(784.0, 1318.0, 0.3)   # やさしい お祝い(上がる)
		_sfx.volume_db = -5.0
		add_child(_sfx)


func _make_tone(freq_a: float, freq_b: float, dur: float) -> AudioStreamWAV:
	var rate: int = 22050
	var n: int = int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / float(rate)
		var prog: float = float(i) / float(n)
		var freq: float = freq_a if prog < 0.5 else freq_b
		var env: float = sin(prog * PI)
		var s: float = sin(TAU * freq * t) * env * 0.5
		data.encode_s16(i * 2, int(clamp(s, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = data
	return wav


# === メッシュ ヘルパー ===

func _lcyl(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, segs: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = segs
	mi.mesh = c
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.8
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _lsphere(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 14
	s.rings = 7
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _lemit(parent: Node3D, radius: float, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 14
	s.rings = 7
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.8
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi
