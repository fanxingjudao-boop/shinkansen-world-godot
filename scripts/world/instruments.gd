extends Node3D

# B-5 楽器(押すと音が鳴る たからもの)。PLAYFUL_DETAILS B-5。
# 主役は「もっきん」= ドレミの 8 枚の鍵盤。タップすると その音が鳴り、自分で
# メロディが弾ける(音を出す遊びは子供の根源的な楽しみ)。もうひとつ「ラッパ」を
# 置き、タップすると ぴゃ〜と 短いファンファーレが鳴る。
#
# 設計(SPEC.md / interactables.gd B-2 を踏襲):
# - Main 直下に 1 つ置く小さなノード(main.gd が起動時に生成)。Main.tscn は不変。
# - タップ判定は Area3D の input_event(カメラからの物理ピッキング)。
#   Viewport の physics_object_picking を ON(B-2 と同じ。他は近接式なので影響なし)。
# - 音は sound_fx と同じ プロシージャル WAV。音量はひかえめ・不快でない正弦波。
# - ミュートは Master バス(settings の「おと」)で一括 → 既定バスに繋ぐだけで連動。

const RIM_SHADER = preload("res://assets/shaders/rim.gdshader")
const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const MIX_RATE: int = 22050

# 置き場所(地上・主人公の近くで さわりやすい所)。実機で重なれば調整可。
const XYLO_POS: Vector2 = Vector2(12.0, 8.0)
const TRUMPET_POS: Vector2 = Vector2(4.0, -12.0)

# もっきん: ドレミファソラシド(C5..C6)の周波数。
const SCALE_FREQS: Array = [523.25, 587.33, 659.25, 698.46, 783.99, 880.0, 987.77, 1046.5]
# 鍵盤の色(にじいろ・やわらかめ)。低音=あたたかい色 → 高音=すずしい色。
const BAR_COLORS: Array = [
	Color(1.0, 0.55, 0.65),  # ど もも
	Color(1.0, 0.7, 0.4),    # れ オレンジ
	Color(1.0, 0.88, 0.4),   # み きいろ
	Color(0.65, 0.85, 0.5),  # ふぁ わかくさ
	Color(0.55, 0.82, 0.95), # そ みずいろ
	Color(0.5, 0.65, 0.95),  # ら あお
	Color(0.78, 0.62, 0.92), # し むらさき
	Color(1.0, 0.62, 0.78),  # ど(高) もも
]

var _sfx: AudioStreamPlayer
var _notes: Array = []           # 鍵盤ごとの音(index 対応)
var _fanfare: AudioStreamWAV
var _busy: Dictionary = {}       # 連打よけ(反応中の vis を覚える)


func _ready() -> void:
	get_viewport().physics_object_picking = true  # B-2 が ON 済でも冪等
	_sfx = AudioStreamPlayer.new()
	_sfx.volume_db = -10.0
	add_child(_sfx)
	for f in SCALE_FREQS:
		_notes.append(_make_tone([float(f)], 0.4))           # 1 音(やわらかい減衰)
	_fanfare = _make_tone([523.25, 659.25, 783.99, 1046.5], 0.16)  # ぴゃ〜(ドミソド)
	_build_xylophone()
	_build_trumpet()


# === もっきん ===

func _build_xylophone() -> void:
	var gy: float = TerrainHeight.compute_height(XYLO_POS.x, XYLO_POS.y)
	var root := Node3D.new()
	root.position = Vector3(XYLO_POS.x, gy, XYLO_POS.y)
	add_child(root)

	var n: int = SCALE_FREQS.size()
	var spacing: float = 0.34
	var total_w: float = spacing * float(n - 1)
	var bar_y: float = 0.5

	# 両端の脚(木の台)
	for sx in [-1.0, 1.0]:
		var leg := _box(0.12, bar_y, 1.5, Color(0.82, 0.66, 0.46))
		leg.position = Vector3(sx * (total_w * 0.5 + 0.28), bar_y * 0.5, 0)
		root.add_child(leg)
	# レール 2 本(鍵盤を載せる横木)
	for sz in [-1.0, 1.0]:
		var rail := _box(total_w + 0.7, 0.06, 0.1, Color(0.78, 0.6, 0.42))
		rail.position = Vector3(0, bar_y, sz * 0.5)
		root.add_child(rail)

	# 鍵盤(低音ほど長い)。各鍵盤が個別の Area3D を持ち、タップで その音。
	for i in range(n):
		var x: float = -total_w * 0.5 + float(i) * spacing
		var blen: float = lerpf(1.42, 0.82, float(i) / float(n - 1))
		var vis := Node3D.new()
		vis.position = Vector3(x, bar_y + 0.09, 0)
		root.add_child(vis)
		var bar := _box(0.26, 0.1, blen, BAR_COLORS[i % BAR_COLORS.size()])
		vis.add_child(bar)

		var area := Area3D.new()
		area.input_ray_pickable = true
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.3, 0.45, maxf(blen, 0.6))
		shape.shape = box
		shape.position = Vector3(0, 0.12, 0)
		area.add_child(shape)
		vis.add_child(area)
		area.input_event.connect(_on_bar_input.bind(vis, i))


