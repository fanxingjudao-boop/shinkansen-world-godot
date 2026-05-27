# ROADMAP — Godot 版 開発計画

Three.js プロトタイプで実証した楽しさを、Godot 4 で再構築し、本格的に作り込みます。

## 全体方針

- **Phase 0 がゲート**: Godot プロジェクトの初期化と最小限の動作確認
- **Phase 1 以降は段階的**: 1 つずつ確実に積み上げる
- **創作の自由度**: 各 Phase で「ROADMAP にないアイデア」も歓迎(改善さんに確認の上)

---

## Phase 0: プロジェクト初期化(必須・ゲート)

### 0-1. Godot 4 環境構築

- Godot 4.3 以降をダウンロード(改善さん側で実施)
- Standard 版(.NET 版は不要、GDScript で進めるため)
- `project.godot` を作成
- 設定:
  - `rendering/renderer/rendering_method` を `gl_compatibility` に
  - `display/window/size/viewport_width` 等を 1920×1080 に
  - `display/window/stretch/mode` を `viewport`、`aspect` を `expand`
  - `physics/3d/default_gravity` を 9.8

### 0-2. プロジェクト構造作成

`docs/ARCHITECTURE.md` のディレクトリ構造を作成:
- `scenes/`、`scripts/`、`resources/`、`assets/` などの空フォルダ
- `.gitignore` に `.godot/`、`*.tmp`、`export/`、`.import/` を追加

### 0-3. 最小限の動作確認

「キャラが歩く、カメラが追従する」だけを実装:

- `Player.tscn`: `CharacterBody3D` + 簡単な見た目(円柱と球)
- `Main.tscn`: 平らな地面、プレイヤー、カメラ
- `player.gd`: WASD で移動、ジャンプ(キーボード対応)
- カメラ追従(`Camera3D` を Player の子に、または独立した CameraRig で)

これが動けば Godot 環境が正しく動作している証拠。

### 0-4. タッチ入力の確認

PC キーボードに加えて、iPad のタッチ入力に対応:
- `InputEventScreenTouch` の取得
- 仮想 D-pad の UI(`CanvasLayer` 上のボタン)
- 「タッチ」ボタンの実装

### 0-5. Web Export 初回ビルド

- `Project > Export > Web` を設定
- カスタム HTML シェルを準備(`assets/web/template.html`)
- ローカルでビルド・確認(`python3 -m http.server` で配信)
- ブラウザで動作確認

### 0-6. ホスティング設定

- Vercel または GitHub Pages にアップロード
- COEP/COOP ヘッダー設定(Vercel の場合 `vercel.json`)
- iPad 実機での動作確認

**Phase 0 完了条件**: iPad の Safari でブラウザを開くと、キャラが歩いて操作できる状態。

---

## Phase 1: ワールド構築

### 1-1. 地形(Terrain)

- `PlaneMesh` を細かく分割した地形(`subdivide_width`, `subdivide_depth`)
- カスタムシェーダー or `MeshDataTool` で頂点に高さを与える
- 山 3 つ、湖 1 つ、川を表現(Three.js 版の `heightAt` 関数を GDScript で再現)
- 色は高さで変化(雪山の頂上、草原、湖辺の砂浜)
- マテリアル: `StandardMaterial3D`、`vertex_color_use_as_albedo = true`

### 1-2. 空と昼夜サイクル

- `WorldEnvironment` で `Sky` を設定
- `ProceduralSkyMaterial` or カスタムスカイシェーダー
- `day_night_cycle.gd` で時刻を進める
- 太陽の位置、空の色、霧の色を時刻に応じて変化
- 星空(夜のみ): `Sky` のカスタム or 大きな球のテクスチャ

### 1-3. 線路(Railway)

- `Path3D` で楕円形の線路を定義
- 2 本のレール: `CSGPolygon3D` で Path に沿わせる、または `MultiMeshInstance3D` で枕木を配置
- 枕木: `BoxMesh` を Path に沿って配置(`MultiMeshInstance3D` 推奨)
- レール: 細長い `CylinderMesh` または `BoxMesh`

### 1-4. 雲

- `MultiMeshInstance3D` で雲を配置
- 各雲は数個の球(`SphereMesh`)を組み合わせた `Node3D`
- 水平に流れるアニメーション
- 夕焼け時は雲が赤く染まる

### 1-5. 水

- `PlaneMesh` + 水面シェーダー(`assets/shaders/water.gdshader`)
- 頂点シフトで波
- フレネル反射で光沢
- 透明度で底が見える

### 1-6. 桜の花びら

- `GPUParticles3D` で大量の花びら
- `ParticleProcessMaterial` で重力 + ランダムな揺れ
- `BillboardMode = Y_BILLBOARD` で常にカメラ向き
- 桜色のテクスチャ(または `QuadMesh` + マテリアル)

