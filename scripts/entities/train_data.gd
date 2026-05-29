class_name TrainData
extends Resource

# 列車の見た目・速度・性能を定義する Resource。
# 9 編成それぞれ .tres ファイルとして resources/train_data/ に置く。
# 新編成追加は .tres を 1 つ作るだけ、コード変更不要(データ駆動)。

# 表示名(ひらがな、図鑑用)
@export var display_name: String = ""

# 内部識別子(英数字、デバッグ用)
@export var slug: String = ""

# 車体メインカラー
@export var body_color: Color = Color.WHITE

# アクセントライン色(帯)
@export var accent_color: Color = Color.WHITE

# 楕円トラック上の最高速度(t を 1 秒あたりどれだけ進めるか、ラジアン/秒換算でない単位)
@export var speed: float = 0.1

# ノーズの形状: "sharp"(尖鋭)/ "rounded"(丸い)/ "steam"(SL の煙突)
@export var nose_type: String = "sharp"

# パンタグラフを持つか(電気機関車は true、SL は false)
@export var has_pantograph: bool = true

# 蒸気エフェクトを持つか(SL のみ true、Phase 2 後で実装)
@export var has_steam: bool = false

# 楕円上の初期位置(0..TAU 単位)。9 編成で重ならないように分散させる
@export var initial_t: float = 0.0
