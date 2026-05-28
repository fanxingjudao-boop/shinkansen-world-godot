class_name TerrainHeight
extends RefCounted

# 地形の高さ・色を計算する純粋関数群。
# 設計方針: 言語非依存・テスト可能(docs/ARCHITECTURE.md)。
# Three.js プロトタイプの heightAt(x, z) を Godot に移植したもの。

const WORLD_SIZE: float = 400.0
const MESH_SUBDIV: int = 120  # 視覚メッシュの分割数。三角形 28800、Compatibility で軽量

# 山と湖のパラメータ(Three.js 版より移植)
const MOUNTAIN_A_POS: Vector2 = Vector2(90.0, -100.0)
const MOUNTAIN_A_HEIGHT: float = 18.0
const MOUNTAIN_A_RADIUS: float = 25.0
const MOUNTAIN_B_POS: Vector2 = Vector2(-110.0, -70.0)
const MOUNTAIN_B_HEIGHT: float = 22.0
const MOUNTAIN_B_RADIUS: float = 28.0
const MOUNTAIN_C_POS: Vector2 = Vector2(30.0, 130.0)
const MOUNTAIN_C_HEIGHT: float = 14.0
const MOUNTAIN_C_RADIUS: float = 20.0
const LAKE_POS: Vector2 = Vector2(-50.0, 80.0)
const LAKE_RADIUS: float = 22.0

# 高さに応じた色(草原・砂・雪山遷移)
const COLOR_GRASS: Color = Color(0.5, 0.78, 0.35)
const COLOR_SAND: Color = Color(0.85, 0.78, 0.55)
const COLOR_SNOW_LO: Color = Color(0.55, 0.7, 0.4)
const COLOR_SNOW_HI: Color = Color(0.95, 1.0, 0.9)


# 任意座標の地形高さを返す。
# Three.js heightAt(x, z) と数値が一致するように移植している。
static func compute_height(x: float, z: float) -> float:
	var h1: float = sin(x * 0.025) * cos(z * 0.03) * 1.8
	var h2: float = sin(x * 0.05)  * cos(z * 0.04) * 0.8
	var m1: float = _gaussian_mountain(x, z, MOUNTAIN_A_POS, MOUNTAIN_A_HEIGHT, MOUNTAIN_A_RADIUS)
	var m2: float = _gaussian_mountain(x, z, MOUNTAIN_B_POS, MOUNTAIN_B_HEIGHT, MOUNTAIN_B_RADIUS)
	var m3: float = _gaussian_mountain(x, z, MOUNTAIN_C_POS, MOUNTAIN_C_HEIGHT, MOUNTAIN_C_RADIUS)
	var lake_depth: float = _lake_depression(x, z)
	return h1 + h2 + m1 + m2 + m3 + lake_depth + _micro_noise(x, z)


# 高さに応じた頂点カラー。
# h > 10: 雪山(白に遷移)、-2 ≤ h ≤ 10: 草原、h < -2: 砂
static func compute_vertex_color(h: float) -> Color:
	if h > 10.0:
		var t: float = clamp((h - 10.0) / 8.0, 0.0, 1.0)
		return Color(
			lerp(COLOR_SNOW_LO.r, COLOR_SNOW_HI.r, t),
			lerp(COLOR_SNOW_LO.g, COLOR_SNOW_HI.g, t),
			lerp(COLOR_SNOW_LO.b, COLOR_SNOW_HI.b, t)
		)
	elif h < -2.0:
		return COLOR_SAND
	else:
		return COLOR_GRASS


# === 内部ヘルパー(static、純粋関数) ===

static func _gaussian_mountain(x: float, z: float, center: Vector2, height: float, radius: float) -> float:
	var d: float = Vector2(x - center.x, z - center.y).length()
	return height * exp(-d * d / (radius * radius * 0.5))


static func _lake_depression(x: float, z: float) -> float:
	var d: float = Vector2(x - LAKE_POS.x, z - LAKE_POS.y).length()
	if d < LAKE_RADIUS:
		return -(LAKE_RADIUS - d) * 0.25
	return 0.0


static func _micro_noise(x: float, z: float) -> float:
	return sin(x * 0.3) * cos(z * 0.3) * 0.04
