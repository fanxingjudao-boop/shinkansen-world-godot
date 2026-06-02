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
enum CaptureMode { SINGLE, FOUR_TIMES, AUTO_RIDE, AUTO_BEFRIEND, AUTO_BOOK, AUTO_DRIVE, AUTO_CROSSING, AUTO_COLLISION, AUTO_CASTLE, AUTO_MOON }

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
		CaptureMode.AUTO_DRIVE:
			await _capture_drive()
		CaptureMode.AUTO_CROSSING:
			await _capture_crossing()
		CaptureMode.AUTO_COLLISION:
			await _capture_collision()
		CaptureMode.AUTO_CASTLE:
			await _capture_castle()
		CaptureMode.AUTO_MOON:
			await _capture_moon()
	get_tree().quit()


# 検証: ①カメラ基準移動(うえ=カメラの前)②城に柱が無い③ロケット④月面。
func _capture_moon() -> void:
	var player := get_tree().root.find_child("Player", true, false) as CharacterBody3D
	var rig := get_tree().root.find_child("CameraRig", true, false)
	var mt := get_tree().root.find_child("MoonTrip", true, false)

	# --- ① カメラ基準移動チェック(本物の追従カメラで) ---
	if player and rig:
		player.global_position = Vector3(0, 3, 0)
		await get_tree().physics_frame
		rig.rotate_view(2)  # カメラを 90 度回す
		await get_tree().create_timer(1.2).timeout  # 回転が落ち着くまで
		var cam0 := get_viewport().get_camera_3d()
		var camfwd := -cam0.global_transform.basis.z
		camfwd.y = 0.0
		camfwd = camfwd.normalized()
		var p0 := player.global_position
		Input.action_press("move_forward")
		for i in range(36):
			await get_tree().physics_frame
		Input.action_release("move_forward")
		var disp := player.global_position - p0
		disp.y = 0.0
		var dot := disp.normalized().dot(camfwd) if disp.length() > 0.1 else 0.0
		print("[AutoCapture] cam-relative: disp_len=%.2f dot(camfwd)=%.2f (1.0=完全一致)" % [disp.length(), dot])
		rig.rotate_view(-2)  # カメラを戻す

	# 以降は debug カメラで撮影(追従を止める)
	var cam := get_viewport().get_camera_3d() as Camera3D
	var rigp := cam.get_parent()
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)

	# --- ② 城に柱が無いこと(全景) ---
	cam.global_position = Vector3(205, 46, 200)
	cam.look_at(Vector3(150, 14, 135))
	cam.fov = 60.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_castle_nopillar.png")

	# --- ③ ロケット(発射台) ---
	if mt and player:
		var rp: Vector3 = mt._rocket_pos
		player.global_position = rp + Vector3(0, -1.4, 7)
		await get_tree().physics_frame
		cam.global_position = rp + Vector3(8, 3.5, 9)
		cam.look_at(rp + Vector3(0, -0.5, 0))
		cam.fov = 52.0
		await get_tree().process_frame
		await get_tree().process_frame
		await _save_screenshot("user://screenshot_rocket.png")

	# --- ④ 月へ行って撮影 ---
	if mt:
		mt._go_moon()
		await get_tree().create_timer(1.2).timeout  # フェード+ワープ+環境切替の完了待ち
		rigp.set_process(false)  # snap で再開していないが念のため
		var moon: Vector3 = mt.MOON_POS
		cam.global_position = moon + Vector3(0, 12, 40)
		cam.look_at(moon + Vector3(0, 2, -10))
		cam.fov = 62.0
		await get_tree().process_frame
		await get_tree().process_frame
		await _save_screenshot("user://screenshot_moon.png")


# お城検証: おしろでんしゃをアーチ(ratio0.25)に置き、全景/アーチ通過/上空の高架を撮る。
func _capture_castle() -> void:
	var trains := get_tree().root.find_child("Trains", true, false)
	if trains:
		var oshiro := trains.get_node_or_null("Oshiro")
		if oshiro:
			oshiro._progress = 0.25 * 139.4  # ループ北点 = お城のアーチ
			oshiro._apply_progress()
	var cam := get_tree().root.find_child("Camera3D", true, false) as Camera3D
	if cam == null:
		await _save_screenshot(SCREENSHOT_PATH)
		return
	var parent := cam.get_parent()
	if parent and parent.get_script() != null:
		parent.set_process(false)
	# 全景(南東・上空から。お城+上空の高架ループ)
	cam.global_position = Vector3(205, 46, 200)
	cam.look_at(Vector3(150, 14, 135))
	cam.fov = 60.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_castle_overview.png")
	# アーチ(西の口から +X 方向に覗く。おしろでんしゃが通っている)
	cam.global_position = Vector3(108, 6.5, 135)
	cam.look_at(Vector3(160, 6.0, 135))
	cam.fov = 58.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_castle_arch.png")
	# 上空(高架ループを見上げる)
	cam.global_position = Vector3(150, 16, 188)
	cam.look_at(Vector3(150, 26, 135))
	cam.fov = 62.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_castle_sky.png")


