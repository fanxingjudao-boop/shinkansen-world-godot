class_name SkyColor
extends RefCounted

# 時刻 t (0.0〜1.0) に応じた空・太陽・環境光の色と強度を計算する純粋関数群。
# Three.js プロトタイプの updateTimeOfDay() を Godot 4 に移植したもの。
# 設計方針: 言語非依存・テスト可能(docs/ARCHITECTURE.md)。

# 時刻区分
#   0.00-0.22  夜
#   0.22-0.32  朝焼け
#   0.32-0.70  昼
#   0.70-0.80  夕焼け
#   0.80-1.00  夜へ

const NIGHT_END: float = 0.22
const SUNRISE_END: float = 0.32
const DAY_END: float = 0.70
const SUNSET_END: float = 0.80

# 背景色
const NIGHT_BG: Color = Color(0.15, 0.18, 0.40)
const DAY_BG: Color = Color(0.72, 0.78, 0.96)
const SUNSET_BG: Color = Color(0.90, 0.48, 0.46)

# 太陽の光
const NIGHT_SUN: Color = Color(0.70, 0.70, 1.00)
const DAY_SUN: Color = Color(1.00, 1.00, 0.95)
const SUNSET_SUN: Color = Color(1.00, 0.65, 0.45)
const NIGHT_SUN_ENERGY: float = 0.3
const DAY_SUN_ENERGY: float = 0.9

# 環境光
const NIGHT_AMBIENT: Color = Color(0.50, 0.60, 0.80)
const DAY_AMBIENT: Color = Color(1.00, 0.97, 0.91)
const NIGHT_AMBIENT_ENERGY: float = 0.10
const DAY_AMBIENT_ENERGY: float = 0.25


# Fog の色(WorldEnvironment.fog_light_color)。
# 背景と同じ色を使い、空と fog が同化するようにする(夜の空が水色のままにならない)
static func fog_color(t: float) -> Color:
	return background(t)


# 背景色(WorldEnvironment.background_color)
static func background(t: float) -> Color:
	if t < NIGHT_END:
		return NIGHT_BG
	elif t < SUNRISE_END:
		return NIGHT_BG.lerp(DAY_BG, (t - NIGHT_END) / (SUNRISE_END - NIGHT_END))
	elif t < DAY_END:
		return DAY_BG
	elif t < SUNSET_END:
		return DAY_BG.lerp(SUNSET_BG, (t - DAY_END) / (SUNSET_END - DAY_END))
	else:
		return SUNSET_BG.lerp(NIGHT_BG, (t - SUNSET_END) / (1.0 - SUNSET_END))


# 環境光の色
static func ambient(t: float) -> Color:
	var day_amount: float = _day_amount(t)
	return NIGHT_AMBIENT.lerp(DAY_AMBIENT, day_amount)


static func ambient_energy(t: float) -> float:
	return lerp(NIGHT_AMBIENT_ENERGY, DAY_AMBIENT_ENERGY, _day_amount(t))


# 太陽光の色
static func sun_color(t: float) -> Color:
	if t < NIGHT_END:
		return NIGHT_SUN
	elif t < SUNRISE_END:
		return NIGHT_SUN.lerp(DAY_SUN, (t - NIGHT_END) / (SUNRISE_END - NIGHT_END))
	elif t < DAY_END:
		return DAY_SUN
	elif t < SUNSET_END:
		return DAY_SUN.lerp(SUNSET_SUN, (t - DAY_END) / (SUNSET_END - DAY_END))
	else:
		return SUNSET_SUN.lerp(NIGHT_SUN, (t - SUNSET_END) / (1.0 - SUNSET_END))


static func sun_energy(t: float) -> float:
	return lerp(NIGHT_SUN_ENERGY, DAY_SUN_ENERGY, _day_amount(t))


# 太陽の位置(円軌道、戻り値はワールド座標)
static func sun_position(t: float, radius: float, height_offset: float, z_offset: float) -> Vector3:
	var angle: float = t * TAU - PI * 0.5
	return Vector3(
		cos(angle) * radius,
		sin(angle) * radius + height_offset,
		z_offset
	)


# 内部ヘルパー: 「どれくらい昼か」(0=夜、1=昼)
# 太陽高度をベースに 0.0〜1.0 に正規化
static func _day_amount(t: float) -> float:
	# 太陽軌道は sin(t * TAU - PI/2) = -cos(t * TAU)
	# t=0.0 で -1(夜の真ん中)、t=0.5 で +1(昼の真ん中)
	var sun_height: float = -cos(t * TAU)
	return clamp((sun_height + 1.0) * 0.5, 0.0, 1.0)
