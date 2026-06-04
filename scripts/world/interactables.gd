extends Node3D

# たたくと 反応するもの(PLAYFUL_DETAILS B-2)。
# 世界の オブジェクトを タッチ(タップ)すると 反応する。きのこ=ぽよん、
# たいこ=ぽんと鳴る、ベル=ちりんと鳴る。触れるものが あるほど 世界が 遊び場に。
#
# 設計(SPEC.md の方針):
# - Main 直下に 1 つ置く小さなノード(main.gd が起動時に生成)。
# - タップ判定は Area3D の input_event(カメラからの物理ピッキング)を使う。
#   そのため Viewport の physics_object_picking を ON にする(他は近接式なので影響なし)。
# - 反応は 必ず 楽しい・かわいい(壊れる/痛がる は無し)。音は ひかえめ。

const RIM_SHADER = preload("res://assets/shaders/rim.gdshader")
const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const MIX_RATE: int = 22050

# 置き場所(地上・主人公の近くで さわりやすい所)。kind ごとに 見た目と 反応が ちがう。
const ITEMS: Array = [
	{"kind": "mushroom", "pos": Vector2(-10.0, 8.0),  "color": Color(0.95, 0.45, 0.5)},
	{"kind": "mushroom", "pos": Vector2(-14.0, 12.0), "color": Color(0.95, 0.8, 0.4)},
	{"kind": "drum",     "pos": Vector2(10.0, -6.0),  "color": Color(0.9, 0.55, 0.3)},
	{"kind": "bell",     "pos": Vector2(-6.0, -12.0), "color": Color(1.0, 0.85, 0.35)},
]

var _sfx: AudioStreamPlayer
var _sounds: Dictionary = {}     # kind -> AudioStreamWAV
var _busy: Dictionary = {}       # 連打よけ(反応中の vis を覚える)


func _ready() -> void:
	# Area3D の input_event を 動かすため、ビューポートの物理ピッキングを ON。
	get_viewport().physics_object_picking = true
	_sfx = AudioStreamPlayer.new()
	_sfx.volume_db = -9.0
	add_child(_sfx)
	_sounds["mushroom"] = _make_tone([523.0, 880.0], 0.1)        # ぽよん
	_sounds["drum"] = _make_tone([160.0, 110.0], 0.12)           # ぽん(低い)
	_sounds["bell"] = _make_tone([1046.5, 1568.0, 1318.5], 0.1)  # ちりん
	for item in ITEMS:
		_build_item(item)


func _build_item(item: Dictionary) -> void:
	var pos: Vector2 = item.pos
	var gy: float = TerrainHeight.compute_height(pos.x, pos.y)
	var root := Node3D.new()
	root.position = Vector3(pos.x, gy, pos.y)
	add_child(root)

	var vis := Node3D.new()
	root.add_child(vis)

	var hit_h: float = 0.7
	match item.kind:
		"mushroom":
			var stem := _cyl(0.12, 0.36, Color(0.97, 0.95, 0.88))
			stem.position = Vector3(0, 0.18, 0)
			vis.add_child(stem)
			var cap := _ball(0.34, item.color, 0.7)
			cap.scale = Vector3(1.0, 0.7, 1.0)
			cap.position = Vector3(0, 0.42, 0)
			vis.add_child(cap)
			# 白い ぽつぽつ
			for a in range(5):
				var ang: float = float(a) / 5.0 * TAU
				var dot := _ball(0.05, Color(1, 1, 1), 0.6)
				dot.position = Vector3(cos(ang) * 0.2, 0.5, sin(ang) * 0.2)
				vis.add_child(dot)
			hit_h = 0.8
		"drum":
			var barrel := _cyl(0.34, 0.5, item.color)
			barrel.position = Vector3(0, 0.3, 0)
			vis.add_child(barrel)
			var top := _cyl(0.36, 0.06, Color(0.98, 0.95, 0.9))
			top.position = Vector3(0, 0.56, 0)
			vis.add_child(top)
			hit_h = 0.7
		"bell":
			var bell := _ball(0.3, item.color, 0.4)
			bell.scale = Vector3(1.0, 1.15, 1.0)
			bell.position = Vector3(0, 0.5, 0)
			vis.add_child(bell)
			var ring := _cyl(0.06, 0.12, Color(0.7, 0.5, 0.2))
			ring.position = Vector3(0, 0.82, 0)
			vis.add_child(ring)
			hit_h = 0.95

	# タップを 拾う Area3D(カメラからの ピッキング)。
	var area := Area3D.new()
	area.input_ray_pickable = true
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.9, hit_h, 0.9)
	shape.shape = box
	shape.position = Vector3(0, hit_h * 0.5, 0)
	area.add_child(shape)
	root.add_child(area)
	area.input_event.connect(_on_item_input.bind(vis, str(item.kind)))


# Area3D.input_event: (camera, event, position, normal, shape_idx) + bind(vis, kind)
func _on_item_input(_camera: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _shape_idx: int, vis: Node3D, kind: String) -> void:
	var tapped: bool = false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
	elif event is InputEventScreenTouch and event.pressed:
		tapped = true
	if tapped:
		_react(vis, kind)


func _react(vis: Node3D, kind: String) -> void:
	if _busy.get(vis, false):
		return
	_busy[vis] = true
	if _sfx and _sounds.has(kind):
		_sfx.stream = _sounds[kind]
		_sfx.play()
	var tw := create_tween()
	match kind:
		"mushroom":
			# ぺこっと 縮んで ぽよん
			tw.tween_property(vis, "scale", Vector3(1.2, 0.7, 1.2), 0.1).set_trans(Tween.TRANS_SINE)
			tw.tween_property(vis, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		"bell":
			# ちりんと 横ゆれ
			tw.tween_property(vis, "rotation:z", 0.25, 0.08).set_trans(Tween.TRANS_SINE)
			tw.tween_property(vis, "rotation:z", -0.25, 0.12).set_trans(Tween.TRANS_SINE)
			tw.tween_property(vis, "rotation:z", 0.0, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_:
			# たいこ: ぽんと つぶれて もどる
			tw.tween_property(vis, "scale", Vector3(1.1, 0.85, 1.1), 0.08).set_trans(Tween.TRANS_SINE)
			tw.tween_property(vis, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _busy[vis] = false)


# === メッシュ / 音ヘルパー ===

func _ball(radius: float, color: Color, rough: float) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = 12
	s.rings = 8
	return _rim(MeshInstance3D.new(), s, color, rough)


func _cyl(radius: float, height: float, color: Color) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 14
	return _rim(MeshInstance3D.new(), c, color, 0.7)


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
