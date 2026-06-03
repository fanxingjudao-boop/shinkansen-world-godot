extends Node3D

# 動物たちの「なかよし」を統括する。Animals ノードに付ける。
# - プレイヤーが動物に近づいたら自動でなかよし成立(タッチ不要=3歳児にやさしい)
# - interact を使わないので乗車システム(ride_controller)と競合しない
# - なかよし成立で動物が喜び、HUD に「○○と なかよし!」通知
# - なかよし数は signal で公開(将来の HUD カウンター / 図鑑用)

const Animal = preload("res://scripts/entities/animal.gd")
const TouchHud = preload("res://scripts/ui/touch_hud.gd")

const BEFRIEND_RANGE: float = 3.0

# === 動物が歌う(なかよし済みの子が、近くにいるとときどき短いメロを歌う) ===
const MIX_RATE: int = 22050
const SING_RANGE: float = 18.0        # プレイヤーからこの距離以内の子が歌う(近くの子の声が聞こえる)
const SING_INTERVAL_MIN: float = 7.0
const SING_INTERVAL_MAX: float = 15.0

# === なかよしの子が ときどき「ほし」を くれる(プレゼント) ===
const GIFT_RANGE: float = 16.0
const GIFT_INTERVAL_MIN: float = 12.0
const GIFT_INTERVAL_MAX: float = 20.0

@export var player_path: NodePath
@export var hud_path: NodePath
@export var game_state_path: NodePath

signal befriended(display_name: String, total: int)

var _player: Node3D
var _hud: TouchHud
var _game_state: Node
var _count: int = 0

var _song_player: AudioStreamPlayer
var _songs: Array = []          # AudioStreamWAV のバリエーション
var _sing_timer: float = 6.0

var _gift_player: AudioStreamPlayer
var _gift_song: AudioStreamWAV
var _gift_timer: float = 10.0


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	_hud = get_node_or_null(hud_path) as TouchHud
	_game_state = get_node_or_null(game_state_path)
	if _player == null:
		push_warning("[AnimalManager] player_path が未解決")
	_song_player = AudioStreamPlayer.new()
	_song_player.volume_db = -10.0
	add_child(_song_player)
	_build_songs()
	_sing_timer = randf_range(SING_INTERVAL_MIN, SING_INTERVAL_MAX)
	_gift_player = AudioStreamPlayer.new()
	_gift_player.volume_db = -8.0
	add_child(_gift_player)
	_gift_song = _make_song([880.0, 1318.5], 0.14)   # やさしい「ピロン」
	_gift_timer = randf_range(GIFT_INTERVAL_MIN, GIFT_INTERVAL_MAX)


func _process(delta: float) -> void:
	if _player == null:
		return
	var pp: Vector3 = _player.global_position
	for child in get_children():
		var a := child as Animal
		if a == null or a.is_befriended():
			continue
		if a.global_position.distance_to(pp) < BEFRIEND_RANGE:
			a.befriend()
			_count += 1
			if _hud:
				_hud.show_notice("%sと なかよし!" % a.get_display_name())
			if _game_state:
				_game_state.add_befriended(a.get_slug())
			befriended.emit(a.get_display_name(), _count)

	# 歌のタイマー
	_sing_timer -= delta
	if _sing_timer <= 0.0:
		_sing_timer = randf_range(SING_INTERVAL_MIN, SING_INTERVAL_MAX)
		_try_sing(pp)

	# プレゼントのタイマー(なかよしの子が ときどき ほしを くれる)
	_gift_timer -= delta
	if _gift_timer <= 0.0:
		_gift_timer = randf_range(GIFT_INTERVAL_MIN, GIFT_INTERVAL_MAX)
		_try_gift(pp)


# === 歌 ===

# プレイヤーの近くにいるなかよし済みの子を 1 匹選んで歌わせる + 旋律を鳴らす。
func _try_sing(pp: Vector3) -> void:
	var singers: Array = []
	for child in get_children():
		var a := child as Animal
		if a == null or not a.is_befriended():
			continue
		if a.global_position.distance_to(pp) < SING_RANGE:
			singers.append(a)
	if singers.is_empty():
		return
	var a: Animal = singers[randi() % singers.size()]
	a.sing()
	if _song_player and not _songs.is_empty():
		# slug で旋律を選ぶ(同じ子はいつも同じ歌)
		var idx: int = abs(a.get_slug().hash()) % _songs.size()
		_song_player.stream = _songs[idx]
		_song_player.play()


# === プレゼント(ほし) ===

# プレイヤーの近くにいる なかよし済みの子を 1 匹選び、ほしを プレゼントさせる。
# なかよしが 多い/近い ほど もらえる(公平に 良い結果へ)。
func _try_gift(pp: Vector3) -> void:
	if _game_state == null:
		return
	var givers: Array = []
	for child in get_children():
		var a := child as Animal
		if a == null or not a.is_befriended():
			continue
		if a.global_position.distance_to(pp) < GIFT_RANGE:
			givers.append(a)
	if givers.is_empty():
		return
	var a: Animal = givers[randi() % givers.size()]
	a.sing()   # ぴょこっと よろこぶ
	_spawn_gift_fx(a.global_position + Vector3(0, 1.4, 0))
	if _hud:
		_hud.show_notice("%s が ほしを くれた!" % a.get_display_name())
	_game_state.add_star()
	if _gift_player and _gift_song:
		_gift_player.stream = _gift_song
		_gift_player.play()


# 金色の キラキラ(プレゼントの演出)。
func _spawn_gift_fx(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 14
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.4
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -2.0, 0)
	pm.scale_min = 0.14
	pm.scale_max = 0.36
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.34, 0.34)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3)
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


func _build_songs() -> void:
	var phrases := [
		[523.25, 659.25, 783.99, 659.25],
		[659.25, 783.99, 880.0, 783.99],
		[783.99, 880.0, 1046.5, 880.0],
		[587.33, 659.25, 783.99, 1046.5],
	]
	for p in phrases:
		_songs.append(_make_song(p, 0.15))


# 正弦波で音列(各音 note_dur 秒)を 1 つの WAV に合成。各音は sin 包絡線で角を取る。
func _make_song(freqs: Array, note_dur: float) -> AudioStreamWAV:
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
