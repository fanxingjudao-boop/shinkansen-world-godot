extends Node3D

# かくれんぼ動物(PLAYFUL_DETAILS B-1)。
# 地上の あちこちに ちいさな子が こっそり 隠れている。近づくと「みつけた!」と
# うれしそうに ぴょこんと 飛び出す。みつけた数は セーブして 図鑑に「かくれんぼ」進捗を出す。
#
# 設計(SPEC.md の方針):
# - 巨大マネージャを作らず、Main 直下に 1 つだけ置く小さなノード(main.gd が生成)。
# - 見た目は player/animal と同じく スクリプト生成 + リムライト。3D ファイル不要。
# - 怖くない: 飛び出しは やさしい上向きバウンス + 明るい音。急に大きい音/暗いは無し。
# - 失敗なし: みつけられなくても損しない。みつけたら必ず「やったね!」。

const RIM_SHADER = preload("res://assets/shaders/rim.gdshader")
const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const FIND_RANGE: float = 4.5          # この距離まで 近づくと みつかる
const MIX_RATE: int = 22050

# 隠れている子(地上の あちこち)。id はセーブの識別子、name はひらがな表示用。
const SPOTS: Array = [
	{"id": "h0", "pos": Vector2(30.0, 34.0),   "color": Color(0.95, 0.75, 0.35), "name": "きいろい こ"},
	{"id": "h1", "pos": Vector2(-42.0, 20.0),  "color": Color(0.6, 0.82, 0.55),  "name": "みどりの こ"},
	{"id": "h2", "pos": Vector2(16.0, -46.0),  "color": Color(0.95, 0.6, 0.72),  "name": "ももいろの こ"},
	{"id": "h3", "pos": Vector2(-34.0, -38.0), "color": Color(0.6, 0.74, 0.95),  "name": "みずいろの こ"},
	{"id": "h4", "pos": Vector2(54.0, -8.0),   "color": Color(0.82, 0.66, 0.95), "name": "むらさきの こ"},
]

var _player: Node3D
var _game_state: Node
var _hud: Node
var _critters: Array = []          # [{root, vis, base_y, found, id, name}]
var _sfx: AudioStreamPlayer
var _found_song: AudioStreamWAV
var _ready_done: bool = false


func _ready() -> void:
	var root := get_tree().root
	_player = root.find_child("Player", true, false) as Node3D
	_game_state = root.find_child("GameState", true, false)
	_hud = root.find_child("TouchHUD", true, false)
	_sfx = AudioStreamPlayer.new()
	_sfx.volume_db = -7.0
	add_child(_sfx)
	_found_song = _make_tone([784.0, 1046.5, 1318.5], 0.12)   # やさしい「ピロリン」(みつけた!)
	if _game_state:
		_game_state.hidden_total = SPOTS.size()
	_build_all()
	_ready_done = true


func _process(_delta: float) -> void:
	if not _ready_done or _player == null:
		return
	var pp: Vector3 = _player.global_position
	for c in _critters:
		if c.found:
			continue
		if c.root.global_position.distance_to(pp) < FIND_RANGE:
			_find(c)


# === 生成 ===

func _build_all() -> void:
	for spot in SPOTS:
		var already: bool = _game_state != null and _game_state.has_hidden(spot.id)
		_critters.append(_build_critter(spot, already))


