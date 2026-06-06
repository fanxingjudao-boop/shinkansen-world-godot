extends CharacterBody3D

# プレイヤー操作スクリプト。
# 移動・物理・カメラ基準移動・月の惑星歩きを担当する。
# 見た目とアニメ(歩行・てをふる・よろこび)は「選べる主人公」に委譲する:
# GameState.selected_character の id を character_roster.gd で引いて、その見た目
# スクリプト(character_visual.gd の子孫)を子ノードとして生成する。
# これで うんてんしさん / きつね など 主人公を切り替えられる。
# ロジック層(pure 関数)と Godot 操作層を分離(docs/ARCHITECTURE.md、C# 移植配慮)。

const CharacterRoster = preload("res://scripts/entities/characters/character_roster.gd")
const GameState = preload("res://scripts/world/game_state.gd")

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 6.5
const ROTATION_SPEED: float = 12.0

signal jumped

# いま表示している主人公の見た目(character_visual.gd の子孫)。
var _char: Node3D
# いま表示している主人公の id(再生成の要否判定に使う)。
var _char_id: String = ""

# 重力の倍率。月旅行(moon_trip.gd)で小さくするとふわっと跳べる。
var gravity_scale: float = 1.0
# 移動速度の倍率。月面カー(moon_trip.gd)に のると 1 より大きくして はやく走れる。
var speed_scale: float = 1.0
# げんき(おだんご等)で 永続的に少しずつ速くなる倍率。reward_manager.gd が設定。
# 上限つきなので 怖いほど速くならない(地上も月の惑星歩きも効く)。
var energy_speed_scale: float = 1.0

# 月の「小さな惑星」モード。重力を planet_center へ向け、up を球面法線に合わせる。
# これで球の裏側まで ぐるっと歩ける(地上/空は通常の Y 重力のまま=この値が false)。
var planet_mode: bool = false
var planet_center: Vector3 = Vector3.ZERO


func _ready() -> void:
	if not is_in_group("player"):
		add_to_group("player")
	# セーブ済み(または既定)の主人公で見た目を生成。
	set_character(_load_selected_id())


# GameState から選択中の主人公 id を読む(無ければ既定)。
func _load_selected_id() -> String:
	var gs := _game_state()
	if gs and CharacterRoster.is_valid(gs.selected_character):
		return gs.selected_character
	return CharacterRoster.DEFAULT_ID


# Main 直下の GameState を取る(Player の親が Main)。
func _game_state() -> GameState:
	var p := get_parent()
	if p == null:
		return null
	return p.get_node_or_null("GameState") as GameState


# 主人公を切り替える(タイトルの選ぶ画面から呼ばれる)。
# 同じ id なら何もしない。違えば 古い見た目を消して 新しく生成し、GameState に記録。
func set_character(id: String) -> void:
	if not CharacterRoster.is_valid(id):
		id = CharacterRoster.DEFAULT_ID
	if id == _char_id and _char != null:
		return
	if _char != null:
		_char.queue_free()
		_char = null
	var entry: Dictionary = CharacterRoster.get_entry(id)
	var scr: Script = load(entry["script"])
	if scr == null:
		return
	_char = scr.new()
	add_child(_char)
	_char.build()
	_char_id = id
	# GameState に保存(セーブされて 次回も同じ主人公で始まる)。
	var gs := _game_state()
	if gs:
		gs.set_character(id)


func _physics_process(delta: float) -> void:
	if planet_mode:
		_planet_process(delta)
		return
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)

	# カメラ基準の移動: 「うえ」ボタンはどの向きでも画面の奥(カメラの前)へ進む。
	# カメラをボタンで回しても、上=奥・下=手前・左右=画面の左右、で直感的に動く。
	var move: Vector3 = _camera_relative_move(input_dir)
	velocity.x = move.x
	velocity.z = move.z

	# === Godot 操作層 ===
	if not is_on_floor():
		velocity += get_gravity() * gravity_scale * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		jumped.emit()

	move_and_slide()

	# キャラは進む向きを向く(カメラ基準の移動方向)
	if input_dir.length() > 0.01 and move.length() > 0.01:
		var target_yaw: float = atan2(-move.x, -move.z)
		rotation.y = lerp_angle(rotation.y, target_yaw, ROTATION_SPEED * delta)

	if _char:
		_char.animate_walk(delta, input_dir.length() > 0.01)


# 入力(D-pad/キー)を、いま映しているカメラの向きに合わせたワールド移動ベクトルへ変換。
# move_forward(うえ)= カメラの前(画面奥)/ move_right(みぎ)= カメラの右。
func _camera_relative_move(input_dir: Vector2) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		# カメラが無いときはワールド基準にフォールバック
		var d := Vector3(input_dir.x, 0.0, input_dir.y)
		if d.length() > 1.0:
			d = d.normalized()
		return d * SPEED * speed_scale * energy_speed_scale
	var b := cam.global_transform.basis
	var fwd := Vector3(-b.z.x, 0.0, -b.z.z)   # カメラの前を水平化(画面の奥)
	var right := Vector3(b.x.x, 0.0, b.x.z)   # カメラの右を水平化
	fwd = fwd.normalized() if fwd.length() > 0.001 else Vector3(0, 0, -1)
	right = right.normalized() if right.length() > 0.001 else Vector3(1, 0, 0)
	# input_dir.y は move_forward で負になるので、前方向は -input_dir.y を掛ける
	var dir := right * input_dir.x - fwd * input_dir.y
	if dir.length() > 1.0:
		dir = dir.normalized()
	return dir * SPEED * speed_scale * energy_speed_scale


# === 月の小さな惑星モード(球面を裏側まで歩く) ===

func _planet_process(delta: float) -> void:
	var input_dir: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_forward", "move_back"
	)
	# up = 球の中心から外向き(= 足元から頭の向き)。接地判定にも使う。
	var up: Vector3 = (global_position - planet_center).normalized()
	if up.length() < 0.5:
		up = Vector3.UP
	up_direction = up
	var move: Vector3 = _planet_move(input_dir, up)
	# 速度を「接線(移動)」と「法線(重力/ジャンプ)」に分けて合成
	var v_up: float = velocity.dot(up)
	if not is_on_floor():
		v_up -= get_gravity().length() * gravity_scale * delta
	if Input.is_action_just_pressed("jump") and is_on_floor():
		v_up = JUMP_VELOCITY
		jumped.emit()
	velocity = move + up * v_up
	move_and_slide()
	_orient_to_surface(up, move, delta)
	if _char:
		_char.animate_walk(delta, input_dir.length() > 0.01)


# 惑星上の移動: カメラ基準の入力を 足元の接平面へ射影(うえ=画面奥のまま)。
func _planet_move(input_dir: Vector2, up: Vector3) -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector3.ZERO
	var b := cam.global_transform.basis
	var fwd := -b.z - up * (-b.z).dot(up)   # カメラ前を接平面へ
	var right := b.x - up * b.x.dot(up)      # カメラ右を接平面へ
	if fwd.length() < 0.001:
		fwd = up.cross(Vector3.RIGHT)
	if right.length() < 0.001:
		right = up.cross(Vector3.FORWARD)
	fwd = fwd.normalized()
	right = right.normalized()
	var dir := right * input_dir.x - fwd * input_dir.y
	if dir.length() > 1.0:
		dir = dir.normalized()
	return dir * SPEED * speed_scale * energy_speed_scale


# 体を 球面に合わせて立たせ(足=法線方向)、進む向きへ向ける。
func _orient_to_surface(up: Vector3, move: Vector3, delta: float) -> void:
	var fwd: Vector3
	if move.length() > 0.05:
		fwd = move.normalized()
	else:
		fwd = -global_transform.basis.z
		fwd = fwd - up * fwd.dot(up)
		if fwd.length() < 0.001:
			fwd = global_transform.basis.x - up * global_transform.basis.x.dot(up)
		fwd = fwd.normalized()
	var bz := -fwd
	var bx := up.cross(bz).normalized()
	var by := bz.cross(bx).normalized()
	var target := Basis(bx, by, bz)
	var t: float = clamp(ROTATION_SPEED * delta, 0.0, 1.0)
	global_transform.basis = global_transform.basis.slerp(target, t).orthonormalized()


# === 見た目・アニメは選択中の主人公(character_visual.gd の子孫)へ委譲 ===

# 「てをふる」: いまの主人公が応える(AnimalManager.request_wave から呼ばれる)。
func wave() -> void:
	if _char:
		_char.wave()


# おだんごを食べたとき等の「やったね!」のぴょこっと喜び。
func celebrate() -> void:
	if _char:
		_char.celebrate()
