# ARCHITECTURE — Godot プロジェクト構造設計

## ディレクトリ構造

```
shinkansen-world/
├── project.godot              # Godot プロジェクト設定
├── icon.svg                   # Godot エディタ用アイコン
├── CLAUDE.md                  # Claude Code 作業指示書(ルート)
├── README.md
├── changelog.md
├── .gitignore                 # Godot 用(`.godot/`、`*.tmp` 除外)
├── docs/
│   ├── ARCHITECTURE.md        # 本ファイル
│   ├── HANDOFF.md             # 経緯と既知の課題
│   ├── ROADMAP.md             # 開発計画
│   └── GODOT_NOTES.md         # Godot 固有の知見
├── reference/
│   └── threejs-prototype/     # Claude.ai 版の参考実装
│       └── index.html
├── scenes/
│   ├── Main.tscn              # エントリーポイント
│   ├── world/
│   │   ├── World.tscn         # メインゲーム世界
│   │   ├── Terrain.tscn       # 地形
│   │   ├── Railway.tscn       # 線路
│   │   ├── Sky.tscn           # 空・雲・太陽
│   │   └── Water.tscn         # 湖・水
│   ├── entities/
│   │   ├── Player.tscn        # プレイヤーキャラ
│   │   ├── Train.tscn         # 新幹線テンプレート
│   │   ├── Station.tscn       # 駅テンプレート
│   │   ├── Star.tscn          # 集める星
│   │   └── animals/
│   │       ├── Animal.tscn    # 動物の基底
│   │       ├── Rabbit.tscn    # うさぎ
│   │       ├── Bear.tscn      # くま
│   │       └── ...
│   ├── ui/
│   │   ├── HUD.tscn           # ゲーム中の UI
│   │   ├── TitleScreen.tscn   # タイトル画面
│   │   ├── LoadingScreen.tscn # ロード画面
│   │   ├── BookOverlay.tscn   # 図鑑
│   │   ├── ParentMode.tscn    # 親モード(設定)
│   │   └── WinScreen.tscn     # クリア画面
│   └── fx/
│       ├── StarBurst.tscn     # 星獲得エフェクト
│       ├── HeartBurst.tscn    # ハート出現
│       ├── Confetti.tscn      # 紙吹雪
│       ├── CherryPetals.tscn  # 桜の花びら
│       └── Steam.tscn         # 蒸気
├── scripts/
│   ├── autoload/              # シングルトン(Autoload)
│   │   ├── GameState.gd       # ゲーム進捗管理
│   │   ├── AudioManager.gd    # 音楽・効果音
│   │   ├── SaveSystem.gd      # セーブ/ロード
│   │   ├── Settings.gd        # 設定管理
│   │   └── EventBus.gd        # シグナル中継
│   ├── world/
│   │   ├── terrain.gd
│   │   ├── railway.gd
│   │   ├── day_night_cycle.gd # 昼夜サイクル
│   │   └── ...
│   ├── entities/
│   │   ├── player.gd
│   │   ├── train.gd
│   │   ├── station.gd
│   │   ├── star.gd
│   │   └── animal.gd
│   ├── ui/
│   │   ├── hud.gd
│   │   ├── book.gd
│   │   └── ...
│   └── shaders/
│       ├── water.gdshader     # 水面シェーダー
│       ├── grass.gdshader     # 草の揺れ
│       └── toon.gdshader      # トゥーンシェーディング
├── resources/
│   ├── train_data/            # Train Resource 群
│   │   ├── hayabusa.tres
│   │   ├── komachi.tres
│   │   └── ...
│   ├── animal_data/           # Animal Resource 群
│   ├── station_data/          # Station Resource 群
│   └── save/                  # セーブデータのフォーマット定義
├── assets/
│   ├── fonts/
│   │   ├── MochiyPopOne-Regular.ttf
│   │   └── MPLUSRounded1c-Bold.ttf
│   ├── textures/
│   │   ├── terrain/
│   │   ├── trains/
│   │   └── ui/
│   ├── audio/
│   │   ├── bgm/
│   │   └── sfx/
│   └── models/                # 3D モデル(後述、最小限)
└── export/                    # ビルド出力先(.gitignore)
    ├── web/
    └── windows/
```

