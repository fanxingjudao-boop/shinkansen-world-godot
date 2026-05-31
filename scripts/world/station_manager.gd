extends Node3D

# 駅の「はっけん」を統括する。Stations ノードに付ける。
# - プレイヤーが駅に近づいたら自動で発見(タッチ不要、動物のなかよしと同じ方式)
# - 発見で GameState に記録 + HUD に「○○ えき はっけん!」通知
# - 発見済み判定は GameState.has_station() で行う(重複通知を防ぐ)

const Station = preload("res://scripts/world/station.gd")
const TouchHud = preload("res://scripts/ui/touch_hud.gd")

const FIND_RANGE: float = 9.0  # 駅は大きいので広め

# === 駅メロ(電車が駅に着いたとき、その駅のテーマ短メロを鳴らす) ===
const MIX_RATE: int = 22050
const ARRIVE_AUDIBLE_RANGE: float = 75.0  # カメラからこの距離以内の編成の到着だけ鳴らす(乗車中=カメラが編成上, 近くの編成も含む)
const MELODY_NEAR_STATION: float = 22.0   # 到着位置からこの距離以内に駅があれば、その駅のメロを鳴らす
const CHIME_COOLDOWN: float = 1.2         # 連続再生を防ぐクールダウン(秒)

# === おだんごで げんきアップ(おかし駅のだんごに近づくと食べられる) ===
const EAT_RANGE: float = 4.5              # だんごにこの距離まで近づくと食べる
const EAT_COOLDOWN: float = 5.0           # 食べ続けない(満腹の間)クールダウン(秒)
const TREAT_COLOR: Color = Color(1.0, 0.7, 0.8)  # だんごのキラキラ色(さくら色)

@export var player_path: NodePath
@export var hud_path: NodePath
@export var game_state_path: NodePath
@export var trains_path: NodePath  # Trains ノード(到着シグナルを受け取る)

signal discovered(display_name: String, total: int)

var _player: Node3D
var _hud: TouchHud
var _game_state: Node

var _melody_player: AudioStreamPlayer
var _jingles: Dictionary = {}  # slug -> AudioStreamWAV
var _chime_cooldown: float = 0.0
var _eat_cooldown: float = 0.0


func _ready() -> void:
	_player = get_node_or_null(player_path) as Node3D
	_hud = get_node_or_null(hud_path) as TouchHud
	_game_state = get_node_or_null(game_state_path)
	_setup_station_melody()


func _process(delta: float) -> void:
	if _chime_cooldown > 0.0:
		_chime_cooldown = max(0.0, _chime_cooldown - delta)
	if _eat_cooldown > 0.0:
		_eat_cooldown = max(0.0, _eat_cooldown - delta)
	if _player == null or _game_state == null:
		return
	var pp: Vector3 = _player.global_position
	_update_treats(pp)
	for child in get_children():
		var s := child as Station
		if s == null:
			continue
		var slug := s.get_slug()
		if _game_state.has_station(slug):
			continue
		if s.global_position.distance_to(pp) < FIND_RANGE:
			_game_state.add_station(slug)
			if _hud:
				_hud.show_notice("%s えき はっけん!" % s.get_display_name())
			discovered.emit(s.get_display_name(), _game_state.visited_stations.size())


# === おだんごで げんきアップ ===

func _update_treats(pp: Vector3) -> void:
	if _eat_cooldown > 0.0:
		return
	for child in get_children():
		var s := child as Station
		if s == null or not s.has_treat():
			continue
		if s.get_treat_position().distance_to(pp) < EAT_RANGE:
			_eat_treat(s)
			return


func _eat_treat(s: Station) -> void:
	_eat_cooldown = EAT_COOLDOWN
	if _game_state and _game_state.has_method("add_energy"):
		_game_state.add_energy(1)  # SoundFX が changed を受けて「もぐもぐ音」を鳴らす
	if _hud:
		_hud.show_notice("おだんご もぐもぐ! げんき アップ!")
	_spawn_treat_sparkle(s.get_treat_position())
	if _player and _player.has_method("celebrate"):
		_player.celebrate()


# だんごの上にさくら色のキラキラを一発はじけさせる(one-shot、寿命後 自動削除)
func _spawn_treat_sparkle(pos: Vector3) -> void:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 0.7
	p.one_shot = true
	p.explosiveness = 1.0
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 1.6
	pm.initial_velocity_max = 3.6
	pm.gravity = Vector3(0, -3.5, 0)
	pm.scale_min = 0.12
	pm.scale_max = 0.32
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.3, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TREAT_COLOR
	mat.emission_enabled = true
	mat.emission = TREAT_COLOR
	mat.emission_energy_multiplier = 2.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	qm.material = mat
	p.draw_pass_1 = qm
	add_child(p)
	p.global_position = pos
	p.emitting = true
	p.finished.connect(p.queue_free)


# === 駅メロ ===

func _setup_station_melody() -> void:
	_melody_player = AudioStreamPlayer.new()
	_melody_player.volume_db = -9.0
	add_child(_melody_player)
	_build_jingles()
	var trains := get_node_or_null(trains_path)
	if trains:
		for t in trains.get_children():
			if t.has_signal("arrived"):
				t.arrived.connect(_on_train_arrived)


# 駅ごとのやさしい短メロ(ペンタトニック中心の Hz 列)。slug -> 音列。
func _build_jingles() -> void:
	var notes := {
		"midori": [523.25, 659.25, 783.99],
		"hana": [659.25, 587.33, 783.99, 880.0],
		"yama": [783.99, 659.25, 523.25],
		"mizuumi": [587.33, 783.99, 659.25, 1046.5],
		"okashi": [880.0, 783.99, 880.0, 1046.5],
		"niji": [523.25, 587.33, 659.25, 783.99, 880.0],
	}
	for slug in notes:
		_jingles[slug] = _make_jingle(notes[slug], 0.16)


# 電車が駅に着いたら呼ばれる。近く(カメラ範囲内)の編成だけ、最寄りの駅メロを鳴らす。
func _on_train_arrived(anchor_pos: Vector3) -> void:
	if _chime_cooldown > 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	if anchor_pos.distance_to(cam.global_position) > ARRIVE_AUDIBLE_RANGE:
		return
	# 到着位置に最も近い駅を探す
	var best: Station = null
	var best_d: float = MELODY_NEAR_STATION
	for child in get_children():
		var s := child as Station
		if s == null:
			continue
		var d: float = s.global_position.distance_to(anchor_pos)
		if d < best_d:
			best_d = d
			best = s
	if best == null:
		return
	var jingle = _jingles.get(best.get_slug())
	if jingle == null:
		return
	_melody_player.stream = jingle
	_melody_player.play()
	_chime_cooldown = CHIME_COOLDOWN


# 正弦波で音列(各音 note_dur 秒)を 1 つの WAV に合成。各音は sin 包絡線で角を取る。
func _make_jingle(freqs: Array, note_dur: float) -> AudioStreamWAV:
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