**Phase 1 完了条件**: 美しい風景の中を散歩できる(列車・動物・星はまだ無し)。

---

## Phase 2: 列車システム

### 2-1. Train シーンの作成

`Train.tscn` を作成、`TrainData` リソースで個別化:

```
Train (Node3D + train.gd)
├── PathFollow3D (線路に追従)
│   └── Visual (Node3D)
│       ├── LeadCar (MeshInstance3D 群)
│       ├── MidCar
│       ├── TailCar
│       ├── ParticleEmitter (蒸気、SL のみ)
│       └── Headlight (SpotLight3D)
└── InteractArea (Area3D)
```

### 2-2. TrainData リソース

```gdscript
class_name TrainData extends Resource

@export var display_name: String
@export var body_color: Color
@export var accent_color: Color
@export var max_speed: float = 0.13
@export var nose_type: TrainNoseType
@export var description: String  # 図鑑用
@export var has_pantograph: bool = true
@export var emits_steam: bool = false
```

### 2-3. 9 編成の Train 配置

Three.js 版で実装した 9 種類を Resource として作成:
- はやぶさ(緑)、こまち(ピンク)、かがやき(白金)、N700(白青)、ドクターイエロー
- つばさ、つばめ、SL人吉、E235やまのて

### 2-4. 駅停車

- 駅近くで速度を 25% に落とす
- 通り過ぎたら元の速度に
- 駅構内アナウンス(後の Phase で実装)

### 2-5. 乗車システム

- 「タッチ」で電車に乗る
- カメラを電車の屋根 or 運転席に
- もう一度タッチで降車
- 最寄りの駅に降りる演出

**Phase 2 完了条件**: 9 種類の電車が線路を走り、乗ることができる。

---

## Phase 3: 駅・動物・星・図鑑

### 3-1. Station の実装

- `Station.tscn` テンプレート
- `StationData` リソース(駅名、色、装飾タイプ、サブテキスト)
- 6 駅(みどり・はな・やま・みずうみ・おかし・にじ)
- 各駅に固有装飾
- 駅看板は `Label3D` でテキスト表示

### 3-2. 動物 NPC

- `Animal.tscn` 基底シーン
- うさぎ、くま、きつね、ねこ、ぱんだ、いぬ、ぺんぎん、ぶたの 8 種
- 各動物は `Animal.tscn` を継承し、固有の見た目・モーション
- ふらふら歩き回る AI(`NavigationAgent3D` か簡易ステートマシン)
- 「タッチ」で会話、仲良し成立

### 3-3. 星(Collectibles)

- `Star.tscn`: `OctahedronGeometry` 風のメッシュ + エミッシブマテリアル
- 12 個配置、回転・浮遊アニメ
- 「タッチ」で獲得、`StarBurst.tscn` パーティクル発生

### 3-4. HUD

- 集めた星のカウンター
- 仲良しの動物のカウンター
- 列車図鑑の進捗
- 時刻インジケーター
- D-pad、ジャンプボタン、タッチボタン
- 全体の見た目は Three.js 版を踏襲

### 3-5. 図鑑(Book)

- `BookOverlay.tscn`: モーダル風 UI
- 3 タブ(列車・動物・駅)
- 発見済み/未発見の表示切替
- 列車をタップすると詳細(画像、説明、最高速度)

### 3-6. ミッション

- `MissionData` リソース
- 5 段階の優しいミッション
- クリア時の達成感演出

**Phase 3 完了条件**: ゲームの主要機能(集める・出会う・乗る・探す)がすべて動作。

---

## Phase 4: 美的演出の作り込み

### 4-1. シェーダー作り込み

- **トゥーンシェーディング**: 動物・キャラに適用、可愛さアップ
- **リムライト**: 物体の輪郭が光る、子供向けに優しい光
- **草の揺れ**: 頂点シェーダーで風になびく
- **水面**: 波 + 反射 + 透過の本格水シェーダー
- **空グラデーション**: 時刻と合わせた美しい色彩

### 4-2. パーティクル

- 桜の花びら(春)
- 紅葉(秋)
- 雪(冬)
- ホタル(夏の夜)
- 紙吹雪(クリア時)
- 星のキラキラ(獲得時)
- 蒸気(SL の煙突)

### 4-3. アニメーション

- プレイヤーの歩行(腕振り、頭の上下)
- 動物の固有モーション(うさぎはぴょんぴょん、ぺんぎんはよちよち)
- 列車の車輪回転(速度連動)
- パンタグラフの上下(電気機関車)
- 駅の旗・装飾の風揺れ

### 4-4. 音