func _on_bar_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int, vis: Node3D, idx: int) -> void:
	if _is_tap(event):
		_play_bar(vis, idx)


func _play_bar(vis: Node3D, idx: int) -> void:
	if _busy.get(vis, false):
		return
	_busy[vis] = true
	if _sfx and idx < _notes.size():
		_sfx.stream = _notes[idx]
		_sfx.play()
	var base_y: float = vis.position.y
	var tw := create_tween()
	# ぺこっと 沈んで もどる(たたいた感)。素早く戻して 速い演奏もできるように。
	tw.tween_property(vis, "position:y", base_y - 0.06, 0.04).set_trans(Tween.TRANS_SINE)
	tw.tween_property(vis, "position:y", base_y, 0.12).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _busy[vis] = false)


# === ラッパ ===

func _build_trumpet() -> void:
	var gy: float = TerrainHeight.compute_height(TRUMPET_POS.x, TRUMPET_POS.y)
	var root := Node3D.new()
	root.position = Vector3(TRUMPET_POS.x, gy, TRUMPET_POS.y)
	add_child(root)

	var vis := Node3D.new()
	root.add_child(vis)
	# 短い柱 + 金色のベル(広がるコーン)+ 吹き口
	var post := _cyl(0.06, 0.5, Color(0.8, 0.62, 0.42))
	post.position = Vector3(0, 0.25, 0)
	vis.add_child(post)
	var bell := _cone(0.06, 0.34, 0.4, Color(1.0, 0.82, 0.3))
	bell.position = Vector3(0, 0.72, 0)
	vis.add_child(bell)
	var mouth := _ball(0.08, Color(1.0, 0.88, 0.45), 0.4)
	mouth.position = Vector3(0, 0.52, 0)
	vis.add_child(mouth)

	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.0, 0.8)
	shape.shape = box
	shape.position = Vector3(0, 0.5, 0)
	area.add_child(shape)
	root.add_child(area)
	area.input_event.connect(_on_trumpet_input.bind(vis))


func _on_trumpet_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int, vis: Node3D) -> void:
	if _is_tap(event):
		_play_trumpet(vis)


func _play_trumpet(vis: Node3D) -> void:
	if _busy.get(vis, false):
		return
	_busy[vis] = true
	if _sfx and _fanfare:
		_sfx.stream = _fanfare
		_sfx.play()
	var tw := create_tween()
	# ぴゃ〜と のびあがって もどる
	tw.tween_property(vis, "scale", Vector3(1.1, 1.18, 1.1), 0.12).set_trans(Tween.TRANS_SINE)
	tw.tween_property(vis, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _busy[vis] = false)


# === 入力ヘルパー ===

func _is_tap(event: InputEvent) -> bool:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		return true
	if event is InputEventScreenTouch and event.pressed:
		return true
	return false


# === メッシュ / 音ヘルパー(interactables.gd と同じ作法)===

func _ball(radius: float, color: Color, rough: float) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 8
	return _rim(MeshInstance3D.new(), s, color, rough)


func _box(sx: float, sy: float, sz: float, color: Color) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return _rim(MeshInstance3D.new(), b, color, 0.7)


func _cyl(radius: float, height: float, color: Color) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 14
	return _rim(MeshInstance3D.new(), c, color, 0.7)


# 上が広い コーン(ラッパのベル)。top_radius != bottom_radius で円錐。
func _cone(bottom_r: float, top_r: float, height: float, color: Color) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = height
	c.radial_segments = 16
	return _rim(MeshInstance3D.new(), c, color, 0.45)


func _rim(mi: MeshInstance3D, mesh: Mesh, color: Color, rough: float) -> MeshInstance3D:
	mi.mesh = mesh
	var sm := ShaderMaterial.new()
	sm.shader = RIM_SHADER
	sm.set_shader_parameter("albedo", color)
	sm.set_shader_parameter("roughness_val", rough)
	sm.set_shader_parameter("rim_color", Color(1, 1, 0.96))
	sm.set_shader_parameter("rim_power", 2.5)
	sm.set_shader_parameter("rim_strength", 0.5)
	mi.material_override = sm
	return mi


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
			var sv: float = sin(TAU * freq * t) * env * 0.55
			var v: int = int(clamp(sv, -1.0, 1.0) * 32767.0)
			data.encode_s16((k * per + i) * 2, v)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
