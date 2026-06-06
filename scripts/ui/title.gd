extends CanvasLayer

# スタート画面。「だれで あそぶ?」で主人公を選び、「はじめる」でプレイ開始。
# 「はじめる」押下が「最初のユーザー操作」になるので、ブラウザの AudioContext が
# 有効化され、以降の効果音が鳴るようになる(Web の自動再生制限への対応)。
#
# 主人公の選択は character_roster.gd を参照して 絵カードを並べる。タップで Player の
# 見た目を即切替し(背景が半透明なので 後ろで切り替わるのが見える)、GameState に保存。

const CharacterRoster = preload("res://scripts/entities/characters/character_roster.gd")

signal started  # 「はじめる」でプレイ開始(ミッション案内などの合図に使う)

@onready var start_btn: BaseButton = $Root/Center/VBox/StartButton
@onready var root: Control = $Root
@onready var _vbox: VBoxContainer = $Root/Center/VBox

# id -> 絵カード Button(選択ハイライトの更新用)
var _cards: Dictionary = {}
var _selected_id: String = "driver"


func _ready() -> void:
	start_btn.pressed.connect(_on_start)
	# 念のため、押下時のミュート解除に備えてオーディオバスを有効化
	AudioServer.set_bus_mute(0, false)
	_build_character_select()


func _on_start() -> void:
	start_btn.disabled = true
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		visible = false
		started.emit())  # タイトルが消えてから 最初のミッションを案内


# === 「だれで あそぶ?」主人公えらび ===

func _build_character_select() -> void:
	_selected_id = _current_id()

	# 見出し
	var heading := Label.new()
	heading.text = "だれで あそぶ?"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 40)
	heading.add_theme_color_override("font_color", Color(0.157, 0.408, 0.788))
	heading.add_theme_color_override("font_outline_color", Color(1, 1, 1))
	heading.add_theme_constant_override("outline_size", 8)
	_vbox.add_child(heading)
	_vbox.move_child(heading, start_btn.get_index())

	# 絵カードを よこ に ならべる
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_vbox.add_child(row)
	_vbox.move_child(row, start_btn.get_index())

	for entry in CharacterRoster.CHARACTERS:
		var card := _make_card(entry)
		row.add_child(card)
		_cards[entry["id"]] = card

	_refresh_cards()


# 1枚の絵カード(その子のイメージ色 + ひらがなの名前)。タッチターゲットは大きく。
func _make_card(entry: Dictionary) -> Button:
	var id: String = entry["id"]
	var tint: Color = entry["tint"]
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(240, 170)
	btn.text = entry["name"]
	btn.add_theme_font_size_override("font_size", 34)
	btn.add_theme_color_override("font_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_outline_color", tint.darkened(0.45))
	btn.add_theme_constant_override("outline_size", 8)
	# 通常・押下・ホバーすべて 同じ色のまるカード(子供が押しやすい)
	for sname in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(sname, _card_style(tint, false))
	btn.pressed.connect(_on_card_pressed.bind(id))
	return btn


func _card_style(tint: Color, selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	var r := 32
	sb.corner_radius_top_left = r
	sb.corner_radius_top_right = r
	sb.corner_radius_bottom_left = r
	sb.corner_radius_bottom_right = r
	# 選んでいるカードは 白くて太いふちで強調
	var bw := 8 if selected else 3
	sb.border_width_left = bw
	sb.border_width_top = bw
	sb.border_width_right = bw
	sb.border_width_bottom = bw
	sb.border_color = Color(1, 1, 1) if selected else tint.darkened(0.3)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	return sb


func _on_card_pressed(id: String) -> void:
	if id == _selected_id:
		return
	_selected_id = id
	# Player の見た目を 即切替(GameState への保存も Player.set_character がやる)
	var player := get_tree().get_root().find_child("Player", true, false)
	if player and player.has_method("set_character"):
		player.set_character(id)
	_refresh_cards()


# 選択中のカードを強調表示し直す。
func _refresh_cards() -> void:
	for entry in CharacterRoster.CHARACTERS:
		var id: String = entry["id"]
		var card: Button = _cards.get(id)
		if card == null:
			continue
		var sel: bool = (id == _selected_id)
		card.add_theme_stylebox_override("normal", _card_style(entry["tint"], sel))
		card.add_theme_stylebox_override("hover", _card_style(entry["tint"], sel))
		card.add_theme_stylebox_override("pressed", _card_style(entry["tint"], sel))
		card.add_theme_stylebox_override("focus", _card_style(entry["tint"], sel))
		# 選んでいる子は ちょっと 大きく(ぷにっと)
		card.pivot_offset = card.custom_minimum_size * 0.5
		var tw := create_tween()
		tw.tween_property(card, "scale", Vector2(1.08, 1.08) if sel else Vector2.ONE, 0.18) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# いま選ばれている主人公 id(GameState から。無ければ既定)。
func _current_id() -> String:
	var gs := get_tree().get_root().find_child("GameState", true, false)
	if gs and "selected_character" in gs and CharacterRoster.is_valid(gs.selected_character):
		return gs.selected_character
	return CharacterRoster.DEFAULT_ID
