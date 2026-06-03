extends CanvasLayer

# おでかけメニュー(どこへ いく?)。
# HUD の「どこへ いく?」ボタンで開く。6つの世界の 絵カードが並び、
# タップで すぐ その世界へワープ(乗り物の近くにいなくても)。
# 図鑑(book.gd)と同じ overlay 方式:開いている間は get_tree().paused=true、
# 本 CanvasLayer は process_mode=Always なのでボタンは効く。
#
# 「どこへ いく?」ボタンの表示制御は ここが担当(各世界スクリプトが
# 自分のワールドボタンを管理するのと同じ流儀):地上にいて 電車に
# 乗っていない時だけ表示(世界の中・乗車中は隠す=二重ワープを防ぐ)。

# {name, vehicle, color, node}。色は各世界の背景色に合わせる。
const WORLDS: Array = [
	{"name": "つき", "vehicle": "ロケット", "color": Color(0.72, 0.78, 0.92), "node": "MoonTrip"},
	{"name": "そら", "vehicle": "ひこうき", "color": Color(0.5, 0.72, 0.95), "node": "SkyCastle"},
	{"name": "うみ", "vehicle": "せんすいかん", "color": Color(0.25, 0.6, 0.75), "node": "Submarine"},
	{"name": "おかし", "vehicle": "おかしの きしゃ", "color": Color(1.0, 0.7, 0.82), "node": "CandyLand"},
	{"name": "きょうりゅう", "vehicle": "サファリカー", "color": Color(0.5, 0.7, 0.4), "node": "DinoLand"},
	{"name": "ゆき", "vehicle": "そり", "color": Color(0.82, 0.88, 1.0), "node": "YukiLand"},
]

@onready var grid: GridContainer = $Root/Panel/VBox/Grid
@onready var close_btn: BaseButton = $Root/Panel/VBox/Close

var _world_btn: BaseButton
var _ride: Node
var _world_nodes: Array = []     # 6つの世界ノード(キャッシュ)
var _cached: bool = false


func _ready() -> void:
	visible = false
	close_btn.pressed.connect(close)
	for w in WORLDS:
		grid.add_child(_make_card(w))
	# 「どこへ いく?」ボタンを掴んで 押下=open を配線(表示制御は _process)。
	_world_btn = get_tree().root.find_child("WorldButton", true, false) as BaseButton
	if _world_btn:
		_world_btn.pressed.connect(open)
		_world_btn.visible = false


func _process(_delta: float) -> void:
	if _world_btn == null:
		return
	_ensure_cache()
	# 地上(どの世界にもいない)+ 電車に乗っていない 時だけ「どこへ いく?」を出す。
	var riding: bool = _ride != null and _ride.has_method("is_riding") and _ride.is_riding()
	_world_btn.visible = (not riding) and (not _any_world_active())


func _ensure_cache() -> void:
	if _cached:
		return
	var root := get_tree().root
	_ride = root.find_child("RideController", true, false)
	_world_nodes.clear()
	for w in WORLDS:
		var n := root.find_child(str(w["node"]), true, false)
		if n:
			_world_nodes.append(n)
	_cached = true


func _any_world_active() -> bool:
	for n in _world_nodes:
		if n.has_method("is_active") and n.is_active():
			return true
	return false


func open() -> void:
	visible = true
	get_tree().paused = true


func close() -> void:
	get_tree().paused = false
	visible = false


# カード押下:メニューを閉じて(=paused 解除)その世界へワープ。
func _select(world: Dictionary) -> void:
	close()
	var n := get_tree().root.find_child(str(world["node"]), true, false)
	if n and n.has_method("warp_in"):
		n.warp_in()


# 世界の 絵カード(色のスウォッチ + 大きい名前 + 乗り物名 + 透明ボタン)。
func _make_card(world: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(230, 160)
	# 白い角丸 + その世界の色のフチ(かわいい額縁)。
	var card_sb := StyleBoxFlat.new()
	card_sb.bg_color = Color(1, 1, 1, 1)
	card_sb.set_corner_radius_all(20)
	card_sb.set_border_width_all(5)
	card_sb.border_color = world["color"] as Color
	panel.add_theme_stylebox_override("panel", card_sb)

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

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(0, 80)
	swatch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	swatch.color = world["color"] as Color
	v.add_child(swatch)

	var name_label := Label.new()
	name_label.text = str(world["name"])
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 34)
	name_label.add_theme_color_override("font_color", Color(0.2, 0.25, 0.35))
	v.add_child(name_label)

	var veh_label := Label.new()
	veh_label.text = str(world["vehicle"])
	veh_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	veh_label.add_theme_font_size_override("font_size", 20)
	veh_label.add_theme_color_override("font_color", Color(0.5, 0.55, 0.62))
	v.add_child(veh_label)

	# 透明ボタンを上に重ねて タップを拾う(見た目は panel のまま)。
	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(func() -> void: _select(world))
	panel.add_child(btn)

	return panel