# already=true(過去にみつけた子)は 立って 待っている。まだの子は ちいさく 隠れている。
func _build_critter(spot: Dictionary, already: bool) -> Dictionary:
	var pos: Vector2 = spot.pos
	var gy: float = TerrainHeight.compute_height(pos.x, pos.y)
	var root := Node3D.new()
	root.position = Vector3(pos.x, gy, pos.y)
	add_child(root)

	var vis := Node3D.new()
	root.add_child(vis)
	# まだの子は ちいさく(隠れている感)。みつけると ぽよんと 大きくなる。
	vis.scale = Vector3.ONE if already else Vector3.ONE * 0.55

	var col: Color = spot.color
	# からだ(まるい)
	var body := _ball(0.32, col, 0.85)
	body.scale = Vector3(1.0, 1.0, 1.1)
	body.position = Vector3(0, 0.3, 0)
	vis.add_child(body)
	# おみみ(ちょこん)
	for sx in [-1.0, 1.0]:
		var ear := _ball(0.1, col, 0.85)
		ear.position = Vector3(sx * 0.16, 0.58, 0.0)
		vis.add_child(ear)
	# おなか(あかるい)
	var belly := _ball(0.2, col.lerp(Color.WHITE, 0.5), 0.85)
	belly.scale = Vector3(0.9, 1.0, 0.6)
	belly.position = Vector3(0, 0.28, -0.18)
	vis.add_child(belly)
	# め(まんまる)
	for sx in [-1.0, 1.0]:
		var eye := _ball(0.05, Color(0.08, 0.06, 0.05), 0.4, true)
		eye.position = Vector3(sx * 0.11, 0.36, -0.28)
		vis.add_child(eye)

	return {"root": root, "vis": vis, "base_y": 0.0, "found": already, "id": spot.id, "name": spot.name}


# === みつけた ===

func _find(c: Dictionary) -> void:
	c.found = true
	var vis: Node3D = c.vis
	# ぽよんと 大きくなりながら ぴょこんと 飛び出す(やさしい上向きバウンス)。
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(vis, "scale", Vector3.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(vis, "position:y", c.base_y + 0.7, 0.18) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(vis, "position:y", c.base_y, 0.3) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)

	_spawn_sparkle(c.root.global_position + Vector3(0, 0.8, 0), c.root)
	if _sfx and _found_song:
		_sfx.stream = _found_song
		_sfx.play()
	if _game_state:
		_game_state.add_hidden(c.id)

	var n: int = _game_state.hidden_found.size() if _game_state else 0
	var total: int = _critters.size()
	if _hud and _hud.has_method("show_notice"):
		if n >= total:
			_hud.show_notice("かくれんぼ はかせに なったよ!")
		else:
			_hud.show_notice("みつけた! かくれんぼ %d/%d" % [n, total])


# にじいろの キラキラ(みつけた演出)。
func _spawn_sparkle(pos: Vector3, parent: Node3D) -> void:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0, -2.2, 0)
	pm.scale_min = 0.14
	pm.scale_max = 0.34
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.32, 0.32)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.6)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.5)
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


# === メッシュ / 音ヘルパー(animal.gd / animal_manager.gd と同じ作り) ===

func _ball(radius: float, color: Color, rough: float, unshaded: bool = false) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 8
	var mi := MeshInstance3D.new()
	mi.mesh = s
	if unshaded:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = mat
	else:
		var sm := ShaderMaterial.new()
		sm.shader = RIM_SHADER
		sm.set_shader_parameter("albedo", color)
		sm.set_shader_parameter("roughness_val", rough)
		sm.set_shader_parameter("rim_color", Color(1, 1, 0.96))
		sm.set_shader_parameter("rim_power", 2.5)
		sm.set_shader_parameter("rim_strength", 0.5)
		mi.material_override = sm
	return mi


# 正弦波で 音列(各音 note_dur 秒)を 1 つの WAV に。各音は sin 包絡線で角を取る。
func _make_tone(freqs: Array, note_dur: float) -> AudioStreamWAV:
	var per: int = int(MIX_RATE * note_dur)
	var n: int = per * freqs.size()
	var data := PackedByteArray()
	data.resize(n * 2)
	for k in range(freqs.size()):
		var freq: float = float(freqs[k])
		for i in range(per):
			var t: float = float(i) / float(MIX_RATE)
			var prog: float = float(i) / float(per)
			var env: float = sin(prog * PI)
			var s: float = sin(TAU * freq * t) * env * 0.55
			var v: int = int(clamp(s, -1.0, 1.0) * 32767.0)
			data.encode_s16((k * per + i) * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
