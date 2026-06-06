extends "res://scripts/entities/characters/character_visual.gd"

# 主人公その1「しんかんせんの うんてんしさん」。3 頭身のかわいい運転士。
# もともと player.gd にあった見た目生成・歩行アニメ・てをふる を切り出したもの
# (主人公を選べるようにするため)。見た目・寸法はそのまま。

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

var _arm_l: Node3D
var _arm_r: Node3D
var _leg_l: Node3D
var _leg_r: Node3D


# === 歩行アニメ ===

func animate_walk(delta: float, moving: bool) -> void:
	if _arm_l == null:
		return
	if moving:
		_walk_phase += delta * WALK_FREQ
		var s: float = sin(_walk_phase) * WALK_SWING
		_arm_l.rotation.x = s
		if not _waving:
			_arm_r.rotation.x = -s
		_leg_l.rotation.x = -s
		_leg_r.rotation.x = s
		position.y = abs(sin(_walk_phase * 2.0)) * 0.06
	else:
		var t: float = clamp(10.0 * delta, 0.0, 1.0)
		_arm_l.rotation.x = lerp_angle(_arm_l.rotation.x, 0.0, t)
		if not _waving:
			_arm_r.rotation.x = lerp_angle(_arm_r.rotation.x, 0.0, t)
		_leg_l.rotation.x = lerp_angle(_leg_l.rotation.x, 0.0, t)
		_leg_r.rotation.x = lerp_angle(_leg_r.rotation.x, 0.0, t)
		position.y = lerp(position.y, 0.0, t)


# 「てをふる」: 右腕を上げて ふりふり する。
# 振っている間は _waving で歩行アニメの右腕を止め、tween と競合させない。
func wave() -> void:
	if _waving or _arm_r == null:
		return
	_waving = true
	var tw := create_tween()
	tw.tween_property(_arm_r, "rotation:z", -2.3, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for i in range(2):
		tw.tween_property(_arm_r, "rotation:x", 0.5, 0.15).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_arm_r, "rotation:x", -0.3, 0.15).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_arm_r, "rotation:x", 0.0, 0.12)
	tw.tween_property(_arm_r, "rotation:z", 0.0, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _waving = false)


# === 見た目構築 ===

func build() -> void:
	# 足(青ズボン+靴)
	_leg_l = _make_limb(Vector3(-0.15, 0.45, 0.0), 0.42, 0.11, PANTS, true)
	_leg_r = _make_limb(Vector3(0.15, 0.45, 0.0), 0.42, 0.11, PANTS, true)

	# 体(黄色いシャツ)
	var body := CapsuleMesh.new()
	body.radius = 0.26
	body.height = 0.72
	_add_part(body, Vector3(0, 0.76, 0), SHIRT, self)
	# えり / ボタン
	var collar := CylinderMesh.new()
	collar.top_radius = 0.2
	collar.bottom_radius = 0.27
	collar.height = 0.12
	_add_part(collar, Vector3(0, 1.06, 0), HAT, self)

	# 腕(肌色、肩を支点に振る)
	_arm_l = _make_limb(Vector3(-0.32, 1.02, 0.0), 0.4, 0.09, SKIN, false)
	_arm_r = _make_limb(Vector3(0.32, 1.02, 0.0), 0.4, 0.09, SKIN, false)

	_build_head()


# 手足: 支点 Node3D を pos に置き、その子にメッシュを下方向へ伸ばす(支点で回転=振り)
func _make_limb(pos: Vector3, length: float, radius: float, color: Color, is_leg: bool) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pos
	add_child(pivot)
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
	add_child(head)

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
