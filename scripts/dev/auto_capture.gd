extends Node

# 開発用: シーンを少し待ってからスクリーンショットを撮り、ゲームを終了する。
# Claude Code が見た目を自動確認するために使う(scenes/dev/AutoCapture.tscn から呼ばれる)。
#
# モード:
#   SINGLE        : 1 枚だけ撮影
#   FOUR_TIMES    : DayNightCycle.time_of_day を 0.25/0.50/0.75/0.95 に切替えて 4 枚
#   AUTO_RIDE     : 最寄り電車に強制乗車して屋根上視点を撮影 → 降車後を撮影(乗車システム検証)
# 視点モード:
#   PLAYER / BIRD / SIDE

enum ViewMode { PLAYER, BIRD, SIDE, LAKE, TRAIN_CLOSE, STATION, ANIMAL, STEAM, CHAR, TOWN, TUNNEL }
enum CaptureMode { SINGLE, FOUR_TIMES, AUTO_RIDE, AUTO_BEFRIEND, AUTO_BOOK }

const DELAY_SEC: float = 2.0
const VIEW: ViewMode = ViewMode.PLAYER
const MODE: CaptureMode = CaptureMode.SINGLE
const SCREENSHOT_PATH: String = "user://screenshot.png"


func _ready() -> void:
	# 検証スクショではタイトル画面を隠す
	var title := get_tree().root.find_child("TitleScreen", true, false)
	if title:
		title.visible = false
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
		CaptureMode.AUTO_RIDE:
			await _capture_ride()
		CaptureMode.AUTO_BEFRIEND:
			await _capture_befriend()
		CaptureMode.AUTO_BOOK:
			await _capture_book()
	get_tree().quit()


# 図鑑検証: GameState に発見をいくつか入れ、図鑑を開いて でんしゃ/どうぶつ タブを撮る。
func _capture_book() -> void:
	var gs := get_tree().root.find_child("GameState", true, false)
	if gs:
		gs.call("add_star")
		gs.call("add_star")
		gs.call("add_star")
		gs.call("add_befriended", "usagi")
		gs.call("add_befriended", "neko")
		gs.call("add_boarded", "hayabusa")
		gs.call("add_station", "midori")
	var book := get_tree().root.find_child("BookOverlay", true, false)
	if book == null:
		print("[AutoCapture] BookOverlay not found")
		await _save_screenshot(SCREENSHOT_PATH)
		return
	book.call("open")
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_book_train.png")
	book.call("_show_tab", "animal")
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_book_animal.png")


# なかよし検証: プレイヤーをうさぎの隣にテレポートし、AnimalManager の
# 近接検知 → なかよし成立 → HUD 通知 を撮る。
func _capture_befriend() -> void:
	var player := get_tree().root.find_child("Player", true, false) as Node3D
	var usagi := get_tree().root.find_child("Usagi", true, false) as Node3D
	if player == null or usagi == null:
		print("[AutoCapture] Player/Usagi not found, falling back to single")
		await _save_screenshot(SCREENSHOT_PATH)
		return
	player.global_position = usagi.global_position + Vector3(2.0, 0.0, 0.0)
	await get_tree().process_frame  # AnimalManager が近接検知して befriend
	await get_tree().create_timer(0.4).timeout  # 通知のフェードイン + 喜びジャンプ
	await _save_screenshot("user://screenshot_befriend.png")


# 乗車システムの検証: 本物の RideController._do_board / _do_alight を呼んで
# 屋根上カメラと降車後プレイヤー位置を無人で撮る(フェードは介さず即時切替)。
func _capture_ride() -> void:
	var rc := get_tree().root.find_child("RideController", true, false)
	var trains := get_tree().root.find_child("Trains", true, false)
	if rc == null or trains == null or trains.get_child_count() == 0:
		print("[AutoCapture] RideController/Trains not found, falling back to single")
		await _save_screenshot(SCREENSHOT_PATH)
		return
	var train := trains.get_child(0)  # Hayabusa(initial_t=0)
	rc._do_board(train)
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_ride.png")
	rc._do_alight()
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_alight.png")


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
		cam.global_position = Vector3(0, 430, 430)
		cam.look_at(Vector3.ZERO)
		cam.fov = 60.0
	elif VIEW == ViewMode.SIDE:
		cam.global_position = Vector3(300, 70, 300)
		cam.look_at(Vector3(0, 8, 0))
		cam.fov = 62.0
	elif VIEW == ViewMode.LAKE:
		# 湖(-88,140)+ SL ループ(線路が水上→自動橋脚)を斜め見下ろし
		cam.global_position = Vector3(-40, 22, 200)
		cam.look_at(Vector3(-88, 0, 140))
		cam.fov = 60.0
	elif VIEW == ViewMode.TRAIN_CLOSE:
		# 中央の立体交差(高架つばめ +8m + 橋脚)と中央ループを近くから
		cam.global_position = Vector3(135, 34, 95)
		cam.look_at(Vector3(35, 8, -10))
		cam.fov = 55.0
	elif VIEW == ViewMode.STATION:
		# みどり駅(はやぶさ本線 ratio0 ≈ (285,0))を斜めから
		cam.global_position = Vector3(318, 14, 30)
		cam.look_at(Vector3(288, 3, 0))
		cam.fov = 56.0
	elif VIEW == ViewMode.ANIMAL:
		# うさぎ(home 8,12 付近)に寄って造形を確認
		cam.global_position = Vector3(12, 3.5, 3)
		cam.look_at(Vector3(7, 1.2, 13))
		cam.fov = 50.0
	elif VIEW == ViewMode.STEAM:
		# SL人吉(湖ループ -88,140)の蒸気を撮る
		cam.global_position = Vector3(-130, 10, 150)
		cam.look_at(Vector3(-95, 4, 138))
		cam.fov = 52.0
	elif VIEW == ViewMode.CHAR:
		# プレイヤー(初期 (0,0,0) 付近、yaw0 で -Z を向く)の顔を斜め前から
		cam.global_position = Vector3(1.3, 1.7, -3.8)
		cam.look_at(Vector3(0, 1.2, 0))
		cam.fov = 42.0
	elif VIEW == ViewMode.TOWN:
		# メインの街(150,45、やまのて線の内側)を斜め上から
		cam.global_position = Vector3(150, 30, 110)
		cam.look_at(Vector3(150, 3, 45))
		cam.fov = 58.0
	elif VIEW == ViewMode.TUNNEL:
		# トンネル(つばさ/山B ふもと ≈ (-190,-138) 付近)
		cam.global_position = Vector3(-150, 28, -95)
		cam.look_at(Vector3(-188, 8, -135))
		cam.fov = 55.0
	print("[AutoCapture] debug camera applied: ", VIEW, " pos=", cam.global_position)
