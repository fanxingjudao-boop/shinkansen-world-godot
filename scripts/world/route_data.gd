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

		# === お城(castle.gd と連携)===
		{
			# おしろでんしゃ: お城のアーチ(中央トンネル)を貫いて走る地上ループ。
			# 北点(ratio 0.25)= お城の中心(150,135)で、そこで接線が X 方向 = アーチを真っ直ぐ通る。
			# castle.gd の CASTLE_CENTER と一致させること(中心 + (0, rz) = (150,135))。
			"slug": "oshiro", "center": Vector2(150.0, 117.0),
			"rx": 26.0, "rz": 18.0, "rot_deg": 0.0, "wp_count": 40,
			"start_ratio": 0.0, "stops": [{ "ratio": 0.62, "kind": "dwell", "seconds": 3.0 }],
		},
		{
			# そらでんしゃ: お城の上空を周回する高架ループ(+17m、railway が自動で橋脚)。
			"slug": "sora", "center": Vector2(150.0, 135.0),
			"rx": 25.0, "rz": 19.0, "rot_deg": 0.0, "wp_count": 44,
			"wave_amp": 0.10, "wave_freq": 3.0,  # 単純な円→蛇行する楕円(空をうねって飛ぶ感じ)
			"elevation": 17.0,
			"start_ratio": 0.0, "stops": [{ "ratio": 0.5, "kind": "dwell", "seconds": 3.0 }],
		},

		# === かくれた でんしゃ(B-7)===
		{
			# ゆめ: 夜だけ rare_train.gd が出現させる にじいろの夢の新幹線。専用の中ループ
			# (他ルートと別 Path3D なので衝突しない)。線路は常設・列車は夜だけ走る。
			# 位置・大きさは実機を見て調整可(他ルートや街と重ならないか)。
			"slug": "yume", "center": center,
			"rx": 120.0, "rz": 100.0, "rot_deg": 0.0, "wp_count": 56,
			"start_ratio": 0.0, "stops": [{ "ratio": 0.0, "kind": "dwell", "seconds": 4.0 }],
		},
	]


# === 分岐(ワープ式)データ ===
# うんてんしゅモードで運転中、from 編成のルート上 at_ratio 付近に来たら
# 「to 編成のルートへ乗り換える?」の選択肢を出す。選ぶと train.switch_route() で
# to ルートの to_ratio へ滑らかに(フェードで)載り替わる。
#
# 対象は本線3編成(hayabusa/kagayaki/n700)のみ。3編成は center(0,0) の同心・近接
# (径方向 ~8m)・同 elevation(0)なので、同じ ratio はほぼ同じ角度位置=横に並ぶ。
# そのため to_ratio ≒ at_ratio にすると、乗り換え前後で位置がほとんど飛ばない。
# つばめ(+8m 高架)や散在ループは高さ・距離が離れるため対象外。
#
# ratio は各ルートの停車点・初期位置を避けて選ぶ(乗り換え直後の停車点即ヒットを防ぐ):
#   hayabusa 停車 0.00 / kagayaki 停車 0.50 / n700 停車 0.25
static func branches() -> Array:
	return [
		# はやぶさ ⇄ かがやき(ratio 0.18 付近・どの停車点からも離れている)
		{ "from": "hayabusa", "at_ratio": 0.18, "to": "kagayaki", "to_ratio": 0.18 },
		{ "from": "kagayaki", "at_ratio": 0.18, "to": "hayabusa", "to_ratio": 0.18 },
		# かがやき ⇄ N700(ratio 0.40 付近)
		{ "from": "kagayaki", "at_ratio": 0.40, "to": "n700", "to_ratio": 0.40 },
		{ "from": "n700", "at_ratio": 0.40, "to": "kagayaki", "to_ratio": 0.40 },
		# N700 ⇄ はやぶさ(ratio 0.72 付近)
		{ "from": "n700", "at_ratio": 0.72, "to": "hayabusa", "to_ratio": 0.72 },
		{ "from": "hayabusa", "at_ratio": 0.72, "to": "n700", "to_ratio": 0.72 },

		# === 各地へ(本線 はやぶさ をハブに 名所へ往復)===
		# 離れたルートでも take_branch はフェード中点で載せ替えるので 飛びは見えない。
		# 行き先ルートには既に編成がいる(入れ替えで「1ルート1編成」を保つ)。
		# at_ratio/to_ratio は 各ルートの停車点を避ける(はやぶさ停車0.0・はやぶさ既存0.18/0.72)。
		# label = 子供向けの行き先名(HUD の2択・通知に使う)。
		{ "from": "hayabusa", "at_ratio": 0.10, "to": "komachi", "to_ratio": 0.25, "label": "まちの まんなか" },
		{ "from": "komachi", "at_ratio": 0.25, "to": "hayabusa", "to_ratio": 0.10, "label": "ほんせん" },
		{ "from": "hayabusa", "at_ratio": 0.30, "to": "sl_hitoyoshi", "to_ratio": 0.5, "label": "みずうみ" },
		{ "from": "sl_hitoyoshi", "at_ratio": 0.5, "to": "hayabusa", "to_ratio": 0.30, "label": "ほんせん" },
		{ "from": "hayabusa", "at_ratio": 0.45, "to": "tsubasa", "to_ratio": 0.5, "label": "やま" },
		{ "from": "tsubasa", "at_ratio": 0.5, "to": "hayabusa", "to_ratio": 0.45, "label": "ほんせん" },
		{ "from": "hayabusa", "at_ratio": 0.58, "to": "e235_yamanote", "to_ratio": 0.5, "label": "まち" },
		{ "from": "e235_yamanote", "at_ratio": 0.5, "to": "hayabusa", "to_ratio": 0.58, "label": "ほんせん" },
		{ "from": "hayabusa", "at_ratio": 0.85, "to": "oshiro", "to_ratio": 0.3, "label": "おしろ" },
		{ "from": "oshiro", "at_ratio": 0.3, "to": "hayabusa", "to_ratio": 0.85, "label": "ほんせん" },
		{ "from": "hayabusa", "at_ratio": 0.38, "to": "doctor_yellow", "to_ratio": 0.5, "label": "ドクターイエロー" },
		{ "from": "doctor_yellow", "at_ratio": 0.5, "to": "hayabusa", "to_ratio": 0.38, "label": "ほんせん" },
		{ "from": "hayabusa", "at_ratio": 0.65, "to": "tsubame", "to_ratio": 0.5, "label": "つばめ(こうか)" },
		{ "from": "tsubame", "at_ratio": 0.5, "to": "hayabusa", "to_ratio": 0.65, "label": "ほんせん" },
	]