# コリジョン検証: プレイヤーを建物の +Z 側に置き、建物へ向かって(move_forward=-Z)
# 1.5 秒歩かせ、壁で止まるか(すり抜けないか)を距離で判定して撮る。
func _capture_collision() -> void:
	var town := get_tree().root.find_child("Town", true, false)
	var player := get_tree().root.find_child("Player", true, false) as CharacterBody3D
	if town == null or player == null:
		print("[AutoCapture] Town/Player not found")
		await _save_screenshot(SCREENSHOT_PATH)
		return
	# 建物(StaticBody3D を子に持つ root)を 1 つ探す
	var target: Node3D = null
	for child in town.get_children():
		for sub in child.get_children():
			if sub is StaticBody3D:
				target = child
				break
		if target:
			break
	if target == null:
		print("[AutoCapture] 建物(StaticBody)が見つからない")
		await _save_screenshot(SCREENSHOT_PATH)
		return
	var bpos: Vector3 = target.global_position
	# プレイヤーを建物の +Z 側 6m に配置
	player.global_position = bpos + Vector3(0.0, 1.2, 6.0)
	player.velocity = Vector3.ZERO
	await get_tree().physics_frame
	var start_dz: float = player.global_position.z - bpos.z
	# 建物へ向かって(-Z)歩く
	Input.action_press("move_forward")
	for i in range(110):  # ~1.8 秒ぶんの物理フレーム
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var end_dz: float = player.global_position.z - bpos.z
	var blocked: bool = end_dz > 1.4   # 壁(半幅1.5)+カプセル(0.35)で手前に止まるはず
	print("[AutoCapture] collision: start_dz=%.2f end_dz=%.2f blocked=%s (建物center=%.1f,%.1f)" \
		% [start_dz, end_dz, str(blocked), bpos.x, bpos.z])
	# 壁ぎわのプレイヤーを横から撮る
	var cam := get_tree().root.find_child("Camera3D", true, false) as Camera3D
	if cam:
		var parent := cam.get_parent()
		if parent and parent.get_script() != null:
			parent.set_process(false)
		cam.global_position = bpos + Vector3(7.0, 3.5, 5.0)
		cam.look_at(bpos + Vector3(0, 1.2, 2.5))
		cam.fov = 55.0
		await get_tree().process_frame
		await get_tree().process_frame
	await _save_screenshot("user://screenshot_collision.png")


# 踏切検証: komachi は start_ratio=0 なので起動時 ratio0 の踏切(≈(102,-30))に編成がいて
# 「閉」状態、ratio0.25 の踏切(≈(60,6))は「開」状態のはず。両方を斜めから撮る。
func _capture_crossing() -> void:
	var cam := get_tree().root.find_child("Camera3D", true, false) as Camera3D
	if cam == null:
		await _save_screenshot(SCREENSHOT_PATH)
		return
	var parent := cam.get_parent()
	if parent and parent.get_script() != null:
		parent.set_process(false)  # CameraRig の追従を止める
	# 閉(電車が来ている): komachi ratio0 ≈ (102,-30) を線路ぎわから寄って
	cam.global_position = Vector3(108, 3.5, -24)
	cam.look_at(Vector3(102, 2.2, -30))
	cam.fov = 50.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_crossing_closed.png")
	# 開(電車がいない): komachi ratio0.25 ≈ (60,6) に寄って遮断機の上がりを確認
	cam.global_position = Vector3(66, 3.5, 12)
	cam.look_at(Vector3(60, 2.2, 6))
	cam.fov = 50.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_crossing_open.png")


# うんてんしゅモード検証: はやぶさに乗車 → 運転モード突入(ゴー/とまれ表示)→
# 分岐2択を表示 → 乗り換え(ワープ)後の前面展望を撮る。
func _capture_drive() -> void:
	var rc := get_tree().root.find_child("RideController", true, false)
	var trains := get_tree().root.find_child("Trains", true, false)
	if rc == null or trains == null or trains.get_child_count() == 0:
		print("[AutoCapture] RideController/Trains not found, falling back to single")
		await _save_screenshot(SCREENSHOT_PATH)
		return
	var train := trains.get_child(0)  # Hayabusa
	rc._do_board(train)
	await get_tree().process_frame
	rc.toggle_driver_mode()           # 運転モード突入(フェード遷移あり)
	await get_tree().create_timer(0.8).timeout
	await _save_screenshot("user://screenshot_drive.png")
	# 分岐2択を強制表示(はやぶさ→かがやき)。
	# 列車は実際には分岐手前にいないので、_check_branch が即座に隠さないよう
	# クールダウンを上げて抑止してから表示する(検証用)。
	rc._branch_cooldown = 999.0
	rc._offer_branch({ "from": "hayabusa", "at_ratio": 0.18, "to": "kagayaki", "to_ratio": 0.18 })
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_branch.png")
	rc._branch_cooldown = 0.0
	# 乗り換え(ワープ)実行 → フェード後の前面展望
	rc.take_branch()
	await get_tree().create_timer(0.8).timeout
	await _save_screenshot("user://screenshot_warp.png")


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
