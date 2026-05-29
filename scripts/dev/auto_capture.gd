extends Node

# 開発用: シーンを少し待ってからスクリーンショットを撮り、ゲームを終了する。
# Claude Code が見た目を自動確認するために使う(scenes/dev/AutoCapture.tscn から呼ばれる)。
#
# モード:
#   SINGLE        : 1 枚だけ撮影
#   FOUR_TIMES    : DayNightCycle.time_of_day を 0.25/0.50/0.75/0.95 に切替えて 4 枚
# 視点モード:
#   PLAYER / BIRD / SIDE

enum ViewMode { PLAYER, BIRD, SIDE, LAKE }
enum CaptureMode { SINGLE, FOUR_TIMES }

const DELAY_SEC: float = 2.0
const VIEW: ViewMode = ViewMode.PLAYER
const MODE: CaptureMode = CaptureMode.SINGLE
const SCREENSHOT_PATH: String = "user://screenshot.png"


func _ready() -> void:
	await get_tree().create_timer(DELAY_SEC).timeout
	_apply_debug_camera()

	match MODE:
		CaptureMode.SINGLE:
			# debug カメラ変更を 1 フレーム描画させてから撮影
			await get_tree().process_frame
			await get_tree().process_frame
			await _save_screenshot(SCREENSHOT_PATH)
		CaptureMode.FOUR_TIMES:
			await _capture_four_times()
	get_tree().quit()


func _capture_four_times() -> void:
	var dn := get_tree().root.find_child("DayNightCycle", true, false)
	if dn == null:
		print("[AutoCapture] DayNightCycle not found, falling back to single capture")
		await _save_screenshot(SCREENSHOT_PATH)
		return
	dn.paused = true
	var schedule: Array = [
		{ "t": 0.25, "name": "screenshot_morning.png" },
		{ "t": 0.50, "name": "screenshot_noon.png" },
		{ "t": 0.75, "name": "screenshot_sunset.png" },
		{ "t": 0.95, "name": "screenshot_night.png" },
	]
	for entry in schedule:
		dn.time_of_day = entry.t
		# Light position/color の変更を 1 フレーム描画させる
		await get_tree().process_frame
		await get_tree().process_frame
		await _save_screenshot("user://" + entry.name)


func _save_screenshot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	if err != OK:
		print("[AutoCapture] save failed (%d): %s" % [err, path])
	else:
		print("[AutoCapture] saved %s" % ProjectSettings.globalize_path(path))


func _apply_debug_camera() -> void:
	if VIEW == ViewMode.PLAYER:
		return
	var cam := get_tree().root.find_child("Camera3D", true, false) as Camera3D
	if cam == null:
		print("[AutoCapture] Camera3D not found")
		return
	var parent := cam.get_parent()
	if parent and parent.get_script() != null:
		parent.set_process(false)
	if VIEW == ViewMode.BIRD:
		cam.global_position = Vector3(0, 180, 180)
		cam.look_at(Vector3.ZERO)
		cam.fov = 55.0
	elif VIEW == ViewMode.SIDE:
		cam.global_position = Vector3(150, 30, 150)
		cam.look_at(Vector3.ZERO)
		cam.fov = 60.0
	elif VIEW == ViewMode.LAKE:
		# 湖(-50, ?, 80)の上を斜め見下ろし
		cam.global_position = Vector3(-50, 15, 110)
		cam.look_at(Vector3(-50, -3, 80))
		cam.fov = 60.0
	print("[AutoCapture] debug camera applied: ", VIEW, " pos=", cam.global_position)
