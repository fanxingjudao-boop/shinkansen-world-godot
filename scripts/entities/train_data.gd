class_name TrainData
extends Resource

# 列車の見た目・速度・性能を定義する Resource。
# 編成ごとに .tres ファイルとして resources/train_data/ に置く(現在11編成)。
# 新編成追加は .tres を 1 つ作り Main.tscn の Trains に1ノード足すだけ(データ駆動)。
# 図鑑・乗車・分岐にも自動で波及する。

# 表示名(ひらがな、図鑑用)
@export var display_name: String = ""

# 内部識別子(英数字、デバッグ用)
@export var slug: String = ""

# 車体メインカラー
@export var body_color: Color = Color.WHITE

# アクセントライン色(帯)
@export var accent_color: Color = Color.WHITE

# 速度感(周回の速さ)。train.gd で「一周 = TAU/speed 秒」に換算され、ルート長が
# 違っても編成ごとの速度感が保たれる(弧長ベース移動。旧・楕円角度ベースではない)。
@export var speed: float = 0.1

# ノーズの形状: "sharp"(尖鋭)/ "rounded"(丸い)/ "steam"(SL の煙突)
@export var nose_type: String = "sharp"

# パンタグラフを持つか(電気機関車は true、SL は false)
@export var has_pantograph: bool = true

# 蒸気エフェクトを持つか(SL のみ true、Phase 2 後で実装)
@export var has_steam: bool = false

# 初期位置などの旧フィールド(楕円時代の名残)。現在の配置は route_data.gd の start_ratio
# で管理しているため未使用だが、既存 .tres 互換のため残置。
@export var initial_t: float = 0.0

# 図鑑(ずかん)の詳細用。やさしいひらがな/カタカナの説明と、最高速度(km/h、表示は「キロ」)。
@export_multiline var description: String = ""
@export var top_speed_kmh: int = 0
