extends "res://scripts/entities/characters/character_visual.gd"

# 主人公その2「キツネ」。
# docs/design_handoff_fox_character/ の Three.js モデル(_buildModel)を Godot の
# プリミティブで忠実に再現したもの。オレンジの体・大きな白いむね・段重ねの長い耳・
# 赤いスカーフ・うるうるアンバーの目・ふさふさの大きな尻尾。歩くと前足が振れ、
# 尻尾と耳がゆれ、ときどき まばたきする。
#
# 元モデルは「顔=+Z 向き・足元 y=0・全高 ~3.4」で組まれている。このゲームの主人公は
# 顔が -Z 向きに統一されているので、内部グループ `_g` を 180° 回して合わせ、
# MODEL_SCALE で うんてんしさんと同じくらいの背丈に縮める。

# 全体の縮尺(元モデル ~3.4 ユニット → ~1.9 ユニットでうんてんしさんと近い背丈)。
# 大きすぎ/小さすぎなら ここを調整(実機体感で)。
const MODEL_SCALE: float = 0.55

# anim 係数(handoff の _animate より)
const EAR_BASE_X: float = -0.06

# パレット(handoff のアートから採取した あたたかいオレンジ)
const ORANGE := Color(0.953, 0.463, 0.165)    # f3762a
const ORANGE_D := Color(0.867, 0.369, 0.094)  # dd5e18
const ORANGE_L := Color(0.984, 0.659, 0.353)  # fba85a
const EAR_EDGE := Color(0.749, 0.290, 0.094)  # bf4a18
const EAR_TIP := Color(0.541, 0.275, 0.133)   # 8a4622
const CREAM := Color(0.988, 0.910, 0.784)     # fce8c8
const WHITE := Color(1.0, 0.965, 0.914)       # fff6e9
const PEACH := Color(0.988, 0.753, 0.494)     # fcc07e
const NOSE := Color(0.165, 0.094, 0.063)      # 2a1810
const RED := Color(0.910, 0.227, 0.149)       # e83a26
const RED_D := Color(0.776, 0.165, 0.122)     # c62a1f
const AMBER := Color(0.965, 0.659, 0.129)     # f6a821
const AMBER_HI := Color(0.988, 0.843, 0.416)  # fcd76a
const EYE_RIM := Color(0.157, 0.075, 0.027)   # 281307
const FEET := Color(0.431, 0.290, 0.180)      # 6e4a2e
const NOSE_HI := Color(0.925, 0.886, 0.863)   # ece2dc
const SMILE := Color(0.290, 0.141, 0.071)     # 4a2412
const BLUSH := Color(1.0, 0.604, 0.525, 0.45) # ff9a86 @0.45
const WHISKER := Color(0.992, 0.953, 0.918, 0.7)

# アニメ用の参照
var _g: Node3D            # 内部グループ(縮尺+180°回転)
var _head: Node3D
var _tail: Node3D
var _ears: Array[Node3D] = []
var _arm_r: Node3D        # 振る前足(=handoff の raisedArm)
var _arm_l: Node3D        # もう一方の前足(=handoff の restArm)
var _eyes: Array[Node3D] = []

var _t: float = 0.0       # 時間アキュムレータ(idle のゆらぎ用)
var _amp: float = 0.0     # 0..1 移動量(歩行ブレンド)
var _next_blink: float = -1.0


# === 歩行・アイドルアニメ(handoff の _animate を移植・地上前提に簡略化) ===

func animate_walk(delta: float, moving: bool) -> void:
	if _head == null:
		return
	_t += delta
	# 移動量を なめらかに 0..1 へ
	var target_amp: float = 1.0 if moving else 0.0
	_amp = lerp(_amp, target_amp, clamp(delta * 8.0, 0.0, 1.0))
	_walk_phase += delta * (6.0 + _amp * 10.0)
	var sw: float = sin(_walk_phase)

	# ぴょこぴょこ ホップ(移動中)+ アイドルの呼吸ゆれ
	var hop: float = abs(sin(_walk_phase)) * _amp * 0.14
	var idle_bob: float = (1.0 - _amp) * sin(_t * 2.5) * 0.04
	position.y = hop + idle_bob

	# 前足が歩きに合わせてゆれる
	if not _waving and _arm_r:
		_arm_r.rotation.x = 0.18 - sw * 0.5 * _amp
	if _arm_l:
		_arm_l.rotation.x = 0.25 + sw * 0.5 * _amp

	# 大きな尻尾の ゆれ(バウンシー)
	if _tail:
		_tail.rotation.z = sin(_t * 2.6 + _walk_phase * 0.4) * 0.16
		_tail.rotation.x = sin(_t * 2.0) * 0.07 + _amp * 0.1
		_tail.rotation.y = sin(_t * 1.8) * 0.08

	# 耳の ぴくぴく
	if _ears.size() == 2:
		_ears[0].rotation.x = EAR_BASE_X + sin(_t * 4.0) * 0.05
		_ears[1].rotation.x = EAR_BASE_X + sin(_t * 4.0 + 1.0) * 0.05

	# 頭の こくり
	_head.rotation.x = -_amp * 0.06 + sin(_t * 2.0) * 0.025
	_head.rotation.z = sin(_t * 1.6) * 0.02

	# ときどき まばたき(目板を たてに つぶす)
	_blink(delta)


