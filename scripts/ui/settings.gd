extends CanvasLayer

# おとなのかた用の設定(親モード)。Main 直下。HUD の「おとな」ボタンから open()。
# 子供が誤って操作しないよう、まず数字ゲート(1→2→3 の順)を通ってから設定に入る。
# 設定: 音(おと)の オン/オフ、あそんだ かいすう の表示、データを けす(2段階の確認つき)。
#
# 開いている間は get_tree().paused = true(world は止まる。本 CanvasLayer は
# process_mode = Always なのでボタン操作できる)。BookOverlay と同じ方針。

const SAVE_PATH: String = "user://save.json"

var _gs: Node
var _root: Control
var _gate: Control
var _panel: Control          # 設定本体(ゲート通過後に表示)
var _gate_seq: Array = []    # 押した数字の並び(1,2,3 で成功)
var _sound_btn: Button
var _play_label: Label
var _confirm: Control        # 「ほんとうに けす?」確認
var _muted: bool = false


func _ready() -> void:
	visible = false
	_gs = get_tree().root.find_child("GameState", true, false)
	_build()


func open() -> void:
	visible = true
	get_tree().paused = true
	_reset_gate()
	_update_sound_label()
	_update_play_label()


func close() -> void:
	get_tree().paused = false
	visible = false


# === 画面の組み立て ===

func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.4, 0.5, 0.6, 0.5)
	_root.add_child(dim)

	# --- 数字ゲート(おとな確認) ---
	_gate = _make_card(Vector2(560, 360))
	_root.add_child(_gate)
	var gv := _make_vbox(_gate)
	var gtitle := _label("おとなの かたへ", 36, Color(0.157, 0.408, 0.788))
	gv.add_child(gtitle)
	var ginfo := _label("1 → 2 → 3 の じゅんに おしてね", 28, Color(0.3, 0.35, 0.45))
	ginfo.autowrap_mode = TextServer.AUTOWRAP_WORD
	gv.add_child(ginfo)
	var nums := HBoxContainer.new()
	nums.alignment = BoxContainer.ALIGNMENT_CENTER
	nums.add_theme_constant_override("separation", 24)
	nums.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gv.add_child(nums)
	for n in [1, 2, 3]:
		var b := _button(str(n), 44, Vector2(110, 110))
		b.pressed.connect(func() -> void: _on_gate_num(n))
		nums.add_child(b)
	var gclose := _button("とじる", 28, Vector2(0, 60))
	gclose.pressed.connect(close)
	gv.add_child(gclose)

	# --- 設定本体(ゲート通過後) ---
	_panel = _make_card(Vector2(560, 460))
	_panel.visible = false
	_root.add_child(_panel)
	var pv := _make_vbox(_panel)
	pv.add_child(_label("せってい", 38, Color(0.157, 0.408, 0.788)))
	_sound_btn = _button("おと: オン", 30, Vector2(0, 72))
	_sound_btn.pressed.connect(_toggle_sound)
	pv.add_child(_sound_btn)
	_play_label = _label("あそんだ かいすう: 0 かい", 28, Color(0.3, 0.4, 0.3))
	pv.add_child(_play_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pv.add_child(spacer)
	var del := _button("データを けす", 28, Vector2(0, 64), Color(0.9, 0.45, 0.5))
	del.pressed.connect(_ask_delete)
	pv.add_child(del)
	var pclose := _button("とじる", 30, Vector2(0, 64))
	pclose.pressed.connect(close)
	pv.add_child(pclose)

	# --- 削除確認 ---
	_confirm = _make_card(Vector2(560, 300))
	_confirm.visible = false
	_root.add_child(_confirm)
	var cv := _make_vbox(_confirm)
	cv.add_child(_label("けすと さいしょから に なるよ。", 30, Color(0.6, 0.3, 0.35)))
	var crow := HBoxContainer.new()
	crow.alignment = BoxContainer.ALIGNMENT_CENTER
	crow.add_theme_constant_override("separation", 24)
	crow.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(crow)
	var yes := _button("けす", 32, Vector2(200, 90), Color(0.9, 0.45, 0.5))
	yes.pressed.connect(_do_delete)
	crow.add_child(yes)
	var no := _button("やめる", 32, Vector2(200, 90))
	no.pressed.connect(func() -> void: _confirm.visible = false; _panel.visible = true)
	crow.add_child(no)


# === ゲート ===

func _reset_gate() -> void:
	_gate_seq.clear()
	_gate.visible = true
	_panel.visible = false
	_confirm.visible = false


func _on_gate_num(n: int) -> void:
	_gate_seq.append(n)
	# 正しい先頭列か確認。違ったらやり直し。
	for i in range(_gate_seq.size()):
		if _gate_seq[i] != i + 1:
			_gate_seq.clear()
			return
	if _gate_seq.size() >= 3:
		_gate.visible = false
		_panel.visible = true


# === 設定の動作 ===

func _toggle_sound() -> void:
	_muted = not _muted
	AudioServer.set_bus_mute(0, _muted)  # 0 = Master
	_update_sound_label()


func _update_sound_label() -> void:
	if _sound_btn:
		_sound_btn.text = "おと: オフ" if _muted else "おと: オン"


func _update_play_label() -> void:
	if _play_label and _gs:
		_play_label.text = "あそんだ かいすう: %d かい" % int(_gs.get("play_count"))


func _ask_delete() -> void:
	_panel.visible = false
	_confirm.visible = true


func _do_delete() -> void:
	# セーブを消して最初から(シーン再読込で全状態をリセット)。
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	get_tree().paused = false
	get_tree().reload_current_scene()


# === UI ヘルパー(コードでカード/ボタンを組む) ===

func _make_card(size: Vector2) -> Panel:
	var p := Panel.new()
	p.anchor_left = 0.5
	p.anchor_top = 0.5
	p.anchor_right = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -size.x * 0.5
	p.offset_top = -size.y * 0.5
	p.offset_right = size.x * 0.5
	p.offset_bottom = size.y * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.99, 1, 1)
	sb.set_corner_radius_all(28)
	sb.set_border_width_all(5)
	sb.border_color = Color(0.49, 0.78, 0.96, 1)
	p.add_theme_stylebox_override("panel", sb)
	return p


func _make_vbox(parent: Control) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 32.0
	v.offset_top = 28.0
	v.offset_right = -32.0
	v.offset_bottom = -28.0
	v.add_theme_constant_override("separation", 18)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(v)
	return v


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _button(text: String, font_size: int, min_size: Vector2, bg: Color = Color(0.49, 0.78, 0.96)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", font_size)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(16)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", sb)
	b.add_theme_stylebox_override("focus", sb)
	var sb2 := StyleBoxFlat.new()
	sb2.bg_color = bg.darkened(0.25)
	sb2.set_corner_radius_all(16)
	b.add_theme_stylebox_override("pressed", sb2)
	return b
