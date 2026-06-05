extends CanvasLayer

# ミニマップ(ちず)。右上のすみに 小さく半透明で出す。迷わないための 目印。
# main.gd が _spawn_extra で起動時に生成(Main.tscn / TouchHUD.tscn は不変)。
#
# 見やすく・視界の邪魔をしない工夫:
# - 小さい(約152px)・半透明(うっすら)・右上のすみ(中央のあそび場と かぶらない)。
# - タップを すり抜ける(mouse_filter=IGNORE)ので ボタン操作の 邪魔をしない。
# - 別世界(つき/うみ/ぎんが等)や 電車に乗っている間は 自動で 隠す(地上の地図なので)。
#
# 北が 上の固定地図。主人公は 向きのわかる 白い矢印。湖=青・山=灰・街=オレンジ・お城=桃。

const MAP_SIZE: float = 152.0
const MAP_RANGE: float = 260.0   # 世界の ±260m を 地図に収める
const REFRESH: float = 0.12      # 地図の更新間隔(秒)。毎フレームは不要=軽い

# ランドマーク(terrain_height.gd / town.gd と同じ位置)
const TOWNS: Array = [Vector2(150, 45), Vector2(-70, 70), Vector2(-40, -110), Vector2(120, -150)]
const MOUNTAINS: Array = [Vector2(158, -175), Vector2(-192, -122), Vector2(52, 228)]
const LAKE: Vector2 = Vector2(-88, 140)
const CASTLE: Vector2 = Vector2(150, 132)

const C_BG := Color(0.10, 0.18, 0.28, 0.40)
const C_BORDER := Color(1, 1, 1, 0.55)
const C_LAKE := Color(0.45, 0.72, 0.96, 0.95)
const C_MOUNT := Color(0.60, 0.60, 0.64, 0.95)
const C_TOWN := Color(1.0, 0.66, 0.3, 0.98)
const C_CASTLE := Color(1.0, 0.62, 0.78, 0.98)
const C_PLAYER := Color(1, 1, 1, 1)
const C_PLAYER_LINE := Color(0.12, 0.2, 0.3, 1)
const C_NORTH := Color(1.0, 0.5, 0.55, 0.95)

var _player: Node3D = null
var _ride: Node = null
var _map: Control
var _t: float = 0.0


func _ready() -> void:
	layer = 1
	# 図鑑/おでかけメニュー/親モードを開くと get_tree().paused=true になる。
	# その間も _process を動かして「開いている間は地図を隠す」ため ALWAYS にする。
	process_mode = Node.PROCESS_MODE_ALWAYS
	_map = Control.new()
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 右上のすみ(上のボタン群の下・余白14px)に固定
	_map.anchor_left = 1.0
	_map.anchor_right = 1.0
	_map.anchor_top = 0.0
	_map.anchor_bottom = 0.0
	_map.offset_left = -(MAP_SIZE + 14.0)
	_map.offset_right = -14.0
	_map.offset_top = 84.0
	_map.offset_bottom = 84.0 + MAP_SIZE
	_map.draw.connect(_on_map_draw)
	add_child(_map)
	_resolve()


func _resolve() -> bool:
	var root := get_tree().root
	if _player == null:
		_player = root.find_child("Player", true, false) as Node3D
	if _ride == null:
		_ride = root.find_child("RideController", true, false)
	return _player != null


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = REFRESH
	# 図鑑/メニュー/親モードなど モーダルが開いている(paused)間は 隠す。
	if get_tree().paused:
		_map.visible = false
		return
	if not _resolve():
		_map.visible = false
		return
	# 乗車中は プレイヤー位置が 更新されない(物理OFF)ので、座標を見る前に 隠す。
	var riding: bool = _ride != null and _ride.has_method("is_riding") and _ride.is_riding()
	if riding:
		_map.visible = false
		return
	# 地上にいる時だけ 出す(別世界は 遠く/高い位置なので 隠す)。
	var p: Vector3 = _player.global_position
	var in_world: bool = absf(p.x) > 360.0 or absf(p.z) > 360.0 or p.y > 80.0
	_map.visible = not in_world
	if not in_world:
		_map.queue_redraw()


# 世界座標(x,z)→ 地図ピクセル(北=上)
func _w2m(wx: float, wz: float) -> Vector2:
	var s: float = MAP_SIZE / (MAP_RANGE * 2.0)
	return Vector2((wx + MAP_RANGE) * s, (wz + MAP_RANGE) * s)


func _on_map_draw() -> void:
	var sz := Vector2(MAP_SIZE, MAP_SIZE)
	# 背景(うっすら・角丸・ふち)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BG
	sb.set_corner_radius_all(16)
	sb.set_border_width_all(3)
	sb.border_color = C_BORDER
	_map.draw_style_box(sb, Rect2(Vector2.ZERO, sz))

	# 湖(青いまる)
	_map.draw_circle(_w2m(LAKE.x, LAKE.y), 7.0, C_LAKE)
	# 山(灰の三角)
	for m in MOUNTAINS:
		var c: Vector2 = _w2m(m.x, m.y)
		_map.draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -5.5), c + Vector2(-5, 4), c + Vector2(5, 4)]), C_MOUNT)
	# 街(オレンジの四角)
	for t in TOWNS:
		var c2: Vector2 = _w2m(t.x, t.y)
		_map.draw_rect(Rect2(c2 - Vector2(4, 4), Vector2(8, 8)), C_TOWN)
	# お城(桃のひし形)
	var cc: Vector2 = _w2m(CASTLE.x, CASTLE.y)
	_map.draw_colored_polygon(PackedVector2Array([
		cc + Vector2(0, -6), cc + Vector2(5, 0), cc + Vector2(0, 6), cc + Vector2(-5, 0)]), C_CASTLE)

	# 北の目印(上のふちに 小さな三角)
	var nc := Vector2(MAP_SIZE * 0.5, 8.0)
	_map.draw_colored_polygon(PackedVector2Array([
		nc + Vector2(0, -4), nc + Vector2(-4, 3), nc + Vector2(4, 3)]), C_NORTH)

	# 主人公(向きのわかる 白い矢印)
	if _player:
		var pp: Vector3 = _player.global_position
		var mp: Vector2 = _w2m(pp.x, pp.z)
		mp.x = clampf(mp.x, 8.0, MAP_SIZE - 8.0)   # はみ出さないよう ふちで止める
		mp.y = clampf(mp.y, 8.0, MAP_SIZE - 8.0)
		var fwd: Vector3 = -_player.global_transform.basis.z
		var d := Vector2(fwd.x, fwd.z)
		d = d.normalized() if d.length() > 0.01 else Vector2(0, -1)
		var perp := Vector2(-d.y, d.x)
		var tip: Vector2 = mp + d * 8.0
		var bl: Vector2 = mp - d * 5.0 + perp * 5.0
		var br: Vector2 = mp - d * 5.0 - perp * 5.0
		_map.draw_colored_polygon(PackedVector2Array([tip, bl, br]), C_PLAYER)
		_map.draw_polyline(PackedVector2Array([tip, bl, br, tip]), C_PLAYER_LINE, 1.5)