func _blink(_delta: float) -> void:
	if _eyes.is_empty():
		return
	if _next_blink < 0.0:
		_next_blink = _t + 2.0 + randf() * 3.0
	var bl: float = 1.0
	if _t > _next_blink:
		var p: float = (_t - _next_blink) / 0.12   # まばたきは ~0.12 秒
		if p >= 1.0:
			_next_blink = _t + 2.5 + randf() * 3.5
		else:
			bl = 1.0 - sin(p * PI)   # 1→0→1
	for e in _eyes:
		e.scale.y = 0.1 + 0.9 * bl


# 「てをふる」: 前足を ぴょこっと上げて ふりふり(うんてんしさんと同じ作法)。
func wave() -> void:
	if _waving or _arm_r == null:
		return
	_waving = true
	var tw := create_tween()
	# 前足を 上げる(前へ振り上げ)
	tw.tween_property(_arm_r, "rotation:x", -1.5, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# ふりふり(2 往復・横ゆれ)
	for i in range(2):
		tw.tween_property(_arm_r, "rotation:z", 0.5, 0.15).set_trans(Tween.TRANS_SINE)
		tw.tween_property(_arm_r, "rotation:z", -0.2, 0.15).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_arm_r, "rotation:z", 0.0, 0.12)
	# もとの位置へ
	tw.tween_property(_arm_r, "rotation:x", 0.18, 0.18) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _waving = false)


# === 見た目構築 ===

func build() -> void:
	# 内部グループ: 縮尺をかけ、顔を -Z 向きへ(元モデルは +Z 向き)。
	_g = Node3D.new()
	_g.scale = Vector3.ONE * MODEL_SCALE
	_g.rotation.y = PI
	add_child(_g)

	_build_feet()
	_build_body()
	_build_neckerchief()
	_build_head_group()
	_build_arms()
	_build_tail()


func _build_feet() -> void:
	# 足元から ちょこんと のぞく うしろ足
	for sx in [-1.0, 1.0]:
		var foot := _sphere(0.17, Vector3(0.22 * sx, 0.12, 0.18), FEET, _g)
		foot.scale = Vector3(1.0, 0.7, 1.35)


func _build_body() -> void:
	# ぷっくりした体: オレンジの背中 + 大きな ふわふわ白いむね
	_sphere(0.78, Vector3(0, 0.84, 0), ORANGE, _g).scale = Vector3(0.96, 1.02, 0.92)
	_sphere(0.7, Vector3(0, 1.04, -0.12), ORANGE_D, _g).scale = Vector3(0.9, 0.78, 0.86)
	_sphere(0.66, Vector3(0, 0.8, 0.34), WHITE, _g).scale = Vector3(0.96, 1.18, 0.72)
	_sphere(0.46, Vector3(0, 0.5, 0.34), WHITE, _g).scale = Vector3(1.02, 1.0, 0.78)


func _build_neckerchief() -> void:
	# 赤いスカーフ(首もと)
	var band := CylinderMesh.new()
	band.top_radius = 0.5
	band.bottom_radius = 0.64
	band.height = 0.28
	var b := _add_part(band, Vector3(0, 1.4, 0), RED, _g)
	b.rotation.x = 0.08
	# むすびめ
	_sphere(0.14, Vector3(0.12, 1.28, 0.5), RED, _g)
	# たれた はしっぽ 2本
	for s in [-1.0, 1.0]:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = 0.13
		cone.height = 0.5
		var end := _add_part(cone, Vector3(0.12 + s * 0.06, 1.05, 0.5), (RED if s < 0 else RED_D), _g)
		end.rotation.x = 0.6
		end.rotation.z = 0.3 * s


