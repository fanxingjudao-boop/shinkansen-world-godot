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
@onready var btn_nagame: BaseButton = $ActionButtons/Nagame
@onready var prompt: Label = $Prompt
@onready var notice: Label = $Notice
@onready var fade: ColorRect = $Fade
@onready var star_count_label: Label = $InfoMenu/StarCount
@onready var friend_count_label: Label = $InfoMenu/FriendCount
@onready var energy_count_label: Label = $InfoMenu/EnergyCount
@onready var btn_book: BaseButton = $BookButton
@onready var btn_menu: BaseButton = $MenuButton
@onready var info_menu: Panel = $InfoMenu
@onready var mission_label: Label = $InfoMenu/Mission
@onready var btn_cam_left: BaseButton = $CameraButtons/CamLeft
@onready var btn_cam_right: BaseButton = $CameraButtons/CamRight
# うんてんしゅモード関連
@onready var btn_unten: BaseButton = $ActionButtons/Unten
@onready var drive_buttons: Control = $DriveButtons
@onready var btn_go: BaseButton = $DriveButtons/Go
@onready var btn_stop: BaseButton = $DriveButtons/Stop
@onready var branch_choice: Control = $BranchChoice
@onready var btn_branch_left: BaseButton = $BranchChoice/Left
@onready var btn_branch_right: BaseButton = $BranchChoice/Right

@export var game_state_path: NodePath
@export var book_path: NodePath

var _notice_tween: Tween
var _game_state: Node
var _book: Node
var _camera_rig: Node
var _ride_controller: Node

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bind(btn_up, "move_forward")
	_bind(btn_down, "move_back")
	_bind(btn_left, "move_left")
	_bind(btn_right, "move_right")
	_bind(btn_jump, "jump")

	_game_state = get_node_or_null(game_state_path)
	if _game_state and _game_state.has_signal("changed"):
		_game_state.changed.connect(_on_state_changed)
		_on_state_changed()
	_book = get_node_or_null(book_path)
	if btn_book:
		btn_book.pressed.connect(_on_book_pressed)
	# 「メニュー」ボタン: 押すたびに情報パネル(ほし/なかよし/げんき/ミッション)を出し入れ
	if btn_menu:
		btn_menu.pressed.connect(_on_menu_pressed)

	# タッチ/おりる ボタンは pressed シグナルで直接 RideController を呼ぶ
	# (interact action のエッジ検出はタッチ/Web で取りこぼしうるため。降車不可の対策)
	_ride_controller = get_tree().root.find_child("RideController", true, false)
	if btn_touch:
		btn_touch.pressed.connect(_on_touch_pressed)
	# 「ながめ」ボタン: 乗車中だけ表示し、押すと車内視点を巡回
	if btn_nagame:
		btn_nagame.pressed.connect(_on_nagame_pressed)

	# うんてんしゅモードのボタン群を RideController へ橋渡し(btn_nagame と同方式)
	if btn_unten:
		btn_unten.pressed.connect(_on_unten_pressed)
	if btn_go:
		btn_go.pressed.connect(func() -> void: _call_rc("driver_go"))
	if btn_stop:
		btn_stop.pressed.connect(func() -> void: _call_rc("driver_stop"))
	if btn_branch_left:
		btn_branch_left.pressed.connect(func() -> void: _call_rc("take_branch"))
	if btn_branch_right:
		btn_branch_right.pressed.connect(func() -> void: _call_rc("keep_straight"))

	# カメラ向きボタン(CameraRig をシーンから探して回転を依頼)
	_camera_rig = get_tree().root.find_child("CameraRig", true, false)
	if btn_cam_left:
		btn_cam_left.pressed.connect(func() -> void: _rotate_camera(-1))
	if btn_cam_right:
		btn_cam_right.pressed.connect(func() -> void: _rotate_camera(1))

	for b in [btn_up, btn_down, btn_left, btn_right, btn_jump, btn_touch, btn_book, btn_menu, btn_cam_left, btn_cam_right, btn_nagame, btn_unten, btn_go, btn_stop, btn_branch_left, btn_branch_right]:
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
	if btn_nagame:
		btn_nagame.visible = is_riding  # 乗車中だけ「ながめ」ボタンを出す
	if btn_unten:
		btn_unten.visible = is_riding   # 乗車中だけ「うんてん」ボタンを出す
	if not is_riding:
		set_driving(false)              # 降車時は運転 UI を必ず畳む
	for b in [btn_up, btn_down, btn_left, btn_right]:
		if b:
			b.disabled = is_riding
			b.modulate = Color(1, 1, 1, 0.35) if is_riding else Color(1, 1, 1, 1)


# 運転手モードの ON/OFF で「ゴー/とまれ」表示と「うんてん」ボタンの文言を出し分け。
func set_driving(on: bool) -> void:
	if drive_buttons:
		drive_buttons.visible = on
	if btn_unten:
		btn_unten.text = "じどう" if on else "うんてん"  # トグル状態を明示
	if not on:
		hide_branch_choice()


# 分岐の2択を表示。Left=「のりかえ」(行き先名・色)/ Right=「このまま まっすぐ」(直進)。
func show_branch_choice(dest_name: String, dest_color: Color) -> void:
	if branch_choice == null:
		return
	if btn_branch_left:
		btn_branch_left.text = "%s に のりかえ" % dest_name
		btn_branch_left.modulate = dest_color.lerp(Color.WHITE, 0.45)
	branch_choice.visible = true


func hide_branch_choice() -> void:
	if branch_choice:
		branch_choice.visible = false

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
	if energy_count_label:
		energy_count_label.text = "げんき %d" % _game_state.energy

func set_mission(text: String) -> void:
	if mission_label:
		mission_label.text = "ミッション: " + text

func _on_book_pressed() -> void:
	if _book and _book.has_method("open"):
		_book.open()

# 「メニュー」ボタン: 情報パネルの表示/非表示をトグル(押したら出る・もう一度で隠れる)
func _on_menu_pressed() -> void:
	if info_menu:
		info_menu.visible = not info_menu.visible

# タッチ/おりる ボタン: RideController に乗降トグルを依頼(タップごとに確実に発火)。
func _on_touch_pressed() -> void:
	if _ride_controller and _ride_controller.has_method("toggle_ride"):
		_ride_controller.toggle_ride()

# 「ながめ」ボタン: 乗車中の視点を巡回(やね→うんてんせき→まどぎわ)。
func _on_nagame_pressed() -> void:
	if _ride_controller and _ride_controller.has_method("cycle_ride_view"):
		_ride_controller.cycle_ride_view()

# 「うんてん」ボタン: 運転手モードのトグルを RideController に依頼。
func _on_unten_pressed() -> void:
	_call_rc("toggle_driver_mode")

# RideController のメソッドを名前で安全に呼ぶ(運転モード系ボタンの共通入口)。
func _call_rc(method: String) -> void:
	if _ride_controller and _ride_controller.has_method(method):
		_ride_controller.call(method)

# カメラの向きを段階回転(CameraRig.rotate_view)。dir=-1 左/+1 右。
func _rotate_camera(dir: int) -> void:
	if _camera_rig and _camera_rig.has_method("rotate_view"):
		_camera_rig.rotate_view(dir)


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
