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
enum CaptureMode { SINGLE, FOUR_TIMES, AUTO_RIDE, AUTO_BEFRIEND, AUTO_BOOK, AUTO_DRIVE, AUTO_CROSSING, AUTO_COLLISION, AUTO_CASTLE, AUTO_MOON, AUTO_MENU, AUTO_FIXCHECK, AUTO_SETTINGS, AUTO_SKY, AUTO_SEA, AUTO_CANDY, AUTO_DINO, AUTO_YUKI, AUTO_WORLDSEL, AUTO_REWARD, AUTO_GREET, AUTO_MUSIC, AUTO_RARE, AUTO_GINGA, AUTO_CHARSEL }

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
		CaptureMode.AUTO_MENU:
			await _capture_menu()
		CaptureMode.AUTO_FIXCHECK:
			await _fixcheck()
		CaptureMode.AUTO_SETTINGS:
			await _capture_settings()
		CaptureMode.AUTO_SKY:
			await _capture_sky()
		CaptureMode.AUTO_SEA:
			await _capture_sea()
		CaptureMode.AUTO_CANDY:
			await _capture_candy()
		CaptureMode.AUTO_DINO:
			await _capture_dino()
		CaptureMode.AUTO_YUKI:
			await _capture_yuki()
		CaptureMode.AUTO_WORLDSEL:
			await _capture_worldsel()
		CaptureMode.AUTO_REWARD:
			await _capture_reward()
		CaptureMode.AUTO_GREET:
			await _capture_greet()
		CaptureMode.AUTO_MUSIC:
			await _capture_music()
		CaptureMode.AUTO_RARE:
			await _capture_rare()
		CaptureMode.AUTO_GINGA:
			await _capture_ginga()
		CaptureMode.AUTO_CHARSEL:
			await _capture_charsel()
	get_tree().quit()


# 主人公えらび 検証: Player.set_character で うんてんしさん / きつね を切り替えて
# それぞれ接写。GameState への保存も確認。タイトルの選ぶカードも撮る。
func _capture_charsel() -> void:
	var player := get_tree().root.find_child("Player", true, false) as CharacterBody3D
	var gs := get_tree().root.find_child("GameState", true, false)
	var cam := get_viewport().get_camera_3d() as Camera3D
	if player == null or cam == null:
		await _save_screenshot(SCREENSHOT_PATH)
		return
	var rigp := cam.get_parent()
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	player.global_position = Vector3(0, 0, 0)
	player.rotation.y = 0.0   # -Z(=カメラの方)を向く
	await get_tree().physics_frame

	# 接写カメラ(顔を 斜め前から)
	cam.global_position = Vector3(1.7, 1.5, -3.7)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.fov = 42.0

	# うんてんしさん
	player.set_character("driver")
	await get_tree().create_timer(0.4).timeout
	await _save_screenshot("user://screenshot_char_driver.png")
	print("[AutoCapture] charsel driver: selected=%s" % str(gs.selected_character if gs else "?"))

	# きつね
	player.set_character("fox")
	await get_tree().create_timer(0.4).timeout
	await _save_screenshot("user://screenshot_char_fox.png")
	print("[AutoCapture] charsel fox: selected=%s (fox なら保存OK)" % str(gs.selected_character if gs else "?"))

	# きつねを 横からも(尻尾・耳の立体感)
	cam.global_position = Vector3(3.4, 1.6, -1.0)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.fov = 46.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_char_fox_side.png")

	# タイトルの選ぶカードを撮る(再表示してフルスクリーン)
	var title := get_tree().root.find_child("TitleScreen", true, false)
	if title:
		title.visible = true
		await get_tree().process_frame
		await get_tree().process_frame
		await _save_screenshot("user://screenshot_charsel_title.png")


# 親モード検証: 「おとな」→ 数字ゲート → 設定画面 を撮る。
func _capture_settings() -> void:
	var s := get_tree().root.find_child("Settings", true, false)
	if s == null:
		await _save_screenshot(SCREENSHOT_PATH)
		return
	s.open()
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_settings_gate.png")
	# ゲートを 1→2→3 で通過
	s._on_gate_num(1)
	s._on_gate_num(2)
	s._on_gate_num(3)
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_settings_panel.png")


# P0修正の動作検証(撮影なし・ログ出力): B2 分岐スワップ不変条件 / B5 ホーム登坂。
func _fixcheck() -> void:
	var rc := get_tree().root.find_child("RideController", true, false)
	var trains := get_tree().root.find_child("Trains", true, false)
	var player := get_tree().root.find_child("Player", true, false) as CharacterBody3D

	# --- B2: 分岐スワップで「1ルート1編成」が保たれるか ---
	if rc and trains:
		var haya := trains.get_node_or_null("Hayabusa")
		if haya:
			rc._do_board(haya)
			await get_tree().physics_frame
			rc.toggle_driver_mode()
			await get_tree().create_timer(0.9).timeout
			rc._branch_cooldown = 999.0  # _check_branch に消されないよう抑止
			# 各地への 遠距離分岐(本線→みずうみ sl_hitoyoshi)をテスト: フェードで載せ替え・入れ替え成立か
			rc._offer_branch({ "from": "hayabusa", "at_ratio": 0.30, "to": "sl_hitoyoshi", "to_ratio": 0.5, "label": "みずうみ" })
			rc.take_branch()  # 直後に呼ぶ(間に _process を挟まない)
			await get_tree().create_timer(1.0).timeout  # フェード+スワップ完了待ち
			var routes := {}
			var dup := false
			for t in trains.get_children():
				var rs: String = t.get_route_slug()
				if routes.has(rs):
					dup = true
				routes[rs] = true
			print("[FixCheck] 各地分岐 swap: 編成数=%d 占有ルート数=%d 重複=%s / はやぶさ編成は今 '%s' / SL編成は今 '%s'" % [
				trains.get_child_count(), routes.size(), str(dup),
				haya.get_route_slug(),
				(trains.get_node_or_null("SLHitoyoshi").get_route_slug() if trains.get_node_or_null("SLHitoyoshi") else "?")])
			rc._do_alight()
			await get_tree().physics_frame

	# --- B5: 駅ホーム(段差0.3m)へジャンプ無しで歩いて乗れるか ---
	if rc and player:
		var stations := get_tree().root.find_child("Stations", true, false)
		var st: Node3D = null
		if stations:
			for c in stations.get_children():
				if c.has_method("get_slug"):
					st = c as Node3D
					break
		if st:
			var sp := st.global_position
			# ホーム +Z 側 7m・地表より少し上に置き、カメラをスナップ(追従lerp中だと
			# カメラ基準移動の向きが定まらないため)してから move_forward(-Z=画面奥)で歩かせる
			player.global_position = sp + Vector3(0, 0.6, 7.0)
			player.set("gravity_scale", 1.0)
			var rig2 := get_tree().root.find_child("CameraRig", true, false)
			if rig2 and rig2.has_method("snap_to_target"):
				rig2.snap_to_target()
			await get_tree().physics_frame
			await get_tree().physics_frame
			var z_before := player.global_position.z
			Input.action_press("move_forward")
			for i in range(90):
				await get_tree().physics_frame
			Input.action_release("move_forward")
			var y_after := player.global_position.y
			var z_after := player.global_position.z
			var climbed: bool = (y_after - sp.y) > 0.1
			print("[FixCheck] B5 home-climb: 駅Y=%.2f 歩行後Y=%.2f Δz=%.2f 段差を登れた=%s" % [
				sp.y, y_after, z_after - z_before, str(climbed)])