func _build_head_group() -> void:
	_head = Node3D.new()
	_head.position = Vector3(0, 1.82, 0)
	_g.add_child(_head)

	# 頭(大きい)
	_sphere(0.72, Vector3.ZERO, ORANGE, _head).scale = Vector3(1.05, 1.0, 0.95)
	# 明るい おでこ + まゆ
	_sphere(0.3, Vector3(0, 0.22, 0.6), ORANGE_L, _head).scale = Vector3(0.42, 0.7, 0.18)
	for sx in [-1.0, 1.0]:
		var brow := _sphere(0.12, Vector3(0.26 * sx, 0.3, 0.56), ORANGE_L, _head)
		brow.scale = Vector3(1.3, 0.55, 0.3)
		brow.rotation.z = -0.3 * sx
	# クリーム色の下顔(オレンジが顔をふちどる)
	_sphere(0.56, Vector3(0, -0.3, 0.3), WHITE, _head).scale = Vector3(0.98, 0.66, 0.74)
	# 白い ほお
	for sx in [-1.0, 1.0]:
		_sphere(0.27, Vector3(0.33 * sx, -0.2, 0.42), WHITE, _head).scale = Vector3(0.85, 0.78, 0.72)
	# 鼻先 + 鼻 + やさしい えがお
	_sphere(0.26, Vector3(0, -0.2, 0.56), WHITE, _head).scale = Vector3(1.0, 0.82, 1.12)
	_sphere(0.12, Vector3(0, -0.12, 0.8), NOSE, _head).scale = Vector3(1.3, 0.92, 1.0)
	# 鼻のツヤ
	_add_unshaded(_ball(0.035), Vector3(-0.04, -0.07, 0.9), NOSE_HI, _head)
	# やさしい えがお(小さな弧を 5つの点で)
	_build_smile()
	# ピンクの ほっぺ(うすく)
	for sx in [-1.0, 1.0]:
		var blush := _add_unshaded_alpha(_ball(0.13), Vector3(0.42 * sx, -0.18, 0.52), BLUSH, _head)
		blush.scale = Vector3(1.0, 1.0, 0.18)
		blush.rotation.y = -0.5 * sx
	# ひげ(うすい すじ・うごかさない)
	_build_whiskers()
	# 目(うるうる アンバー)
	_build_eyes()
	# 大きな耳
	_build_ears()


func _build_smile() -> void:
	# 鼻の下に やさしい 上向きの弧(小さな暗点の連なり)。
	for k in range(5):
		var u: float = float(k) / 4.0          # 0..1
		var x: float = (u - 0.5) * 0.22
		var y: float = -0.3 - (0.5 - abs(u - 0.5)) * 0.06   # 端が上がる=えがお
		_add_unshaded(_ball(0.022), Vector3(x, y, 0.73), SMILE, _head)


func _build_whiskers() -> void:
	# 鼻もとから 横うしろへ はらう うすい ひげ。
	for sx in [-1.0, 1.0]:
		for k in range(3):
			var grp := Node3D.new()
			grp.position = Vector3(0.26 * sx, -0.18 - k * 0.05, 0.6)
			grp.rotation.y = (-0.5 - k * 0.12) * sx
			grp.rotation.z = 0.12 - k * 0.12
			_head.add_child(grp)
			var wm := CylinderMesh.new()
			wm.top_radius = 0.005
			wm.bottom_radius = 0.012
			wm.height = 0.55
			var w := _add_unshaded_alpha(wm, Vector3(0.28 * sx, 0, 0), WHISKER, grp)
			w.rotation.z = PI / 2   # 横にねかせる


func _build_eyes() -> void:
	# きれいな イラスト調の目: 平たい アーモンド + アンバーの虹彩 + 大きな瞳 + キラキラ。
	# blink で たてに つぶせるよう、各目を 1つの Node3D にまとめて _eyes に入れる。
	for sx in [-1.0, 1.0]:
		var eye := Node3D.new()
		eye.position = Vector3(0.255 * sx, 0.03, 0.6)
		eye.rotation = Vector3(0.02, 0.1 * sx, 0)   # 丸い顔に沿う ゆるい外向き
		_head.add_child(eye)
		_eyes.append(eye)
		# 暗い アーモンド外枠(いちばん奥)
		_add_unshaded(_ball(0.16), Vector3(0, 0, 0.02), EYE_RIM, eye).scale = Vector3(1.0, 1.28, 0.22)
		# アンバーの虹彩
		_add_unshaded(_ball(0.135), Vector3(0, 0, 0.04), AMBER, eye).scale = Vector3(1.0, 1.18, 0.22)
		# 下の あかるい アンバー(宝石みたいな かがやき)
		_add_unshaded(_ball(0.075), Vector3(0, -0.06, 0.06), AMBER_HI, eye).scale = Vector3(1.0, 0.8, 0.22)
		# 大きな黒い瞳
		_add_unshaded(_ball(0.09), Vector3(0, -0.005, 0.07), NOSE, eye).scale = Vector3(1.0, 1.15, 0.22)
		# キラキラ(大・左上)
		_add_unshaded(_ball(0.045), Vector3(-0.05, 0.05, 0.09), WHITE, eye)
		# キラキラ(小・右下)
		_add_unshaded(_ball(0.024), Vector3(0.05, -0.05, 0.09), WHITE, eye)


