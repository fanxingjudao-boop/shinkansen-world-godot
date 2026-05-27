extends Control

# 仮想 D-pad + アクションボタンによるタッチ入力。
# 各ボタンの press/release を InputMap action にブリッジするので、
# Player は Input.get_vector() / Input.is_action_just_pressed() で
# キーボードと統一的に扱える。

@onready var btn_up: BaseButton = $DPad/Up
@onready var btn_down: BaseButton = $DPad/Down
@onready var btn_left: BaseButton = $DPad/Left
@onready var btn_right: BaseButton = $DPad/Right
@onready var btn_jump: BaseButton = $ActionButtons/Jump
@onready var btn_touch: BaseButton = $ActionButtons/Touch

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bind(btn_up, "move_forward")
	_bind(btn_down, "move_back")
	_bind(btn_left, "move_left")
	_bind(btn_right, "move_right")
	_bind(btn_jump, "jump")
	_bind(btn_touch, "interact")

func _bind(btn: BaseButton, action: StringName) -> void:
	if btn == null:
		return
	btn.button_down.connect(func(): Input.action_press(action))
	btn.button_up.connect(func(): Input.action_release(action))
