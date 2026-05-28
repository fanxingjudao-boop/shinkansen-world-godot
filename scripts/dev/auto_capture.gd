extends Node

# 開発用: シーンを少し待ってからスクリーンショットを撮り、ゲームを終了する。
# Claude Code が見た目を自動確認するために使う(scenes/dev/AutoCapture.tscn から呼ばれる)。
# 視点モードは VIEW で切り替え可能(俯瞰 / プレイヤー / 横から)。

enum ViewMode { PLAYER, BIRD, SIDE }

const SCREENSHOT_PATH: String = "user://screenshot.png"
const DELAY_SEC: float = 2.0
const VIEW: ViewMode = ViewMode.PLAYER


func _ready() -> void:
	await get_tree().create_timer(DELAY_SEC).timeout
	_apply_debug_camera()
	# カメラ移動後にもう 1 フレーム待ってから撮影
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(SCREENSHOT_PATH)
	if err != OK:
		print("[AutoCapture] save failed: %d" % err)
	else:
		print("[AutoCapture] saved to %s" % ProjectSettings.globalize_path(SCREENSHOT_PATH))
	get_tree().quit()


func _apply_debug_camera() -> void:
	if VIEW == ViewMode.PLAYER:
		return  # 通常のゲームカメラのまま
	var cam := get_tree().root.find_child("Camera3D", true, false) as Camera3D
	if cam == null:
		print("[AutoCapture] Camera3D not found")
		return
	# CameraRig による追従を無効化するため、カメラを Rig から切り離す
	var parent := cam.get_parent()
	if parent and parent.get_script() != null:
		# parent (CameraRig) の _process を止めるため、set_process(false)
		parent.set_process(false)
	if VIEW == ViewMode.BIRD:
		cam.global_position = Vector3(0, 180, 180)
		cam.look_at(Vector3(0, 0, 0))
		cam.fov = 55.0
	elif VIEW == ViewMode.SIDE:
		cam.global_position = Vector3(150, 30, 150)
		cam.look_at(Vector3(0, 0, 0))
		cam.fov = 60.0
	print("[AutoCapture] debug camera applied: ", VIEW, " pos=", cam.global_position)
