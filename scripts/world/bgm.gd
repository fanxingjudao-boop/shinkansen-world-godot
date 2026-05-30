extends Node

# 穏やかな BGM。ペンタトニック(やさしく聞こえる音階)のゆったりした旋律を
# スクリプトで生成してループ再生(素材ファイル不要)。
# 正弦波 + やわらかい包絡線で、子供と大人が一緒に聞いて心地よい音に。
#
# Web: AudioContext はユーザー操作後に有効。タイトルの「はじめる」を押すと
# 鳴り始める(_ready で play() しておけば resume 時に再生される)。

const MIX_RATE: int = 22050

# ゆったりした旋律(ド・ミ・ソ・ラ中心のペンタトニック)。Hz
const MELODY: Array = [
	261.6, 329.6, 392.0, 329.6, 440.0, 392.0, 329.6, 293.7,
	261.6, 329.6, 392.0, 523.3, 440.0, 392.0, 329.6, 261.6,
]
const NOTE_DUR: float = 0.85

var _player: AudioStreamPlayer


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.volume_db = -16.0
	_player.stream = _build_bgm()
	add_child(_player)
	_player.play()


func _build_bgm() -> AudioStreamWAV:
	var note_n: int = int(MIX_RATE * NOTE_DUR)
	var total: int = note_n * MELODY.size()
	var data := PackedByteArray()
	data.resize(total * 2)
	var idx: int = 0
	for ni in range(MELODY.size()):
		var freq: float = MELODY[ni]
		for i in range(note_n):
			var t: float = float(idx) / float(MIX_RATE)
			var prog: float = float(i) / float(note_n)
			# やわらかい attack/release(音の頭と尻をなめらかに)
			var env: float = min(prog * 6.0, 1.0) * min((1.0 - prog) * 4.0, 1.0)
			# 基音 + 1 オクターブ上を少し混ぜてやさしい音色
			var s: float = (sin(TAU * freq * t) + 0.3 * sin(TAU * freq * 2.0 * t)) * env * 0.5
			var v: int = int(clamp(s, -1.0, 1.0) * 32767.0)
			data.encode_s16(idx * 2, v)
			idx += 1
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total
	wav.data = data
	return wav
