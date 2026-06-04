extends CharacterBody3D

# プレイヤー操作スクリプト。
# 見た目は 3 頭身のかわいい「しんかんせんの うんてんしさん」をスクリプトで生成。
# 移動中は腕・足を振り、体が上下する歩行アニメ。
# ロジック層(pure 関数)と Godot 操作層を分離(docs/ARCHITECTURE.md、C# 移植配慮)。

const RIM_SHADER = preload("res://assets/shaders/rim.gdshader")

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 6.5
const ROTATION_SPEED: float = 12.0
const WALK_FREQ: float = 11.0
const WALK_SWING: float = 0.6

# 配色(子供と大人が一緒に見てかわいい)
const SKIN: Color = Color(1.0, 0.85, 0.72)
const HAIR: Color = Color(0.45, 0.3, 0.18)
const HAT: Color = Color(0.16, 0.41, 0.79)
const HAT_DARK: Color = Color(0.1, 0.28, 0.6)
const SHIRT: Color = Color(1.0, 0.85, 0.4)
const PANTS: Color = Color(0.42, 0.55, 0.85)
const SHOE: Color = Color(0.45, 0.3, 0.2)
const CHEEK: Color = Color(1.0, 0.6, 0.7)
const NOSE: Color = Color(1.0, 0.78, 0.68)
const EMBLEM: Color = Color(1.0, 0.85, 0.3)
const EYE_W: Color = Color(1.0, 1.0, 1.0)
const EYE_B: Color = Color(0.12, 0.1, 0.12)

signal jumped

var _visual: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _walk_phase: float = 0.0
# 手を振っている間は true。歩行アニメが右腕を触らないようにして競合を避ける。
var _waving: bool = false

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
	_build_character()


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

	_animate_walk(delta, input_dir.length() > 0.01)


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
	_animate_walk(delta, input_dir.length() > 0.01)


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


# === 歩行アニメ ===

func _animate_walk(delta: float, moving: bool) -> void:
	if _visual == null:
		return
	if moving:
		_walk_phase += delta * WALK_FREQ
		var s: float = sin(_walk_phase) * WALK_SWING
		_arm_l.rotation.x = s
		if not _waving:
			_arm_r.rotation.x = -s
		_leg_l.rotation.x = -s
		_leg_r.rotation.x = s
		_visual.position.y = abs(sin(_walk_phase * 2.0)) * 0.06
	else:
		var t: float = clamp(10.0 * delta, 0.0, 1.0)
		_arm_l.rotation.x = lerp_angle(_arm_l.rotation.x, 0.0, t)
		if not _waving:
			_arm_r.rotation.x = lerp_angle(_arm_r.rotation.x, 0.0, t)
		_leg_l.rotation.x = lerp_angle(_leg_l.rotation.x, 0.0, t)
		_leg_r.rotation.x = lerp_angle(_leg_r.rotation.x, 0.0, t)
		_visual.position.y = lerp(_visual.position.y, 0.0, t)


# 「てをふる」: 右腕を上げて ふりふり する(AnimalManager.request_wave から呼ばれる)。
# 振っている間は _waving で歩行アニメの右腕を止め、tween と競合させない。
# 支点(肩)で z 回転=腕を横に上げる / x 回転=前後に振る。腕は下向き(-Y)に伸びている。
func wave() -> void:
	if _waving or _arm_r == null:
		return
	_waving = true
	var tw := create_tween()
	# 腕を ぴょこっと 上げる
	tw.tween_property(_arm_r, "rotation:z", -2.3, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# ふりふり(2 往復)
	for i in range(2):
		tw.tween_property(_arm_r, "rotation:x", 0.5, 0.15).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_arm_r, "rotation:x", -0.3, 0.15).set_trans(Tween.TRANS_SINE)
	# 腕を 下ろす
	tw.tween_property(_arm_r, "rotation:x", 0.0, 0.12)
	tw.tween_property(_arm_r, "rotation:z", 0.0, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _waving = false)


