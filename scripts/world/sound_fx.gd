extends Node

# やさしい効果音。Main 直下のノード。
# 正弦波の短い音をスクリプトで生成(素材ファイル不要)、GameState の進捗が
# 増えたときに鳴らす。星・なかよし・乗車・駅発見でそれぞれ違う音。
#
# 注意(Web): ブラウザの AudioContext は最初のユーザー操作後に有効になる。
# タッチ/クリックの後でないと鳴らないことがある(Godot/ブラウザ仕様)。
# スタート画面で AudioContext を起こす対応は Phase 5 で。

const GameState = preload("res://scripts/world/game_state.gd")

const MIX_RATE: int = 22050

@export var game_state_path: NodePath

var _gs: GameState
var _player: AudioStreamPlayer

var _prev_star: int = 0
var _prev_friend: int = 0
var _prev_board: int = 0
var _prev_station: int = 0

var _tone_star: AudioStreamWAV
var _tone_friend: AudioStreamWAV
var _tone_board: AudioStreamWAV
var _tone_station: AudioStreamWAV


func _ready() -> void:
	_gs = get_node_or_null(game_state_path) as GameState
	_player = AudioStreamPlayer.new()
	_player.volume_db = -8.0
	add_child(_player)
	# やさしい上昇 2 音(ド→ソ など)
	_tone_star = _make_tone(880.0, 1320.0, 0.18)
	_tone_friend = _make_tone(660.0, 990.0, 0.22)
	_tone_board = _make_tone(523.0, 784.0, 0.20)
	_tone_station = _make_tone(784.0, 1047.0, 0.20)
	if _gs:
		_gs.changed.connect(_on_changed)


func _on_changed() -> void:
	if _gs == null:
		return
	# 増えたものを 1 つ鳴らす(同時増加はまれなので優先順で 1 つ)
	if _gs.star_count > _prev_star:
		_play(_tone_star)
	elif _gs.befriended_animals.size() > _prev_friend:
		_play(_tone_friend)
	elif _gs.boarded_trains.size() > _prev_board:
		_play(_tone_board)
	elif _gs.visited_stations.size() > _prev_station:
		_play(_tone_station)
	_prev_star = _gs.star_count
	_prev_friend = _gs.befriended_animals.size()
	_prev_board = _gs.boarded_trains.size()
	_prev_station = _gs.visited_stations.size()


func _play(stream: AudioStreamWAV) -> void:
	_player.stream = stream
	_player.play()


# 正弦波で短い 2 音(前半 freq_a → 後半 freq_b)を作る。
# 両端をなめらかに(sin の山でフェードイン/アウト)してプチノイズを抑える。
func _make_tone(freq_a: float, freq_b: float, dur: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in range(n):
		var t: float = float(i) / float(MIX_RATE)
		var prog: float = float(i) / float(n)
		var freq: float = freq_a if prog < 0.5 else freq_b
		var env: float = sin(prog * PI)  # 0→1→0 のやさしい包絡線
		var s: float = sin(TAU * freq * t) * env * 0.6
		var v: int = int(clamp(s, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