## 設計原則

### 1. シーンの階層化

Godot のシーンは「ノードの構成」で機能を定義します。再利用性を意識して以下の階層で組みます:

- **基底シーン**: `Animal.tscn` のような共通機能を持つテンプレート
- **派生シーン**: `Rabbit.tscn` が `Animal.tscn` を継承し、固有の見た目とモーションを追加
- **インスタンス**: ワールド配置時は派生シーンをインスタンス化

### 2. Resource によるデータ駆動

電車や動物の「データ」(色、速度、台詞、見た目)は GDScript の `Resource` クラスで定義し、`.tres` ファイルとして保存します。

```gdscript
# resources/train_data.gd
class_name TrainData
extends Resource

@export var display_name: String
@export var body_color: Color
@export var accent_color: Color
@export var max_speed: float = 0.13
@export var nose_type: String = "sharp"  # "sharp", "rounded", "steam"
@export var description: String  # 図鑑用
```

これにより、新幹線を追加するときは `.tres` ファイルを 1 つ作るだけで済みます(コード変更不要)。

### 3. Autoload によるグローバル状態

ゲーム全体で共有される状態は `Autoload`(シングルトン)で管理:

- **GameState**: 集めた星、出会った動物、発見した電車、訪れた駅
- **AudioManager**: BGM 再生、SFX 再生
- **SaveSystem**: localStorage 相当の保存先(Web では HTML5 LocalStorage、ネイティブでは `user://`)
- **Settings**: 音量、季節固定、その他親モード設定
- **EventBus**: シーン間のシグナル中継(密結合を避ける)

### 4. シグナル駆動

Godot の強みである **シグナル**(イベント通知)を活用:

```gdscript
# Star.gd
signal collected(star_node)

func _on_player_entered(body):
    if body.is_in_group("player"):
        collected.emit(self)
        queue_free()
```

シグナルは EventBus を経由して、UI や GameState に伝播させます。これによりシーン間の依存を減らせます。

### 5. グループによる識別

ノードを `Group` で識別:

- `"player"`: プレイヤーキャラ
- `"interactable"`: 「タッチ」で反応するもの
- `"train"`: 電車全般
- `"animal"`: 動物全般
- `"star"`: 集める星

これにより、衝突判定や検索が簡潔に書けます。

## 主要シーン解説

### Main.tscn

エントリーポイント。実質的には `TitleScreen` か `World` のどちらかを表示するだけのコンテナ。

```
Main (Node)
├── CurrentScene (Node) — 動的に TitleScreen / World を入れ替え
└── Fade (CanvasLayer + ColorRect) — シーン遷移用フェード
```

### World.tscn

ゲーム本編。以下を子ノードとして持つ:

```
World (Node3D)
├── Environment (WorldEnvironment) — 空、霧、ライティング
├── DirectionalLight3D (太陽)
├── Terrain (Terrain.tscn インスタンス)
├── Railway (Railway.tscn)
├── Stations (Node3D)
│   ├── MidoriEki (Station.tscn インスタンス + StationData リソース)
│   └── ... (6 駅)
├── Trains (Node3D)
│   ├── Hayabusa (Train.tscn + TrainData リソース)
│   └── ... (9 編成)
├── Animals (Node3D)
├── Stars (Node3D)
├── Decorations (Node3D)
│   ├── Trees (MultiMeshInstance3D で 150 本統合)
│   ├── Flowers (MultiMeshInstance3D)
│   └── Clouds (Node3D + AnimatedClouds.gd)
├── Player (Player.tscn インスタンス)
├── CameraRig (Node3D + CameraRig.gd)
│   └── Camera3D
└── UI (CanvasLayer)
    └── HUD (HUD.tscn インスタンス)
```

### Player.tscn

```
Player (CharacterBody3D)
├── MeshInstance3D (Body) — 円柱と球の組み合わせ
├── MeshInstance3D (Head)
├── MeshInstance3D (Cap)
├── ... (見た目のパーツ)
├── CollisionShape3D (CapsuleShape3D)
├── InteractArea (Area3D) — 「タッチ」検出範囲
│   └── CollisionShape3D (SphereShape3D, radius=3.5)
└── AnimationPlayer
```

### Train.tscn

```
Train (Path3D + PathFollow3D)
└── PathFollow3D
    └── TrainBody (Node3D)
        ├── LeadCar (MeshInstance3D + 各パーツ)
        ├── MidCar
        ├── TailCar
        ├── ParticleEmitter (蒸気用、SL のみ)
        └── Light (SpotLight3D, ヘッドライト)
```

Path3D は線路に沿った曲線で、PathFollow3D で電車を動かします。Three.js 版より遥かにエレガントに実装できます。

## C# 移行(将来)への配慮

ロジックを以下のように分離しておけば、将来 C# 移植時のコストを抑えられます:

1. **データクラス**(`Resource`)は構造体的なので C# 化が容易
2. **シーン**は言語非依存(`.tscn` ファイルは XML)
3. **ノードのスクリプト**を「ロジック層」と「Godot 操作層」に分けて書く

```gdscript
# 推奨パターン
extends Node3D

# === ロジック層(言語非依存・テスト可能) ===
func _calculate_train_position(t: float, speed: float, delta: float) -> float:
    return fmod(t + speed * delta, TAU)

# === Godot 操作層 ===
func _process(delta):
    var new_t = _calculate_train_position(current_t, speed, delta)
    path_follow.progress_ratio = new_t / TAU
    current_t = new_t
```

この設計だと、ロジック層は C# でも書きやすく、Godot 操作層だけが言語固有になります。

## アセット戦略

### モデル

- **新幹線**: Godot 内のプリミティブ(`BoxMesh`、`CylinderMesh`、`SphereMesh`)を組み合わせて作成
- **動物**: 同様にプリミティブで作成、可愛さ重視
- **建物・木**: プリミティブの組み合わせ

Blender で本格モデリングは**しません**。子供向けの「ふにふに」感はプリミティブの組み合わせの方が出ます。
Three.js 版で実証済みのアプローチを Godot で再現します。

### テクスチャ

- 駅看板のテキストは `Label3D` または `Viewport` で動的生成(Three.js 版と同様)
- 地面、線路、列車のテクスチャは基本的に単色 + マテリアル設定で済ませる
- 必要なら手描きの簡単なテクスチャ(草、木目、雲)を `assets/textures/` に追加

### 音

- BGM: 1〜2 曲、フリー素材(魔王魂、効果音ラボ等から)
- SFX: Web Audio 合成版を踏襲、または短いフリー素材
- 子供向けに優しいトーンを徹底

## 配信パイプライン

### Web Export

1. Godot エディタで `Project > Export > Add > Web` を選択
2. `Export Path` を `export/web/index.html` に設定
3. `Custom HTML Shell` で iPad 向けカスタマイズを適用(`docs/GODOT_NOTES.md` 参照)
4. `Export Project` でビルド
5. `export/web/` の中身を GitHub Pages または Vercel にアップロード

### 必要なヘッダー(Vercel)

```
# vercel.json
{
  "headers": [{
    "source": "/(.*)",
    "headers": [
      { "key": "Cross-Origin-Embedder-Policy", "value": "require-corp" },
      { "key": "Cross-Origin-Opener-Policy", "value": "same-origin" }
    ]
  }]
}
```

GitHub Pages はこのヘッダーが設定できないため、**SharedArrayBuffer を必要としないビルド設定**(`Threading: false`)で書き出す必要があります。これによりパフォーマンスは若干落ちますが、子供向けゲームでは問題になりません。

### PWA 化

Three.js 版と同じく `manifest.json` + Service Worker を Godot の出力に追加。
詳細は `docs/ROADMAP.md` の Phase 0 を参照。

## バージョン管理

- `main` ブランチ: 安定版
- 機能追加は `feature/xxx` ブランチで作業 → PR でレビュー
- `.gitignore` で除外: `.godot/`、`*.tmp`、`export/`、`.import/`