# おだんごを食べたとき等の「やったね!」のぴょこっと喜び(scale バウンス)。
# 歩行アニメは position.y/rotation を触るが scale は触らないので競合しない。
func celebrate() -> void:
	if _visual == null:
		return
	var tw := create_tween()
	tw.tween_property(_visual, "scale", Vector3.ONE * 1.25, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_visual, "scale", Vector3.ONE, 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# === 見た目構築(Godot 操作層) ===

func _build_character() -> void:
	_visual = Node3D.new()
	add_child(_visual)

	# 足(青ズボン+靴)
	_leg_l = _make_limb(Vector3(-0.15, 0.45, 0.0), 0.42, 0.11, PANTS, true)
	_leg_r = _make_limb(Vector3(0.15, 0.45, 0.0), 0.42, 0.11, PANTS, true)

	# 体(黄色いシャツ)
	var body := CapsuleMesh.new()
	body.radius = 0.26
	body.height = 0.72
	_add_part(body, Vector3(0, 0.76, 0), SHIRT, _visual)
	# えり / ボタン
	var collar := CylinderMesh.new()
	collar.top_radius = 0.2
	collar.bottom_radius = 0.27
	collar.height = 0.12
	_add_part(collar, Vector3(0, 1.06, 0), HAT, _visual)

	# 腕(肌色、肩を支点に振る)
	_arm_l = _make_limb(Vector3(-0.32, 1.02, 0.0), 0.4, 0.09, SKIN, false)
	_arm_r = _make_limb(Vector3(0.32, 1.02, 0.0), 0.4, 0.09, SKIN, false)

	_build_head()


# 手足: 支点 Node3D を pos に置き、その子にメッシュを下方向へ伸ばす(支点で回転=振り)
func _make_limb(pos: Vector3, length: float, radius: float, color: Color, is_leg: bool) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	_visual.add_child(pivot)
	var cap := CapsuleMesh.new()
	cap.radius = radius
	cap.height = length
	_add_part(cap, Vector3(0, -length * 0.5, 0), color, pivot)
	if is_leg:
		var shoe := BoxMesh.new()
		shoe.size = Vector3(0.2, 0.13, 0.3)
		_add_part(shoe, Vector3(0, -length - 0.02, -0.06), SHOE, pivot)
	else:
		# 手(まるい)
		var hand := SphereMesh.new()
		hand.radius = 0.11
		hand.height = 0.22
		_add_part(hand, Vector3(0, -length - 0.02, 0), SKIN, pivot)
	return pivot


# 顔(半径0.42の球、中心 head 原点)の (x,y) における表面の少し内側の点を返す。
# inset を大きくするほど顔の内側=出っ張らない。目・ほっぺを顔に貼り付けるのに使う。
func _face_pt(x: float, y: float, inset: float) -> Vector3:
	var r2: float = 0.42 * 0.42 - x * x - y * y
	var sz: float = -sqrt(r2) if r2 > 0.0 else 0.0
	return Vector3(x, y, sz + inset)


func _build_head() -> void:
	var head := Node3D.new()
	head.position = Vector3(0, 1.5, 0)  # 頭の中心
	_visual.add_child(head)

	# 顔(大きい丸い頭=3頭身でかわいく)
	var face := SphereMesh.new()
	face.radius = 0.42
	face.height = 0.84
	_add_part(face, Vector3.ZERO, SKIN, head)

	# 後ろ髪(後頭部に少し)
	var hair := SphereMesh.new()
	hair.radius = 0.4
	hair.height = 0.8
	_add_part(hair, Vector3(0, 0.06, 0.14), HAIR, head).scale = Vector3(1.02, 0.9, 0.85)

	# 目(白目+大きいうるうる黒目+キラキラ2つ)。-Z が顔の正面。
	# 顔は球なので、各パーツを「その(x,y)での顔表面」に沿って置き、出っ張らせない
	# (奥行きスケールも薄くして 平らな目のように顔に貼り付く)。
	for sx in [-1.0, 1.0]:
		var ex: float = sx * 0.16
		# 白目(下地・たてに大きめ。いちばん奥)
		var w := SphereMesh.new()
		w.radius = 0.14
		w.height = 0.28
		var wmi := _add_unshaded(w, _face_pt(ex, 0.05, 0.10), EYE_W, head)
		wmi.scale = Vector3(0.85, 1.2, 0.32)
		# 黒目(大きい瞳=うるうる)
		var b := SphereMesh.new()
		b.radius = 0.105
		b.height = 0.21
		var bmi := _add_unshaded(b, _face_pt(ex, 0.04, 0.07), EYE_B, head)
		bmi.scale = Vector3(0.92, 1.05, 0.32)
		# キラキラ(大・上。いちばん手前だが顔表面は越えない)
		var hi1 := SphereMesh.new()
		hi1.radius = 0.045
		hi1.height = 0.09
		_add_unshaded(hi1, _face_pt(ex + sx * 0.04, 0.09, 0.05), EYE_W, head)
		# キラキラ(小・下)
		var hi2 := SphereMesh.new()
		hi2.radius = 0.022
		hi2.height = 0.044
		_add_unshaded(hi2, _face_pt(ex - sx * 0.03, -0.02, 0.05), EYE_W, head)

	# ほっぺ(ピンク。顔表面に沿わせて 出っ張らせない)
	for sx in [-1.0, 1.0]:
		var c := SphereMesh.new()
		c.radius = 0.09
		c.height = 0.18
		var cmi := _add_unshaded(c, _face_pt(sx * 0.26, -0.08, 0.06), CHEEK, head)
		cmi.scale = Vector3(1.1, 0.8, 0.3)

	# 鼻(ちょこん)
	var nose := SphereMesh.new()
	nose.radius = 0.05
	nose.height = 0.1
	_add_part(nose, Vector3(0, -0.04, -0.42), NOSE, head)

	# 帽子(しんかんせんの うんてんしさん)
	var crown := CylinderMesh.new()
	crown.top_radius = 0.4
	crown.bottom_radius = 0.44
	crown.height = 0.34
	_add_part(crown, Vector3(0, 0.46, 0), HAT, head)
	var band := CylinderMesh.new()
	band.top_radius = 0.45
	band.bottom_radius = 0.45
	band.height = 0.08
	_add_part(band, Vector3(0, 0.3, 0), HAT_DARK, head)
	var brim := BoxMesh.new()
	brim.size = Vector3(0.56, 0.07, 0.3)
	_add_part(brim, Vector3(0, 0.3, -0.34), HAT_DARK, head)
	# エンブレム(金の星っぽい点)
	var emb := SphereMesh.new()
	emb.radius = 0.06
	emb.height = 0.12
	var emi := _add_unshaded(emb, Vector3(0, 0.42, -0.4), EMBLEM, head)
	emi.scale = Vector3(1.0, 1.0, 0.5)


# === パーツ生成ヘルパー ===

# リムライト付き(輪郭がふんわり光る)
func _add_part(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var sm := ShaderMaterial.new()
	sm.shader = RIM_SHADER
	sm.set_shader_parameter("albedo", color)
	sm.set_shader_parameter("roughness_val", 0.7)
	sm.set_shader_parameter("rim_color", Color(1, 1, 0.96))
	sm.set_shader_parameter("rim_power", 2.5)
	sm.set_shader_parameter("rim_strength", 0.5)
	mi.material_override = sm
	mi.position = pos
	parent.add_child(mi)
	return mi


# UNSHADED(目・ほっぺ・エンブレムなど、陰の影響を受けず鮮やかに)
func _add_unshaded(mesh: Mesh, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi
