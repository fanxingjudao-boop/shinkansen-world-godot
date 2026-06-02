extends Node3D

# お城(おしろ)。かわいいパステルのお城を1つ建てる。Main 直下のノード。
#
# 仕掛け:
# - 中央に大きなアーチのトンネル(ローカル X 方向)があり、地上の「おしろでんしゃ」が
#   そこを通り抜ける(route_data の "oshiro" ループの北点 = CASTLE_CENTER で接線が X 方向)。
# - お城の上空は「そらでんしゃ」が高架ループ("sora" +17m)でぐるぐる回る。
#
# 当たり判定: 通路をふさがないよう、左右の壁(±Z)と四隅の塔だけ固くする。
# トンネル(子供も電車も通れる)と高い屋根・天守(手が届かない)には付けない。
#
# CASTLE_CENTER は route_data.gd の "oshiro"(center + (0, rz) = ここ)/"sora"(center = ここ)と一致。

const TerrainHeight = preload("res://scripts/world/terrain_height.gd")

const CASTLE_CENTER := Vector2(150.0, 135.0)

# パステルの配色(子供と大人が一緒に見てかわいい)
const IVORY: Color = Color(0.96, 0.93, 0.84)      # 城壁(クリーム)
const IVORY_DK: Color = Color(0.86, 0.82, 0.72)   # 基礎・帯
const ROOF_BLUE: Color = Color(0.42, 0.6, 0.9)    # 青い円錐屋根
const GOLD: Color = Color(1.0, 0.85, 0.32)        # 金の飾り
const FLAG: Color = Color(1.0, 0.58, 0.75)        # 桜色の旗
const STONE: Color = Color(0.74, 0.72, 0.68)      # アーチの石
const WINDOW_C: Color = Color(0.55, 0.85, 1.0)    # 窓(光る)

# 寸法(ローカル。アーチ通路は X 方向、±Z に城壁)
const WALL_LEN: float = 18.0      # 城壁の長さ(X)
const WALL_H: float = 9.0
const WALL_THICK: float = 2.2
const WALL_Z: float = 5.0         # 通路中心からの城壁中心までの距離(±Z)
const GATE_CLEAR_H: float = 6.0   # アーチの通路の高さ(これ以下は空ける)
const TOWER_R: float = 2.3
const TOWER_H: float = 16.0
const KEEP_W: float = 10.0
const KEEP_H: float = 12.0


func _ready() -> void:
	var gx: float = TerrainHeight.compute_height(CASTLE_CENTER.x, CASTLE_CENTER.y)
	position = Vector3(CASTLE_CENTER.x, gx, CASTLE_CENTER.y)
	# rotation.y = 0 → ローカル X = ワールド X(おしろでんしゃはここで X 方向に通り抜ける)
	_build()


func _build() -> void:
	_build_walls()
	_build_gate_roof()
	_build_keep()
	_build_towers()
	_build_gate_trim()


# 通路の左右(±Z)の城壁。上に小さな狭間(クレネル)を並べる。固い(当たり判定)。
func _build_walls() -> void:
	for sz in [-1.0, 1.0]:
		var cz: float = sz * WALL_Z
		_box(Vector3(WALL_LEN, WALL_H, WALL_THICK), Vector3(0, WALL_H * 0.5, cz), IVORY, 0.8)
		# 基礎の帯
		_box(Vector3(WALL_LEN + 0.4, 1.0, WALL_THICK + 0.3), Vector3(0, 0.5, cz), IVORY_DK, 0.8)
		# 金の帯
		_box(Vector3(WALL_LEN + 0.2, 0.4, WALL_THICK + 0.15), Vector3(0, WALL_H - 1.2, cz), GOLD, 0.5)
		# 狭間(クレネル)
		var n: int = 7
		for i in range(n):
			var x: float = lerpf(-WALL_LEN * 0.5 + 1.2, WALL_LEN * 0.5 - 1.2, float(i) / float(n - 1))
			_box(Vector3(1.1, 0.9, WALL_THICK), Vector3(x, WALL_H + 0.45, cz), IVORY, 0.8)
		# 窓(光る・通路の外側を向く)
		for wx in [-5.0, 0.0, 5.0]:
			_window(Vector3(wx, 3.2, cz + sz * (WALL_THICK * 0.5 + 0.02)))
		# 当たり判定(壁。通路 z は空けるので塞がらない)
		_add_box_collision(Vector3(WALL_LEN, WALL_H, WALL_THICK), Vector3(0, WALL_H * 0.5, cz))


# アーチ通路の上の天井(2つの城壁を上でつなぐ)。これより下(GATE_CLEAR_H)は通路で空ける。
func _build_gate_roof() -> void:
	var span_z: float = WALL_Z * 2.0 + WALL_THICK
	var thick: float = WALL_H - GATE_CLEAR_H
	_box(Vector3(WALL_LEN, thick, span_z), Vector3(0, GATE_CLEAR_H + thick * 0.5, 0), IVORY, 0.8)
	# 上面の金の縁
	_box(Vector3(WALL_LEN + 0.2, 0.3, span_z + 0.2), Vector3(0, WALL_H, 0), GOLD, 0.5)


# 中央の天守(てんしゅ)。アーチの上にそびえ、青い円錐屋根 + 金のしゃちほこ風 + 旗。
func _build_keep() -> void:
	var base_y: float = WALL_H
	_box(Vector3(KEEP_W, KEEP_H, KEEP_W), Vector3(0, base_y + KEEP_H * 0.5, 0), IVORY, 0.8)
	# 各階の金の帯 + 窓
	for fl in range(3):
		var y: float = base_y + 2.0 + fl * 3.4
		_box(Vector3(KEEP_W + 0.2, 0.3, KEEP_W + 0.2), Vector3(0, y + 1.2, 0), GOLD, 0.5)
		for sz in [-1.0, 1.0]:
			_window(Vector3(0, y, sz * (KEEP_W * 0.5 + 0.02)))
		for sx in [-1.0, 1.0]:
			_window(Vector3(sx * (KEEP_W * 0.5 + 0.02), y, 0))
	# 軒(屋根の下の張り出し)
	var eaves_y: float = base_y + KEEP_H
	_box(Vector3(KEEP_W + 1.6, 0.5, KEEP_W + 1.6), Vector3(0, eaves_y + 0.25, 0), ROOF_BLUE, 0.6)
	# 青い円錐屋根
	_cone(KEEP_W * 0.85, 5.5, Vector3(0, eaves_y + 0.5 + 2.75, 0), ROOF_BLUE)
	# てっぺんの金の玉 + 旗
	_sphere(0.6, Vector3(0, eaves_y + 0.5 + 5.5 + 0.3, 0), GOLD)
	_flag(Vector3(0, eaves_y + 0.5 + 5.5 + 0.6, 0), 3.0)


# 四隅の丸い塔(円柱 + 青い円錐屋根 + 旗)。固い(当たり判定)。
func _build_towers() -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var cx: float = sx * (WALL_LEN * 0.5 + 1.0)
			var cz: float = sz * (WALL_Z + 1.0)
			var c := Vector2(cx, cz)
			_cyl(TOWER_R, TOWER_H, Vector3(cx, TOWER_H * 0.5, cz), IVORY)
			# 金の帯
			_cyl(TOWER_R + 0.12, 0.5, Vector3(cx, TOWER_H - 1.5, cz), GOLD)
			# 窓
			_window(Vector3(cx, TOWER_H * 0.5, cz - TOWER_R - 0.02))
			# 軒 + 円錐屋根
			_cyl(TOWER_R + 0.5, 0.4, Vector3(cx, TOWER_H + 0.2, cz), ROOF_BLUE)
			_cone(TOWER_R + 0.55, 4.0, Vector3(cx, TOWER_H + 0.4 + 2.0, cz), ROOF_BLUE)
			# 旗
			_flag(Vector3(cx, TOWER_H + 0.4 + 4.0, cz), 2.2)
			# 当たり判定(塔。四角で近似)
			_add_box_collision(Vector3(TOWER_R * 2.0, TOWER_H, TOWER_R * 2.0), Vector3(cx, TOWER_H * 0.5, cz))


# アーチの入口(±X の口)を石の枠で飾る。丸いアーチ天井を段々の石で表現。
func _build_gate_trim() -> void:
	for sx in [-1.0, 1.0]:
		var x: float = sx * (WALL_LEN * 0.5)
		# 左右の柱(石)
		for sz in [-1.0, 1.0]:
			_box(Vector3(0.5, GATE_CLEAR_H, 0.6), Vector3(x, GATE_CLEAR_H * 0.5, sz * 3.6), STONE, 0.75)
		# アーチの段(上にいくほど内側へ寄せて丸みを出す)
		var steps: int = 4
		for i in range(steps):
			var t: float = float(i) / float(steps)
			var half_z: float = lerpf(3.6, 1.6, t)        # 上ほど狭く
			var y: float = GATE_CLEAR_H - 0.3 + t * 1.0
			_box(Vector3(0.5, 0.5, half_z * 2.0), Vector3(x, y, 0), STONE, 0.75)


# === ヘルパー(Godot 操作層) ===

func _box(size: Vector3, pos: Vector3, color: Color, rough: float) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = _mat(color, rough)
	mi.position = pos
	add_child(mi)


func _cyl(radius: float, height: float, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 14
	mi.mesh = c
	mi.material_override = _mat(color, 0.7)
	mi.position = pos
	add_child(mi)


func _cone(radius: float, height: float, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = 0.0
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = 16
	mi.mesh = c
	mi.material_override = _mat(color, 0.6)
	mi.position = pos
	add_child(mi)


func _sphere(radius: float, pos: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	mi.mesh = s
	mi.material_override = _mat(color, 0.4)
	mi.position = pos
	add_child(mi)


func _window(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(0.7, 1.0, 0.12)
	# 窓は法線方向(z)に薄い板。±Z 面用は上で z 位置を調整して呼ぶ。
	mi.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WINDOW_C
	mat.emission_enabled = true
	mat.emission = WINDOW_C
	mat.emission_energy_multiplier = 1.1
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.position = pos
	add_child(mi)


# 旗: 細いポール + 桜色のはためく板(billboard ではなく固定の小さな三角板)
func _flag(base: Vector3, pole_h: float) -> void:
	var pole := MeshInstance3D.new()
	var pc := CylinderMesh.new()
	pc.top_radius = 0.06
	pc.bottom_radius = 0.06
	pc.height = pole_h
	pole.mesh = pc
	pole.material_override = _mat(IVORY_DK, 0.6)
	pole.position = base + Vector3(0, pole_h * 0.5, 0)
	add_child(pole)
	var cloth := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.1, 0.6, 0.06)
	cloth.mesh = cm
	cloth.material_override = _mat(FLAG, 0.6)
	cloth.position = base + Vector3(0.55, pole_h - 0.5, 0)
	add_child(cloth)


func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = 0.05
	return m


# 当たり判定(StaticBody3D + BoxShape3D)。既定レイヤー=1 でプレイヤー(マスク=1)が衝突。
# トンネル(通路)と高い屋根には付けない。
func _add_box_collision(size: Vector3, center: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = center
	body.add_child(cs)
	add_child(body)