# メニュー検証: 閉じた状態(メニュー/ずかんボタンだけ)→「メニュー」を押して開いた状態。
func _capture_menu() -> void:
	var hud := get_tree().root.find_child("TouchHUD", true, false)
	await _save_screenshot("user://screenshot_menu_closed.png")
	if hud and hud.has_method("_on_menu_pressed"):
		hud._on_menu_pressed()  # メニューを開く
		await get_tree().process_frame
		await get_tree().process_frame
		await _save_screenshot("user://screenshot_menu_open.png")


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

	# --- ④ 月(小さな惑星)へ行って撮影 ---
	if mt:
		mt._go_moon()
		await get_tree().create_timer(1.2).timeout  # フェード+ワープ+環境切替の完了待ち
		var moon: Vector3 = mt.MOON_POS
		var pcenter: Vector3 = moon + Vector3(0, -mt.PLANET_R, 0)
		# --- 惑星歩行の機能チェック: 前進し続けて 球面に居続ける&裏側へ回れるか ---
		rigp.set_process(true)  # 本物の追従カメラ(カメラの up が法線に合うか)
		await get_tree().create_timer(0.4).timeout
		Input.action_press("move_forward")
		var around := false
		for s in range(16):
			await get_tree().create_timer(0.4).timeout
			var r: float = player.global_position.distance_to(pcenter)
			var updot: float = (player.global_position - pcenter).normalized().dot(Vector3.UP)
			if updot < 0.0:
				around = true  # 球の下半分=裏側に回れた
			if s == 6:
				# 横っ腹あたりで プレイヤーカメラから撮影(頭が上=酔わないか)
				await _save_screenshot("user://screenshot_moon_walk.png")
			print("[AutoCapture] walk s=%d r=%.1f(=R %.0f?) updot=%.2f" % [s, r, mt.PLANET_R, updot])
		Input.action_release("move_forward")
		print("[AutoCapture] reached_backside=", around)
		# 以降は debug カメラで装飾を撮影
		rigp.set_process(false)
		# 全景(小さな惑星まるごと)
		cam.global_position = pcenter + Vector3(40, 30, 48)
		cam.look_at(pcenter)
		cam.fov = 60.0
		await get_tree().process_frame
		await get_tree().process_frame
		await _save_screenshot("user://screenshot_moon.png")
		# てっぺん(ロケット・もちつき・もちだんご)を寄りで
		cam.global_position = moon + Vector3(10, 8, 12)
		cam.look_at(moon + Vector3(0, 1.0, 0))
		cam.fov = 58.0
		await get_tree().create_timer(0.5).timeout
		await _save_screenshot("user://screenshot_moon_top.png")
		# 月面カー接写(惑星上の駐機位置)
		if mt._buggy:
			var bp: Vector3 = mt._buggy_pos
			var bn: Vector3 = (bp - pcenter).normalized()
			cam.global_position = bp + bn * 4.0 + Vector3(0, 2.5, 0)
			cam.look_at(bp)
			cam.fov = 50.0
			await get_tree().process_frame
			await get_tree().process_frame
			await _save_screenshot("user://screenshot_moon_buggy.png")
			# のる/おりる(reparent)が壊れないか機能チェック
			player.global_position = bp + bn * 1.5
			await get_tree().physics_frame
			mt._mount_buggy()
			await get_tree().physics_frame
			await get_tree().physics_frame
			print("[AutoCapture] buggy mounted=", mt._buggy_mounted, " speed=", player.get("speed_scale"))
			mt._dismount_buggy()
			await get_tree().physics_frame
			print("[AutoCapture] buggy dismounted_ok=", not mt._buggy_mounted, " speed=", player.get("speed_scale"))


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
	# でんしゃの詳細(発見済み はやぶさ)をタップした状態
	var entries: Array = book.call("_load_master", "train")
	for e in entries:
		if e.get("found", false):
			book.call("_show_detail", e)
			break
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_book_detail.png")
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


