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
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
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

	return panel
