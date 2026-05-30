extends CanvasLayer

# スタート画面。「はじめる」ボタンを押すとフェードアウトしてプレイ開始。
# このボタン押下が「最初のユーザー操作」になるので、ブラウザの AudioContext が
# 有効化され、以降の効果音が鳴るようになる(Web の自動再生制限への対応)。

@onready var start_btn: BaseButton = $Root/Center/VBox/StartButton
@onready var root: Control = $Root


func _ready() -> void:
	start_btn.pressed.connect(_on_start)
	# 念のため、押下時のミュート解除に備えてオーディオバスを有効化
	AudioServer.set_bus_mute(0, false)


func _on_start() -> void:
	start_btn.disabled = true
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void: visible = false)