# 銀河鉄道 検証: warp_in で星空ワールドへ → 巡航中の汽車まわりを撮影。
func _capture_ginga() -> void:
	var ginga := get_tree().root.find_child("GingaRailway", true, false)
	if ginga == null:
		print("[AutoCapture] GingaRailway not found")
		await _save_screenshot(SCREENSHOT_PATH)
		return
	if ginga.has_method("warp_in"):
		ginga.warp_in()
	await get_tree().create_timer(1.2).timeout  # フェード+到着+巡航開始を待つ
	print("[AutoCapture] ginga active: %s" % str(ginga.call("is_active")))
	# プレイヤー(=汽車)を後ろ上から撮る
	var player := get_tree().root.find_child("Player", true, false) as Node3D
	var cam := get_viewport().get_camera_3d() as Camera3D
	var rigp := cam.get_parent()
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	cam.fov = 65.0
	if player:
		var p: Vector3 = player.global_position
		cam.global_position = p + Vector3(9, 6, 12)
		cam.look_at(p + Vector3(0, 1.0, 0))
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_ginga.png")
	# 少し進ませて 全景も
	await get_tree().create_timer(1.0).timeout
	if player:
		var p2: Vector3 = player.global_position
		cam.global_position = p2 + Vector3(0, 40, 55)
		cam.look_at(p2)
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_ginga_wide.png")


# B-7 検証: 夜にして ゆめ電車が出現するか。出たらその近くを撮影。
func _capture_rare() -> void:
	var dn := get_tree().root.find_child("DayNightCycle", true, false)
	var rare := get_tree().root.find_child("RareTrain", true, false)
	if dn == null or rare == null:
		print("[AutoCapture] DayNightCycle/RareTrain not found")
		await _save_screenshot(SCREENSHOT_PATH)
		return
	dn.set("time_of_day", 0.92)  # 夜にする
	await get_tree().create_timer(1.3).timeout  # spawner の _process(0.5s間隔)が出現させるのを待つ
	var t = rare.get("_train")
	print("[AutoCapture] rare spawned: %s" % str(t != null))
	var cam := get_viewport().get_camera_3d() as Camera3D
	var rigp := cam.get_parent()
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	cam.fov = 60.0
	if t != null and t.has_method("get_ride_anchor_position"):
		var p: Vector3 = t.get_ride_anchor_position()
		cam.global_position = p + Vector3(10, 7, 14)
		cam.look_at(p + Vector3(0, 1.5, 0))
	else:
		cam.global_position = Vector3(0, 120, 200)
		cam.look_at(Vector3(0, 2, 0))
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_rare_train.png")


# B-5 検証: 楽器(もっきん/ラッパ)を デバッグカメラで写す。_ready で組み立て済なので
# 表示と 配置を確認する(タップ反応は B-2 と同じ仕組み)。
func _capture_music() -> void:
	var inst := get_tree().root.find_child("Instruments", true, false)
	if inst == null:
		print("[AutoCapture] Instruments not found")
		await _save_screenshot(SCREENSHOT_PATH)
		return
	var roots: Array = []
	for c in inst.get_children():
		if c is Node3D:
			roots.append(c)  # [0]=もっきん [1]=ラッパ(AudioStreamPlayer は Node3D でない)
	var cam := get_viewport().get_camera_3d() as Camera3D
	var rigp := cam.get_parent()
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	cam.fov = 55.0
	if roots.size() >= 1:
		var t: Vector3 = (roots[0] as Node3D).global_position
		cam.global_position = t + Vector3(0.0, 2.6, 4.8)
		cam.look_at(t + Vector3(0, 0.5, 0))
		await get_tree().process_frame
		await get_tree().process_frame
		await _save_screenshot("user://screenshot_music_xylophone.png")
	if roots.size() >= 2:
		var t2: Vector3 = (roots[1] as Node3D).global_position
		cam.global_position = t2 + Vector3(0.0, 2.2, 4.0)
		cam.look_at(t2 + Vector3(0, 0.6, 0))
		await get_tree().process_frame
		await get_tree().process_frame
		await _save_screenshot("user://screenshot_music_trumpet.png")