- BGM: 場所別に 2〜3 曲(駅、走行中、夜)
- 駅到着アナウンス(合成 or フリー音源)
- 警笛、踏切音、動物の鳴き声
- 季節の環境音(風、波、虫の声)
- 全体の音量バランス調整

### 4-5. UI モーション

- ボタン押下時のバウンス
- 通知の登場アニメ(`Tween` で `ease_out_back`)
- メニュー開閉のスムーズな動き
- 数字カウントアップの演出

### 4-6. ポストエフェクト(限定的)

- `Environment > Glow` で軽い発光(星・電車のヘッドライト)
- `Environment > Adjustments` で全体の色調整
- 注意: `SSAO`、`SSR`、`Volumetric Fog` は Compatibility では不可

**Phase 4 完了条件**: 「グラフィックが綺麗!」と感じられる品質。

---

## Phase 5: PWA 化・配信

### 5-1. manifest.json

```json
{
  "name": "しんかんせんワールド",
  "short_name": "しんかんせん",
  "start_url": "./index.html",
  "display": "fullscreen",
  "orientation": "landscape",
  "background_color": "#7ec8f5",
  "theme_color": "#2868c9",
  "icons": [...]
}
```

### 5-2. Service Worker

Godot の Web Export には独自の Service Worker(`.service.worker.js`)が含まれる。
これに PWA 用のキャッシュ戦略を追加:

```javascript
const CACHE = 'shinkansen-v1';
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './index.wasm',
  './index.pck',
  // Godot が出力するファイル群
];
```

### 5-3. アイコン

- 192×192、512×512(通常 + maskable)
- apple-touch-icon 180×180
- 新幹線 + 空 + 星の可愛いアイコン

### 5-4. iOS スプラッシュ

`apple-touch-startup-image` 用の画像を準備。
iPad の各解像度向けに用意するのが理想(なくても起動はする)。

### 5-5. カスタム HTML テンプレート

Godot のデフォルト HTML を以下のようにカスタマイズ:

- メタタグ追加(viewport、apple-mobile-web-app-capable 等)
- PWA 関連リンク
- 100dvh 対応
- 横向き警告画面
- ローディング演出(電車アニメ)

### 5-6. 進捗保存

- `SaveSystem` Autoload を実装
- Web 環境では HTML5 LocalStorage を使用
- セーブタイミング: イベント発生時 + 1 分ごと

### 5-7. 親モード

- 設定画面(音量、季節固定、データリセット)
- 長押し 3 秒 + 4 桁 PIN で起動
- 子供の誤操作防止

**Phase 5 完了条件**: iPad の Safari でホーム画面に追加し、アプリ風にフルスクリーン起動できる。

---

## Phase 6: 体験を深める(継続的)

実際に遊んでもらってからのフィードバック対応。優先順位は改善さんが決める。

### 6-1. 駅前のお店

- お団子屋、お花屋、おみやげ屋
- 集めた星で交換、動物にプレゼント

### 6-2. ミニクエスト

- 駅長さんの「○○の電車を見つけてきて」
- 失敗概念なし、スタンプ収集

### 6-3. 季節モード

- 春夏秋冬の切り替え(設定で固定 or 自動)
- 各季節の固有装飾とイベント

### 6-4. 隠し電車

- 特殊条件で出現するレアな電車
- 流れ星後・虹発生時・全動物制覇後

### 6-5. 撮影モード強化

- 実際にキャプチャ・保存
- アルバム機能
- 動物・電車と一緒に写ったらバッジ

### 6-6. アクセシビリティ

- 色覚多様性配慮
- 音 OFF でも遊べる
- フォントサイズ調整

---

## Phase 7+: 自由なアイデア欄

ROADMAP に書いていないけれど、子供を喜ばせそうなアイデア:

- 朝の駅で焼きたてのパン屋さんの匂い演出(湯気)
- 動物が他の動物と話している会話を盗み聞きできる
- 線路に時々お花が咲いていて、それを摘める
- 季節の変わり目に「あきが きたよ!」とお知らせ
- 雨上がりに虹がかかる
- 流れ星の願い事
- 朝起きると新聞屋さんの自転車が走っている
- 夜になると駅員さんが眠そうにあくびをする
- 雨の日は動物たちが傘を持って歩く
- 列車の中から外を見られる視点モード

Claude Code が思いついたアイデアも、改善さんに相談の上で実装してください。

---

## 完了の概念

このプロジェクトに「ここまでで完成」という固定的なゴールはありません。
**お子さん・お孫さんが遊んで楽しんでくれている間、ずっと進化していくプロジェクト**です。

Phase 0〜5 が完了すれば iPad で本格的に遊べる状態に到達。
そこから先は、実際に遊んでもらってフィードバックを受け、改善さんが「次に何を作りたいか」を決めて、Claude Code が形にする、というサイクルで育てていきます。
