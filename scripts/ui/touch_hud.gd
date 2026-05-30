extends Control

# 仮想 D-pad + アクションボタンによるタッチ入力。
# 各ボタンの press/release を InputMap action にブリッジするので、
# Player は Input.get_vector() / Input.is_action_just_pressed() で
# キーボードと統一的に扱える。
#
# 乗車システム(ride_controller.gd)からの依頼で、
# 「のる?」プロンプト・「のったよ!」通知・フェード・ボタン文言の出し分けも担当する。

@onready var btn_up: BaseButton = $DPad/Up
@onready var btn_down: BaseButton = $DPad/Down
@onready var btn_left: BaseButton = $DPad/Left
@onready var btn_right: BaseButton = $DPad/Right
@onready var btn_jump: BaseButton = $ActionButtons/Jump
@onready var btn_touch: BaseButton = $ActionButtons/Touch
@onready var prompt: Label = $Prompt
@onready var notice: Label = $Notice
@onready var fade: ColorRect = $Fade
@onready var star_count_label: Label = $TopBar/StarCount
@onready var friend_count_label: Label = $TopBar/FriendCount
@onready var btn_book: BaseButton = $TopBar/BookButton

@export var game_state_path: NodePath
@export var book_path: NodePath

var _notice_tween: Tween
var _game_state: Node
var _book: Node

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bind(btn_up, "move_forward")
	_bind(btn_down, "move_back")
	_bind(btn_left, "move_left")
	_bind(btn_right, "move_right")
	_bind(btn_jump, "jump")
	_bind(btn_touch, "interact")

	_game_state = get_node_or_null(game_state_path)
	if _game_state and _game_state.has_signal("changed"):
		_game_state.changed.connect(_on_state_changed)
		_on_state_changed()
	_book = get_node_or_null(book_path)
	if btn_book:
		btn_book.pressed.connect(_on_book_pressed)

	for b in [btn_up, btn_down, btn_left, btn_right, btn_jump, btn_touch, btn_book]:
		_add_press_bounce(b)

func _bind(btn: BaseButton, action: StringName) -> void:
	if btn == null:
		return
	btn.button_down.connect(func(): Input.action_press(action))
	btn.button_up.connect(func(): Input.action_release(action))


# === 乗車システム用 public API(ride_controller.gd から呼ばれる) ===

# 「○○に のる?」プロンプトを表示
func show_board_prompt(train_name: String) -> void:
	if prompt == null:
		return
	prompt.text = "%sに のる?" % train_name
	prompt.visible = true

func hide_board_prompt() -> void:
	if prompt:
		prompt.visible = false

# 乗車中はタッチボタンを「おりる」に、D-pad を無効化(動かせないことを明示)
func set_riding(is_riding: bool) -> void:
	if btn_touch:
		btn_touch.text = "おりる" if is_riding else "タッチ"
	for b in [btn_up, btn_down, btn_left, btn_right]:
		if b:
			b.disabled = is_riding
			b.modulate = Color(1, 1, 1, 0.35) if is_riding else Color(1, 1, 1, 1)

# 「○○に のったよ!」を一定時間バウンス表示してフェードアウト
func show_notice(text: String) -> void:
	if notice == null:
		return
	notice.text = text
	notice.visible = true
	notice.modulate = Color(1, 1, 1, 0)
	notice.scale = Vector2(0.6, 0.6)
	notice.pivot_offset = notice.size * 0.5
	if _notice_tween and _notice_tween.is_valid():
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.set_parallel(true)
	# 登場(バウンス + フェードイン)
	_notice_tween.tween_property(notice, "modulate:a", 1.0, 0.25)
	_notice_tween.tween_property(notice, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 表示を保ってからフェードアウト
	_notice_tween.set_parallel(false)
	_notice_tween.tween_interval(1.6)
	_notice_tween.tween_property(notice, "modulate:a", 0.0, 0.5)
	_notice_tween.tween_callback(func(): notice.visible = false)

# フェード ColorRect の不透明度を設定(ride_controller の遷移 Tween から駆動)
func set_fade_alpha(a: float) -> void:
	if fade:
		fade.color.a = clampf(a, 0.0, 1.0)


# === カウンター / 図鑑(GameState 連携) ===

func _on_state_changed() -> void:
	if _game_state == null:
		return
	if star_count_label:
		star_count_label.text = "ほし %d" % _game_state.star_count
	if friend_count_label:
		friend_count_label.text = "なかよし %d" % _game_state.befriended_animals.size()

func _on_book_pressed() -> void:
	if _book and _book.has_method("open"):
		_book.open()


# === ボタン押下でぷにっと縮む(ease_out_back) ===

func _add_press_bounce(btn: BaseButton) -> void:
	if btn == null:
		return
	btn.button_down.connect(func() -> void: _bounce(btn, 0.88))
	btn.button_up.connect(func() -> void: _bounce(btn, 1.0))

func _bounce(btn: BaseButton, target: float) -> void:
	btn.pivot_offset = btn.size * 0.5
	var tw := create_tween()
	tw.tween_property(btn, "scale", Vector2.ONE * target, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
