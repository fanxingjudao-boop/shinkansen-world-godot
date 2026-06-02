extends CanvasLayer

# 図鑑(ずかん)オーバーレイ。
# でんしゃ / どうぶつ / えき の 3 タブ。発見済みは名前+色、未発見は「?」。
# マスターは resources/*_data/ の .tres を走査して取得し、GameState の発見状態と照合。
# 開いている間は get_tree().paused = true(world は止まるが、本 CanvasLayer は
# process_mode = Always なのでボタン操作できる)。

const COLS: int = 4

const TAB_DIRS: Dictionary = {
	"train": "res://resources/train_data/",
	"animal": "res://resources/animal_data/",
	"station": "res://resources/station_data/",
}

@export var game_state_path: NodePath

var _game_state: Node
var _current_tab: String = "train"

# でんしゃの詳細パネル(セルをタップで表示)。コードで一度だけ組み立てて使い回す。
var _detail: Panel
var _detail_swatch: ColorRect
var _detail_name: Label
var _detail_desc: Label
var _detail_speed: Label

@onready var grid: GridContainer = $Root/Panel/VBox/Grid
@onready var tab_train: BaseButton = $Root/Panel/VBox/Tabs/TabTrain
@onready var tab_animal: BaseButton = $Root/Panel/VBox/Tabs/TabAnimal
@onready var tab_station: BaseButton = $Root/Panel/VBox/Tabs/TabStation
@onready var close_btn: BaseButton = $Root/Panel/VBox/Close


func _ready() -> void:
	_game_state = get_node_or_null(game_state_path)
	visible = false
	tab_train.pressed.connect(func() -> void: _show_tab("train"))
	tab_animal.pressed.connect(func() -> void: _show_tab("animal"))
	tab_station.pressed.connect(func() -> void: _show_tab("station"))
	close_btn.pressed.connect(close)


func open() -> void:
	visible = true
	get_tree().paused = true
	_show_tab(_current_tab)


func close() -> void:
	get_tree().paused = false
	visible = false


func _show_tab(tab: String) -> void:
	_current_tab = tab
	_hide_detail()
	for c in grid.get_children():
		c.queue_free()
	for e in _load_master(tab):
		grid.add_child(_make_cell(e))


# === マスターデータ読込 ===

# 戻り: [{slug, name, color, found}, ...]
func _load_master(tab: String) -> Array:
	var out: Array = []
	var dir_path: String = TAB_DIRS.get(tab, "")
	if dir_path == "":
		return out
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	var files := d.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".tres"):
			continue
		var res := ResourceLoader.load(dir_path + f)
		if res == null:
			continue
		var slug: String = str(res.get("slug"))
		var entry: Dictionary = {
			"slug": slug,
			"name": str(res.get("display_name")),
		}
		match tab:
			"train":
				entry["color"] = res.get("body_color")
				entry["found"] = _game_state != null and _game_state.has_train(slug)
				entry["desc"] = str(res.get("description"))
				entry["speed"] = int(res.get("top_speed_kmh"))
			"animal":
				entry["color"] = res.get("body_color")
				entry["found"] = _game_state != null and _game_state.has_animal(slug)
			"station":
				entry["color"] = res.get("main_color")
				entry["found"] = _game_state != null and _game_state.has_station(slug)
		out.append(entry)
	return out


# === セル生成 ===

func _make_cell(e: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(170, 120)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(v)

	var found: bool = e.get("found", false)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(0, 56)
	swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swatch.color = (e.get("color") as Color) if found else Color(0.78, 0.78, 0.8)
	v.add_child(swatch)

	var label := Label.new()
	label.text = str(e.get("name")) if found else "?"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	var col := Color(0.2, 0.25, 0.35) if found else Color(0.6, 0.6, 0.65)
	label.add_theme_color_override("font_color", col)
	v.add_child(label)

	# でんしゃタブで発見済みなら、タップで詳細(説明・最高速度)を出す。
	# 透明なボタンを上に重ねてタップを拾う(見た目は panel のまま)。
	if _current_tab == "train" and found:
		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.pressed.connect(func() -> void: _show_detail(e))
		panel.add_child(btn)

	return panel


# === でんしゃの詳細パネル ===

func _show_detail(e: Dictionary) -> void:
	_ensure_detail()
	_detail_swatch.color = e.get("color") as Color
	_detail_name.text = str(e.get("name"))
	_detail_desc.text = str(e.get("desc"))
	var spd: int = int(e.get("speed"))
	_detail_speed.text = ("さいこうそく %d キロ" % spd) if spd > 0 else ""
	_detail.visible = true


func _hide_detail() -> void:
	if _detail:
		_detail.visible = false


# 詳細パネルを一度だけ組み立てる(中央オーバーレイ。もどるで閉じる)。
func _ensure_detail() -> void:
	if _detail:
		return
	var root := $Root
	_detail = Panel.new()
	_detail.anchor_left = 0.5
	_detail.anchor_top = 0.5
	_detail.anchor_right = 0.5
	_detail.anchor_bottom = 0.5
	_detail.offset_left = -320.0
	_detail.offset_top = -250.0
	_detail.offset_right = 320.0
	_detail.offset_bottom = 250.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.98, 0.99, 1, 1)
	sb.set_corner_radius_all(28)
	sb.set_border_width_all(5)
	sb.border_color = Color(0.49, 0.78, 0.96, 1)
	_detail.add_theme_stylebox_override("panel", sb)
	root.add_child(_detail)

	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 32.0
	v.offset_top = 28.0
	v.offset_right = -32.0
	v.offset_bottom = -28.0
	v.add_theme_constant_override("separation", 18)
	_detail.add_child(v)

	_detail_swatch = ColorRect.new()
	_detail_swatch.custom_minimum_size = Vector2(0, 150)
	v.add_child(_detail_swatch)

	_detail_name = Label.new()
	_detail_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_name.add_theme_font_size_override("font_size", 48)
	_detail_name.add_theme_color_override("font_color", Color(0.157, 0.408, 0.788, 1))
	v.add_child(_detail_name)

	_detail_desc = Label.new()
	_detail_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_detail_desc.add_theme_font_size_override("font_size", 30)
	_detail_desc.add_theme_color_override("font_color", Color(0.2, 0.25, 0.35))
	_detail_desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_detail_desc)

	_detail_speed = Label.new()
	_detail_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail_speed.add_theme_font_size_override("font_size", 36)
	_detail_speed.add_theme_color_override("font_color", Color(0.85, 0.45, 0.1))
	v.add_child(_detail_speed)

	var back := Button.new()
	back.custom_minimum_size = Vector2(0, 64)
	back.text = "もどる"
	back.add_theme_font_size_override("font_size", 30)
	back.add_theme_color_override("font_color", Color(1, 1, 1))
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.49, 0.78, 0.96, 1)
	bsb.set_corner_radius_all(16)
	back.add_theme_stylebox_override("normal", bsb)
	back.add_theme_stylebox_override("hover", bsb)
	back.add_theme_stylebox_override("focus", bsb)
	var bsb2 := StyleBoxFlat.new()
	bsb2.bg_color = Color(0.157, 0.408, 0.788, 1)
	bsb2.set_corner_radius_all(16)
	back.add_theme_stylebox_override("pressed", bsb2)
	back.pressed.connect(_hide_detail)
	v.add_child(back)
