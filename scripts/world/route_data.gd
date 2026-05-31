extends RefCounted

# 線路網のルート定義(データ駆動)。
# 各編成は「自分専用の閉ループ」を 1 本持つ。曲線を共有しないので、速度差があっても
# 構造的に衝突・数珠つなぎが起きない(PathFollow3D は 1 本の Path3D 専用)。
# 平面で交差する箇所は「高さ(elevation)」で上下に分離するので、交差しても衝突しない。
#
# レイアウト(名所に絡める / 立体交差 / 本線の形変更):
#   - 本線: 波打つ大きな 3 車線ループ(マップ外周を蛇行)。同心スケールなので互いに交差しない。
#   - 名所ループ: 湖(SL=線路が水上に出て自動で橋脚)/ 山B(つばさ=トンネル候補)/ 街(やまのて)。
#   - 立体交差: つばめを高架の長い横長ループ(+8m、橋脚つき)にして他ルートの上を通す。
#   - ドクターイエロー: 他編成と同様に走行(dwell)。
#
# spec フィールド:
#   slug, center, rx, rz, rot_deg, wp_count
#   wave_amp/wave_freq : 半径を sin で波打たせる(本線の蛇行用、0 でただの楕円)
#   elevation          : ループ全体の追加高さ(立体交差/高架用。橋脚は railway が自動描画)
#   start_ratio        : 初期位置(全長比 0..1)
#   stops              : [{ ratio, kind:"dwell"|"park", seconds }]


static func specs() -> Array:
	var center := Vector2(0.0, 0.0)
	return [
		# === 本線(波打つ大きな 3 車線ループ・同心)=== 高速編成
		{
			"slug": "hayabusa", "center": center,
			"rx": 285.0, "rz": 250.0, "rot_deg": 0.0, "wp_count": 80,
			"wave_amp": 0.10, "wave_freq": 3.0,
			"start_ratio": 0.00, "stops": [{ "ratio": 0.00, "kind": "dwell", "seconds": 4.0 }],
		},
		{
			"slug": "kagayaki", "center": center,
			"rx": 277.0, "rz": 243.0, "rot_deg": 0.0, "wp_count": 80,
			"wave_amp": 0.10, "wave_freq": 3.0,
			"start_ratio": 0.33, "stops": [{ "ratio": 0.50, "kind": "dwell", "seconds": 3.0 }],
		},
		{
			"slug": "n700", "center": center,
			"rx": 269.0, "rz": 236.0, "rot_deg": 0.0, "wp_count": 80,
			"wave_amp": 0.10, "wave_freq": 3.0,
			"start_ratio": 0.66, "stops": [{ "ratio": 0.25, "kind": "dwell", "seconds": 4.0 }],
		},

		# === 名所ループ ===
		{
			# SL人吉: 湖をめぐる(線路が水上に出るので railway が自動で橋脚を立てる)
			"slug": "sl_hitoyoshi", "center": Vector2(-88.0, 140.0),
			"rx": 34.0, "rz": 29.0, "rot_deg": 0.0, "wp_count": 40,
			"start_ratio": 0.0, "stops": [{ "ratio": 0.0, "kind": "dwell", "seconds": 5.0 }],
		},
		{
			# つばさ: 山B(-192,-122)のふもとをめぐる(トンネル候補)
			"slug": "tsubasa", "center": Vector2(-175.0, -115.0),
			"rx": 30.0, "rz": 26.0, "rot_deg": 0.0, "wp_count": 36,
			"start_ratio": 0.0, "stops": [{ "ratio": 0.0, "kind": "dwell", "seconds": 5.0 }],
		},
		{
			# やまのて: 街をぐるりと囲む環状
			"slug": "e235_yamanote", "center": Vector2(150.0, 45.0),
			"rx": 34.0, "rz": 30.0, "rot_deg": 0.0, "wp_count": 36,
			"start_ratio": 0.0, "stops": [{ "ratio": 0.0, "kind": "dwell", "seconds": 3.0 }],
		},

		# === 中央ループ ===
		{
			"slug": "komachi", "center": Vector2(60.0, -30.0),
			"rx": 42.0, "rz": 36.0, "rot_deg": 0.0, "wp_count": 36,
			"start_ratio": 0.0, "stops": [{ "ratio": 0.5, "kind": "dwell", "seconds": 4.0 }],
		},
		{
			# つばめ: 高架の長い横長ループ(+8m)。他ルートの上を立体交差で通る。
			"slug": "tsubame", "center": center,
			"rx": 150.0, "rz": 46.0, "rot_deg": 0.0, "wp_count": 56,
			"elevation": 8.0,
			"start_ratio": 0.0, "stops": [{ "ratio": 0.0, "kind": "dwell", "seconds": 4.0 }],
		},
		{
			# ドクターイエロー: 他の編成と同じく走行(dwell)。子供には「止まっている=こわれた」に
			# 見えるため、車庫待機(park)はやめて走らせる(将来プレイヤーが呼べる機能は別途検討)。
			"slug": "doctor_yellow", "center": Vector2(-35.0, -45.0),
			"rx": 36.0, "rz": 32.0, "rot_deg": 0.0, "wp_count": 36,
			"start_ratio": 0.1, "stops": [{ "ratio": 0.0, "kind": "dwell", "seconds": 3.0 }],
		},
	]
