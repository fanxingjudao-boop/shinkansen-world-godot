extends RefCounted

# 線路網のルート定義(データ駆動)。
# 各編成は「自分専用の閉ループ」を 1 本持つ。曲線を共有しないので、速度差があっても
# 構造的に衝突・数珠つなぎが起きない(PathFollow3D は 1 本の Path3D 専用)。
#
# レイアウト方針(衝突を確実に避ける):
#   - 本線リング: 中心(0,0)の同心楕円を 4 車線。同心なので絶対に交差しない(=多線本線)。
#   - 中央ループ: 本線の内側(空きディスク, 半径 < 約150)に 5 つの独立ループを配置。
#     中心を半径 95・72°間隔に置き、互いに非重複(隣接中心間 ≈ 112m > ループ径 76m)。
#   これで立体交差(elevation)無しでも全ルートが交わらない。将来 elevation で
#   立体交差を足す余地は railway 側に残してある。
#
# spec の各フィールド:
#   slug        : 編成 slug と一致(train_data.slug)
#   center      : ループ中心 (XZ)
#   rx, rz      : 楕円半径
#   rot_deg     : 楕円の回転(度)
#   wp_count    : ウェイポイント数(Catmull-Rom で滑らかにする元の点数)
#   elevation   : ループ全体の追加高さ(立体交差用。今は 0)
#   start_ratio : 初期位置(全長比 0..1)
#   stops       : [{ ratio: float(0..1), kind: "dwell"|"park", seconds: float }]
#                 dwell=数秒停車して再発車 / park=停止して待機(将来プレイヤーが発車)

const MAINLINE_CENTER := Vector2(0.0, 0.0)


static func specs() -> Array:
	return [
		# === 本線リング(4 車線・同心)=== 高速編成
		{
			"slug": "hayabusa", "center": MAINLINE_CENTER,
			"rx": 232.0, "rz": 182.0, "rot_deg": 0.0, "wp_count": 56,
			"elevation": 0.0, "start_ratio": 0.00,
			"stops": [{ "ratio": 0.00, "kind": "dwell", "seconds": 4.0 }],
		},
		{
			"slug": "kagayaki", "center": MAINLINE_CENTER,
			"rx": 226.0, "rz": 176.0, "rot_deg": 0.0, "wp_count": 56,
			"elevation": 0.0, "start_ratio": 0.30,
			"stops": [{ "ratio": 0.50, "kind": "dwell", "seconds": 3.0 }],
		},
		{
			"slug": "komachi", "center": MAINLINE_CENTER,
			"rx": 220.0, "rz": 170.0, "rot_deg": 0.0, "wp_count": 56,
			"elevation": 0.0, "start_ratio": 0.60,
			"stops": [{ "ratio": 0.25, "kind": "dwell", "seconds": 4.0 }],
		},
		{
			"slug": "n700", "center": MAINLINE_CENTER,
			"rx": 214.0, "rz": 164.0, "rot_deg": 0.0, "wp_count": 56,
			"elevation": 0.0, "start_ratio": 0.85,
			"stops": [{ "ratio": 0.75, "kind": "dwell", "seconds": 4.0 }],
		},

		# === 中央の独立ループ(空きディスク内、半径 95・72°間隔)===
		{
			"slug": "e235_yamanote", "center": Vector2(95.0, 0.0),
			"rx": 42.0, "rz": 36.0, "rot_deg": 0.0, "wp_count": 36,
			"elevation": 0.0, "start_ratio": 0.0,
			"stops": [{ "ratio": 0.0, "kind": "dwell", "seconds": 3.0 }],
		},
		{
			"slug": "tsubame", "center": Vector2(29.3, 90.3),
			"rx": 40.0, "rz": 36.0, "rot_deg": 0.0, "wp_count": 36,
			"elevation": 0.0, "start_ratio": 0.0,
			"stops": [{ "ratio": 0.0, "kind": "dwell", "seconds": 4.0 }],
		},
		{
			"slug": "tsubasa", "center": Vector2(-76.9, 55.8),
			"rx": 40.0, "rz": 36.0, "rot_deg": 0.0, "wp_count": 36,
			"elevation": 0.0, "start_ratio": 0.0,
			"stops": [{ "ratio": 0.0, "kind": "dwell", "seconds": 5.0 }],
		},
		{
			"slug": "sl_hitoyoshi", "center": Vector2(-76.9, -55.8),
			"rx": 40.0, "rz": 36.0, "rot_deg": 0.0, "wp_count": 36,
			"elevation": 0.0, "start_ratio": 0.0,
			"stops": [{ "ratio": 0.0, "kind": "dwell", "seconds": 5.0 }],
		},
		{
			# ドクターイエロー: 車庫(park)。普段は車庫で待機、将来プレイヤーが呼べる目玉。
			"slug": "doctor_yellow", "center": Vector2(29.3, -90.3),
			"rx": 40.0, "rz": 36.0, "rot_deg": 0.0, "wp_count": 36,
			"elevation": 0.0, "start_ratio": 0.1,
			"stops": [{ "ratio": 0.0, "kind": "park", "seconds": 0.0 }],
		},
	]