# A-5 検証: 乗客の手振り。乗車→窓辺視点で他編成に手を振らせて撮影、降車後にも撮影。
func _capture_greet() -> void:
	var rc := get_tree().root.find_child("RideController", true, false)
	var trains := get_tree().root.find_child("Trains", true, false)
	if rc == null or trains == null or trains.get_child_count() == 0:
		print("[AutoCapture] RideController/Trains not found, falling back to single")
		await _save_screenshot(SCREENSHOT_PATH)
		return
	var train := trains.get_child(0)  # Hayabusa
	rc._do_board(train)
	# 窓辺(まどぎわ)視点へ:[やね, うんてんせき, まどぎわ] を 2 回送る
	if rc.has_method("cycle_ride_view"):
		rc.cycle_ride_view()
		rc.cycle_ride_view()
	# 全編成に手を振らせる(自分が振られる側の見え方を確認)
	for t in trains.get_children():
		if t.has_method("wave_passengers"):
			t.wave_passengers()
	await get_tree().create_timer(0.45).timeout  # 腕が上がるのを待つ
	await _save_screenshot("user://screenshot_greet_ride.png")
	rc._do_alight()
	# 降車後、近くの編成に再度手を振らせて地上からの見え方を撮影
	await get_tree().process_frame
	for t in trains.get_children():
		if t.has_method("wave_passengers"):
			t.wave_passengers()
	await get_tree().create_timer(0.45).timeout
	await _save_screenshot("user://screenshot_greet_ground.png")


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


# 空の城 検証: 地上の飛行機 → 自動飛行 → 空の城(城・雲足場・旋回電車・ほし・落ちない)→ 帰り。
func _capture_sky() -> void:
	var player := get_tree().root.find_child("Player", true, false) as CharacterBody3D
	var sky := get_tree().root.find_child("SkyCastle", true, false)
	var cam := get_viewport().get_camera_3d() as Camera3D
	var rigp := cam.get_parent()
	if sky == null or player == null:
		await _save_screenshot(SCREENSHOT_PATH)
		return
	# --- ① 地上の飛行機 ---
	player.global_position = sky._park_pos + Vector3(0, 0, 8)
	await get_tree().physics_frame
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	cam.global_position = sky._park_pos + Vector3(7, 4, 11)
	cam.look_at(sky._park_pos + Vector3(0, 0.8, 0))
	cam.fov = 55.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_airplane.png")
	# --- ② 空の城へ自動飛行(カメラ追従を一旦戻して 離陸の絵を見る) ---
	if rigp and rigp.get_script() != null:
		rigp.set_process(true)
	sky._go_sky()
	await get_tree().create_timer(float(sky.FLIGHT_TIME) + 1.4).timeout
	print("[AutoCapture] on_sky=", sky._on_sky, " player_y=%.1f sky_y=%.1f" % [player.global_position.y, sky.SKY_POS.y])
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	var sp: Vector3 = sky.SKY_POS
	# 全景(大きくなった城・雲・飛行機・旋回電車)
	cam.global_position = sp + Vector3(22, 14, 30)
	cam.look_at(sp + Vector3(0, 9, 0))
	cam.fov = 60.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_sky_castle.png")
	# プレイヤー到着位置から見た 城(降りて何が見えるか)
	cam.global_position = sp + Vector3(0, 4.5, 17)
	cam.look_at(sp + Vector3(0, 6, 0))
	cam.fov = 62.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_sky_arrival.png")
	# 飛行機の駐機 + プレイヤー(降りた所)
	cam.global_position = sky._park_pos + Vector3(8, 4, 11)
	cam.look_at(sky._park_pos + Vector3(0, 1, 0))
	cam.fov = 54.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_sky_airplane.png")
	# 雲の島を 上から(足場・落ちない範囲)
	cam.global_position = sp + Vector3(0, 42, 0.1)
	cam.look_at(sp)
	cam.fov = 70.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_sky_island.png")
	# --- ③ 帰り ---
	sky._go_home()
	await get_tree().create_timer(float(sky.FLIGHT_TIME) + 1.4).timeout
	print("[AutoCapture] back on_sky=", sky._on_sky, " player_y=%.1f" % player.global_position.y)