func _build_ears() -> void:
	# とても高い耳: さびオレンジのふち → オレンジ → ピーチ → 白い内側 → 暗い先。
	for sx in [-1.0, 1.0]:
		var ear := Node3D.new()
		ear.position = Vector3(0.36 * sx, 0.52, -0.02)
		_head.add_child(ear)
		_add_part(_cone(0.5, 1.75), Vector3(0, 0.72, 0), EAR_EDGE, ear).scale = Vector3(1, 1, 0.36)
		_add_part(_cone(0.42, 1.62), Vector3(0, 0.68, 0.05), ORANGE, ear).scale = Vector3(1, 1, 0.36)
		_add_part(_cone(0.3, 1.25), Vector3(0, 0.6, 0.1), PEACH, ear).scale = Vector3(1, 1, 0.36)
		_add_part(_cone(0.18, 0.95), Vector3(0, 0.52, 0.14), WHITE, ear).scale = Vector3(1, 1, 0.36)
		_add_part(_cone(0.2, 0.42), Vector3(0, 1.42, 0), EAR_TIP, ear).scale = Vector3(1, 1, 0.4)
		ear.rotation.z = -0.2 * sx
		ear.rotation.x = EAR_BASE_X
		_ears.append(ear)


func _build_arms() -> void:
	# 両方の前足は からだの脇に 自然に下りている。
	# 右(振る方=raisedArm)
	_arm_r = Node3D.new()
	_arm_r.position = Vector3(-0.44, 1.08, 0.36)
	_g.add_child(_arm_r)
	var ru := CapsuleMesh.new()
	ru.radius = 0.15
	ru.height = 0.72
	_add_part(ru, Vector3(0, -0.2, 0), ORANGE, _arm_r)
	_sphere(0.18, Vector3(0, -0.46, 0.06), WHITE, _arm_r).scale = Vector3(1.05, 0.92, 1.1)
	_arm_r.rotation.x = 0.18
	_arm_r.rotation.z = 0.08

	# 左(restArm)
	_arm_l = Node3D.new()
	_arm_l.position = Vector3(0.4, 1.05, 0.34)
	_g.add_child(_arm_l)
	var lu := CapsuleMesh.new()
	lu.radius = 0.15
	lu.height = 0.72
	_add_part(lu, Vector3(0, -0.2, 0), ORANGE, _arm_l)
	_sphere(0.19, Vector3(0, -0.44, 0.08), WHITE, _arm_l).scale = Vector3(1.1, 0.9, 1.1)
	_arm_l.rotation.x = 0.25


func _build_tail() -> void:
	# とても大きな ふさふさ尻尾: 上うしろへ立ち上がり、横へ くるんと巻く。
	# オレンジ → クリーム → 白(先)。下側に クリームの ふくらみ。
	_tail = Node3D.new()
	_tail.position = Vector3(0.12, 0.55, -0.5)
	_tail.scale = Vector3.ONE * 0.86
	_g.add_child(_tail)
	var segs: int = 14
	for i in range(segs):
		var tt: float = float(i) / float(segs - 1)
		var ang: float = tt * 2.7
		var rad: float
		if tt > 0.84:
			rad = max(0.14, 0.6 - (tt - 0.84) * 2.0)
		else:
			rad = 0.32 + sin(tt * PI) * 0.5
		var col: Color = WHITE if tt > 0.82 else (CREAM if tt > 0.66 else ORANGE)
		var px: float = sin(tt * PI * 0.9) * 0.85 * tt
		var py: float = sin(ang) * 2.1 * tt
		var pz: float = -0.36 - cos(ang) * 1.0 * tt
		_sphere(rad, Vector3(px, py, pz), col, _tail)
		# 下側 クリームの ふくらみ
		if tt > 0.2 and tt < 0.8:
			var uc: Color = WHITE if tt > 0.55 else CREAM
			_sphere(rad * 0.62, Vector3(px, py - rad * 0.5, pz + rad * 0.35), uc, _tail)


# === メッシュ小物ヘルパー ===

func _ball(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	return m


func _cone(bottom_r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = bottom_r
	m.height = h
	return m


# リムライト付きの球を1つ置いて返す(本体パーツ用)。
func _sphere(r: float, pos: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	return _add_part(_ball(r), pos, color, parent)