# 潜水艦 検証: 湖の潜水艦 → 潜航 → 海中(サンゴ・魚)→ 自動巡航が進む → 浮上。
func _capture_sea() -> void:
	var player := get_tree().root.find_child("Player", true, false) as CharacterBody3D
	var sub := get_tree().root.find_child("Submarine", true, false)
	var cam := get_viewport().get_camera_3d() as Camera3D
	var rigp := cam.get_parent()
	if sub == null or player == null:
		await _save_screenshot(SCREENSHOT_PATH)
		return
	# --- ① 湖の潜水艦 + 水面 ---
	player.global_position = sub._sub_pos + Vector3(0, 0, 9)
	await get_tree().physics_frame
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	cam.global_position = sub._sub_pos + Vector3(9, 5, 11)
	cam.look_at(sub._sub_pos + Vector3(0, 0.4, 0))
	cam.fov = 55.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_sub_dock.png")
	# --- ② 潜航 ---
	sub._dive()
	await get_tree().create_timer(1.4).timeout
	var sea: Vector3 = sub.SEA_POS
	print("[AutoCapture] on_sea=", sub._on_sea, " player_y=%.1f sea_y=%.1f" % [player.global_position.y, sea.y])
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	# 海中の全景(サンゴ・魚・明るい青)
	cam.global_position = sea + Vector3(30, 20, 38)
	cam.look_at(sea + Vector3(0, 8, 0))
	cam.fov = 64.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_sea.png")
	# --- ③ 自動巡航が進むか(数秒で位置が動く) ---
	var p0: Vector3 = player.global_position
	await get_tree().create_timer(3.0).timeout
	var moved: float = p0.distance_to(player.global_position)
	print("[AutoCapture] cruise moved=%.1f (0 でなければ自動巡航OK)" % moved)
	# プレイヤー追従カメラで 巡航中(魚の中)を撮る
	if rigp and rigp.get_script() != null:
		rigp.set_process(true)
	await get_tree().create_timer(0.6).timeout
	await _save_screenshot("user://screenshot_sea_cruise.png")
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	# サンゴの庭 接写
	cam.global_position = sea + Vector3(9, 6, 11)
	cam.look_at(sea + Vector3(0, 2.5, 0))
	cam.fov = 60.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_sea_coral.png")
	# --- ④ 浮上 ---
	sub._surface()
	await get_tree().create_timer(1.4).timeout
	print("[AutoCapture] back on_sea=", sub._on_sea, " player_y=%.1f" % player.global_position.y)


func _capture_candy() -> void:
	var player := get_tree().root.find_child("Player", true, false) as CharacterBody3D
	var candy := get_tree().root.find_child("CandyLand", true, false)
	var cam := get_viewport().get_camera_3d() as Camera3D
	var rigp := cam.get_parent()
	if candy == null or player == null:
		await _save_screenshot(SCREENSHOT_PATH)
		return
	# 即時に おかしの くにへ(フェードを介さず)
	candy.call("_build_candy_world")
	candy.set("_world_built", true)
	candy.call("_arrive_candy_mid")
	await get_tree().physics_frame
	var c: Vector3 = candy.CANDY_POS
	print("[AutoCapture] on_candy=", candy._on_candy, " player_y=%.1f floor_y=%.1f" % [player.global_position.y, c.y])
	# 全景(引いて見下ろし)
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	cam.global_position = c + Vector3(0, 26, 52)
	cam.look_at(c + Vector3(0, 3, 0))
	cam.fov = 64.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_candy.png")
	# 床の上・近景(ロリポップ/クッキーの家/お菓子)
	cam.global_position = c + Vector3(10, 6, 20)
	cam.look_at(c + Vector3(0, 2, 0))
	cam.fov = 60.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_candy_ground.png")
	# プレイヤー追従カメラ(実プレイの見え方)
	if rigp and rigp.get_script() != null:
		rigp.set_process(true)
	await get_tree().create_timer(0.6).timeout
	await _save_screenshot("user://screenshot_candy_player.png")


func _capture_dino() -> void:
	var player := get_tree().root.find_child("Player", true, false) as CharacterBody3D
	var dino := get_tree().root.find_child("DinoLand", true, false)
	var cam := get_viewport().get_camera_3d() as Camera3D
	var rigp := cam.get_parent()
	if dino == null or player == null:
		await _save_screenshot(SCREENSHOT_PATH)
		return
	# きょうりゅうランドへ(フェード経由・自動巡航突入)
	dino._depart()
	await get_tree().create_timer(1.4).timeout
	var c: Vector3 = dino.DINO_POS
	print("[AutoCapture] on_dino=", dino._on_dino, " player_y=%.1f ground_y=%.1f" % [player.global_position.y, c.y])
	# 全景(引いて見下ろし・きょうりゅうたち)
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	cam.global_position = c + Vector3(34, 24, 40)
	cam.look_at(c + Vector3(0, 4, 0))
	cam.fov = 64.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_dino.png")
	# 自動巡航が進むか(数秒で位置が動く)
	var p0: Vector3 = player.global_position
	await get_tree().create_timer(3.0).timeout
	var moved: float = p0.distance_to(player.global_position)
	print("[AutoCapture] cruise moved=%.1f (0 でなければ自動巡航OK)" % moved)
	# プレイヤー追従カメラ(サファリの見え方)
	if rigp and rigp.get_script() != null:
		rigp.set_process(true)
	await get_tree().create_timer(0.6).timeout
	await _save_screenshot("user://screenshot_dino_ride.png")
	# きょうりゅう 接写
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	cam.global_position = c + Vector3(-14, 8, 22)
	cam.look_at(c + Vector3(-6, 3, 4))
	cam.fov = 58.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_dino_close.png")
	# 帰る
	dino._return_home()
	await get_tree().create_timer(1.4).timeout
	print("[AutoCapture] back on_dino=", dino._on_dino, " player_y=%.1f" % player.global_position.y)


func _capture_yuki() -> void:
	var player := get_tree().root.find_child("Player", true, false) as CharacterBody3D
	var yuki := get_tree().root.find_child("YukiLand", true, false)
	var cam := get_viewport().get_camera_3d() as Camera3D
	var rigp := cam.get_parent()
	if yuki == null or player == null:
		await _save_screenshot(SCREENSHOT_PATH)
		return
	yuki._depart()
	await get_tree().create_timer(1.4).timeout
	var c: Vector3 = yuki.YUKI_POS
	print("[AutoCapture] on_yuki=", yuki._on_yuki, " player_y=%.1f ground_y=%.1f" % [player.global_position.y, c.y])
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	cam.global_position = c + Vector3(34, 24, 40)
	cam.look_at(c + Vector3(0, 6, 0))
	cam.fov = 64.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_yuki.png")
	var p0: Vector3 = player.global_position
	await get_tree().create_timer(3.0).timeout
	var moved: float = p0.distance_to(player.global_position)
	print("[AutoCapture] cruise moved=%.1f (0 でなければ自動巡航OK)" % moved)
	if rigp and rigp.get_script() != null:
		rigp.set_process(true)
	await get_tree().create_timer(0.6).timeout
	await _save_screenshot("user://screenshot_yuki_ride.png")
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	cam.global_position = c + Vector3(-10, 6, 18)
	cam.look_at(c + Vector3(-6, 2, 0))
	cam.fov = 56.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_yuki_close.png")
	yuki._return_home()
	await get_tree().create_timer(1.4).timeout
	print("[AutoCapture] back on_yuki=", yuki._on_yuki, " player_y=%.1f" % player.global_position.y)


func _capture_worldsel() -> void:
	var ws := get_tree().root.find_child("WorldSelect", true, false)
	var moon := get_tree().root.find_child("MoonTrip", true, false)
	var wbtn := get_tree().root.find_child("WorldButton", true, false) as Control
	if ws == null:
		await _save_screenshot(SCREENSHOT_PATH)
		return
	# ① 地上で「どこへ いく?」ボタンが出るか(world_select の _process が制御)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[AutoCapture] WorldButton visible(地上)=", (wbtn.visible if wbtn else "null"))
	# ② メニューを開いて 6カードを撮る
	ws.open()
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_worldsel.png")
	# ③ つき を選んだ相当: close → warp_in。どこからでも飛べるか
	ws.close()
	await get_tree().process_frame
	if moon and moon.has_method("warp_in"):
		moon.warp_in()
	await get_tree().create_timer(1.2).timeout
	var active = moon.is_active() if (moon and moon.has_method("is_active")) else "?"
	print("[AutoCapture] warp_in → moon on_moon=", active, " (true なら どこからでもワープOK)")
	# ④ ボタンは 世界の中では 隠れるか
	await get_tree().process_frame
	print("[AutoCapture] WorldButton visible(世界の中)=", (wbtn.visible if wbtn else "null"))


func _capture_reward() -> void:
	var gs := get_tree().root.find_child("GameState", true, false)
	var player := get_tree().root.find_child("Player", true, false) as Node3D
	var animals := get_tree().root.find_child("Animals", true, false)
	var usagi := get_tree().root.find_child("Usagi", true, false) as Node3D
	var cam := get_viewport().get_camera_3d() as Camera3D
	var rigp := cam.get_parent()
	if gs == null or player == null:
		await _save_screenshot(SCREENSHOT_PATH)
		return
	# ① げんき → スピードアップ(上限つき)
	gs.add_energy(10)
	await get_tree().process_frame
	print("[AutoCapture] energy=%d → energy_speed_scale=%.2f (≈1.30)" % [gs.energy, player.get("energy_speed_scale")])
	gs.add_energy(100)
	await get_tree().process_frame
	print("[AutoCapture] energy=%d → energy_speed_scale=%.2f (上限1.50)" % [gs.energy, player.get("energy_speed_scale")])
	# ② ほし → ほしのき + お祝い(7こで 5の倍数を越える)
	for i in range(7):
		gs.add_star()
	await get_tree().process_frame
	await get_tree().process_frame
	print("[AutoCapture] star_count=", gs.star_count, " (5こ越えで お祝い済みのはず)")
	# ほしのき(STAR_TREE_POS=(6,-14))を斜め前から撮る
	if rigp and rigp.get_script() != null:
		rigp.set_process(false)
	cam.global_position = Vector3(9.5, 6.0, -8.5)
	cam.look_at(Vector3(6.0, 4.4, -14.0))
	cam.fov = 48.0
	await get_tree().process_frame
	await get_tree().process_frame
	await _save_screenshot("user://screenshot_rewardtree.png")
	# ③ なかよしギフト: うさぎを なかよしにして プレイヤー近くへ → _try_gift
	if animals and usagi and usagi.has_method("befriend"):
		usagi.befriend()
		usagi.global_position = player.global_position + Vector3(2, 0, 0)
		await get_tree().physics_frame
		var before: int = gs.star_count
		animals._try_gift(player.global_position)
		await get_tree().process_frame
		print("[AutoCapture] gift: star %d → %d (+1 なら なかよしギフトOK)" % [before, gs.star_count])
