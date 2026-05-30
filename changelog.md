# Changelog

verification-agent LIGHT モードで Claude Code が変更を記録します。

## v0.12.0 — 2026-05-30 — Phase 3-2(動物がふらふら歩く + なかよし)

世界に 8 種の動物が現れ、草原をぴょこぴょこ歩き回り、近づくと「なかよし」になるようになった。データ駆動。
なかよしは改善さんの選択で「近づくと自動」方式(タッチ不要=3歳児にやさしい、乗車の interact と競合しない)。

- `scripts/entities/animal_data.gd` 新規 — `class_name AnimalData` extends Resource。`display_name` / `slug` / `species` / `body_color` / `accent_color` / `belly_color` / `scale_factor` を `@export`
- `scripts/entities/animal.gd` 新規 — extends Node3D。
  - 見た目を species ごとにスクリプト生成(体+おなか+頭+目、+ 耳/鼻/くちばし/しっぽ)。丸っこいデフォルメ
  - 簡易ステートマシン(IDLE ⇄ WALK)で `_home`(初期位置)半径 8m 内をふらふら。`randf_range` で状態時間と向きをランダム化
  - 歩行中は進行方向へ滑らかに向き(`lerp_angle`)、`sin` で上下バウンス(ぴょこぴょこ)。地形高さに追従(衝突なし=子供向けにすり抜けOK)
- `scenes/entities/Animal.tscn` 新規 — Node3D + animal.gd だけ(見た目は全部スクリプト生成、AnimalData で変わるので静的化しない)
- `resources/animal_data/*.tres` 新規 8 個 — うさぎ(rabbit)/ くま(bear)/ きつね(fox)/ ねこ(cat)/ ぱんだ(panda)/ いぬ(dog)/ ぺんぎん(penguin)/ ぶた(pig)
- `scripts/world/animal_manager.gd` 新規 — `Animals` ノードに付与。プレイヤーが `BEFRIEND_RANGE = 3m` 内に近づいた未なかよしの動物を `befriend()` させ、HUD に「○○と なかよし!」通知。`signal befriended(display_name, total)`(将来の HUD カウンター / 図鑑用)。interact を使わないので乗車と競合しない
- `scripts/entities/animal.gd` 追記 — `befriend()`(立ち止まって `ease_out_back` → `bounce` でぴょんと喜ぶ)/ `is_befriended()` / `get_display_name()`。喜びジャンプ中(`_celebrating`)は移動・バウンスを止める
- `scenes/Main.tscn` 修正 — `Animals`(Node3D + animal_manager)を追加(player_path / hud_path 配線)、配下に 8 体を線路内側の草原に配置
- `scripts/dev/auto_capture.gd` 修正 — `ViewMode.ANIMAL`(造形確認)+ `CaptureMode.AUTO_BEFRIEND`(プレイヤーをうさぎ隣にテレポートして なかよし通知を撮る検証フック)を追加

### 検証

- AutoCapture(ANIMAL ビュー)で うさぎ を確認: 白い丸い体・ピンクの長い耳・丸尾のかわいいデフォルメ。奥に他の動物・電車。スクリプトエラーなし
- AutoCapture(AUTO_BEFRIEND)で「うさぎと なかよし!」通知が出ることを確認(プレイヤー近接 → 自動成立)
- 修正したハマり: `_home` は Vector2 なので `.z` 不可 → `.y`(z 座標相当)に修正(Parse Error: Cannot find member "z" in base "Vector2")

### 範囲外(今回は実装せず)

- なかよし数の HUD カウンター表示(Phase 3-4 HUD で。`signal befriended` は布石済み)
- 動物との会話・固有モーションの作り込み(Phase 4 演出)

次のステップ: 改善さんに体験確認 → Phase 2-4(駅停車)/ 3-3(星獲得)/ 3-4(HUD カウンター)/ 3-5(図鑑)へ

## v0.11.0 — 2026-05-30 — Phase 3-1(駅をつくる)

線路沿いに 6 つの駅が立ち、世界に「目的地」ができた。データ駆動(TrainData と同方針)。

- `scripts/world/station_data.gd` 新規 — `class_name StationData` extends Resource。`display_name` / `sub_text`(看板の大小)/ `slug` / `main_color` / `accent_color` / `decor_type` / `track_t`(楕円上の配置)を `@export`
- `scripts/world/station.gd` 新規 — extends Node3D。`_ready` で `Railway.ellipse_point(track_t)` から線路脇の位置を求め、`rotation.y` を線路接線に合わせて配置。プラットフォーム(色違い床+アクセント縁)+ 屋根(柱4本+屋根板)+ 看板(Label3D ×2、常に読める `BILLBOARD_FIXED_Y`+太アウトライン)+ 固有装飾を全部スクリプト生成
  - 湖の上の区間(`track_t` が湖の半径内)では線路と同様に `compute_water_y()` 以上へ持ち上げ、駅が沈まないようにした
  - 装飾 `decor_type`: tree(木)/ flower(花壇)/ mountain(雪山)/ lake(池)/ sweets(三色だんご)/ rainbow(3本アーチの虹)を `match` で組み立て
- `scenes/world/Station.tscn` 新規 — Node3D + station.gd だけ(中身は全部スクリプト生成、StationData で色・装飾が変わるので静的化しない)
- `resources/station_data/*.tres` 新規 6 個 — みどり(tree, t=0)/ はな(flower, t=1.05)/ みずうみ(lake, t=2.09 ・湖のほとり)/ やま(mountain, t=3.14)/ おかし(sweets, t=4.19)/ にじ(rainbow, t=5.24)。楕円を 6 等分しつつ、湖にかかる t≈2.09 を「みずうみ駅」に割り当て
- `scenes/Main.tscn` 修正 — `Stations`(Node3D)を追加、配下に 6 駅インスタンス(各 station_data を override)
- `scripts/dev/auto_capture.gd` 修正 — `ViewMode.STATION`(みどり駅を間近で撮影)を追加

### 検証

- AutoCapture(STATION ビュー)で みどり駅を確認: 緑屋根+白柱のプラットフォーム、「みどり」「もりの えき」の看板が読める、木の装飾、はやぶさが駅前走行。スクリプトエラーなし
- BIRD ビューで 6 駅が楕円線路沿いに分散配置、みずうみ駅が湖際に沈まず立っていることを確認
- 子供向け配慮: ひらがなのみ、明るいパステル、怖い要素なし、看板は常に正面を向き読める

### 範囲外(今回は実装せず)

- 駅停車(Phase 2-4): 駅近くで電車が減速 → 次の周回で追加候補
- 駅に降りる演出(乗車システムの降車を最寄り駅に寄せる)
- 駅の図鑑タブ(Phase 3-5)

次のステップ: 改善さんに見た目確認(看板を空中ビルボードのままにするか、立て看板にするか等)→ 駅停車 or Phase 3-2(動物)へ

## v0.10.0 — 2026-05-30 — Phase 2-5(電車に乗るシステム)

走行中の電車に乗って、屋根の上から見下ろす視点でいっしょに線路を旅できるようになった。
乗車視点は改善さんの選択(屋根の上から見下ろす)を採用。

- `scripts/world/ride_controller.gd` 新規 — Main 直下のノード(extends Node3D)。乗車状態の中核:
  - 状態機械 `enum State { WALKING, RIDING }`。`interact`(タッチ / E / Enter)のトグルで乗降
  - `is_action_just_pressed("interact")` の唯一の消費者(従来 touch_hud が action_press するだけで誰も消費していなかった)
  - 乗降直後の即トグルを防ぐ `TOGGLE_DEBOUNCE = 0.4s`
  - `_find_nearest_ridable()`: プレイヤーから `RIDE_RANGE = 14m` 以内で最寄りの編成を選ぶ(編成中央のワールド位置で判定)
  - 乗車カメラを電車の PathFollow3D(ROTATION_ORIENTED, -Z 進行方向)の子に **ローカル固定 transform** で生成 → 進行方向に追従しつつ一切揺れない。屋根上俯瞰(pos (0,6,6)・pitch -28°・fov 60)、`current=true` で切替、降車で元の CameraRig/Camera3D に戻す
  - フェード遷移: HUD の全画面 ColorRect を Tween(0→1→中点でカメラ/プレイヤー切替→1→0、片道 0.25s)で噛ませ、カメラ切替の瞬間を隠す(怖くない・酔わない)
  - 降車は「その場の線路脇に降りる」簡易版(駅未実装のため)。`_compute_landing()` で編成中央から進行方向の直交・楕円外側へ `LANDING_OFFSET = 6m` ずらし、`TerrainHeight.compute_height + 1.5` で地形に着地(電車・レール・枕木に重ならない)
  - 判定ロジック `_nearest_index` / `_compute_landing` は static 純粋関数(C# 移植配慮)
  - `signal boarded` / `alighted`(将来の図鑑連携用)
- `scripts/entities/train.gd` 修正 — public API 追加(既存挙動は不変): `get_ride_anchor_position()`(編成中央の現在ワールド位置)/ `get_ride_mount()`(PathFollow3D, カメラのぶら下げ先)/ `get_ride_forward()`(進行方向)/ `get_display_name()`
- `scripts/ui/touch_hud.gd` + `scenes/ui/TouchHUD.tscn` 修正 — 乗車 UI:
  - `Prompt`(Label): 「○○に のる?」を上部中央にパステル枠付きで表示
  - `Notice`(Label): 「○○に のったよ!」を `ease_out_back` バウンス + フェードで登場、1.6s 後にフェードアウト
  - `Fade`(全画面 ColorRect, alpha 0): 遷移演出用。`set_fade_alpha(a)` で RideController の Tween から駆動
  - `set_riding(bool)`: 乗車中はタッチボタンを「タッチ」↔「おりる」に出し分け、D-pad を `disabled` + 薄表示(動かせないことを明示)
- `scenes/Main.tscn` 修正 — `Main` 直下に `RideController` を追加、player/trains/camera_rig/hud の NodePath を配線
- `scripts/dev/auto_capture.gd` 修正 — `CaptureMode.AUTO_RIDE` 追加。最寄り電車に強制乗車して屋根上視点を撮影 → 降車後を撮影(`_do_board`/`_do_alight` を直接叩く検証フック、本番コードは汚さない)

### 検証

- AutoCapture(AUTO_RIDE)で乗車・降車を無人撮影。スクリプトエラーなし
- 乗車スクショ: 屋根の上から進行方向を見下ろす視点、編成と前方の線路が見える。D-pad 薄表示・「おりる」ボタン・「のったよ!」通知を確認
- 降車スクショ: 線路脇(編成中央から 6m 外側・地形+1.5m)に着地、カメラと UI が歩行状態に復帰。位置ログで player=(101.1, 1.84, 25.3) / anchor=(95.5, 0.75, 23.1)、xz 距離 ~6m・Y は電車と重ならないことを確認
- 型安全: `train.gd` / `touch_hud.gd` は class_name 非対応(CLI スキャン問題)のため、`ride_controller` 側で `preload` const を型注釈に使い静的解決(train_data.gd と同方針)

### 範囲外(今回は実装せず)

- 運転席視点への切替(将来 ROADMAP 7「車内視点モード」で追加候補)
- 駅停車(Phase 2-4)/ 駅に降りる演出(Phase 3 駅と同時)
- 列車運転(加減速操作)

次のステップ: 改善さんに PC ブラウザ / iPad で体験確認 → Phase 3(駅・動物・星・図鑑)へ

## v0.9.1 — 2026-05-29 — 列車のリアル化(改善さんフィードバック対応)

改善さん「もっとリアルな新幹線にできませんか?」のフィードバック対応。4 つの方向で改修。

- `scripts/entities/train.gd` 大幅改修:
  - **編成を 3 両 → 5 両**(LEAD + MID×3 + TAIL、総長 ~26m)
  - **窓を一本の長い帯 → 個別小窓**(先頭/末尾車 4 個、中間車 6 個、両側面)
  - **ノーズを CylinderMesh(円錐)に**:
    - sharp: top_radius=0.12、bottom_radius=0.92、長さ 3.2m(はやぶさ風ロングノーズ)
    - rounded: top_radius=0.55、bottom_radius=0.95、長さ 2.2m + 先端 SphereMesh(N700 風カモノハシ)
    - steam: 横向き CylinderMesh(ボイラー)+ 縦の煙突(SL 風)
  - **台車を追加**: 各車両 2 台(前後)、台車枠 BoxMesh + 車輪 4 個ずつ
  - **連結部を追加**: 車両と車両の間に小さな BoxMesh(暗灰)、ジャバラ感
  - **パンタグラフを「く」の字 + 集電板に改良**(従来の単一バーから 2 本アーム + 上の横長 BoxMesh へ)
- `scripts/dev/auto_capture.gd`: `TRAIN_CLOSE` ビューモード追加(Hayabusa initial_t=0 の楕円起点 (100, 0) を間近で撮影)

スクリーンショットで Hayabusa の側面・小窓・台車・連結部・5 両編成が確認できた。子供向けの「ふにふに感」とのバランスは保持(プリミティブの組み合わせのまま、Blender モデリングは導入せず)。

## v0.9.0 — 2026-05-29 — Phase 2-1 + 2-2 + 2-3(9 編成の新幹線が線路を走る)

- `scripts/entities/train_data.gd` 新規 — `class_name TrainData` extends Resource。9 項目(display_name / slug / body_color / accent_color / speed / nose_type / has_pantograph / has_steam / initial_t)を `@export`
- `scripts/entities/train.gd` 新規 — `_ready` で Railway の Path3D を取得し、PathFollow3D を動的 `add_child`。`_process` で t を進めて `progress_ratio = t / TAU` を更新。`_build_visual()` で 3 両編成(LeadCar + MidCar + TailCar)+ 各車両のパーツ(本体 / アクセント帯 / 窓帯 unshaded / 車輪 4 個 / ノーズ / ヘッドライト / パンタグラフ)を全部スクリプト生成
- `scenes/entities/Train.tscn` 新規 — Node3D + train.gd だけ(中身は全部スクリプト生成、TrainData で色や形が変わるので静的シーン化不可)
- `resources/train_data/*.tres` 新規 9 個 — はやぶさ / こまち / かがやき / N700 / ドクターイエロー / つばさ / つばめ / SL人吉 / E235やまのて(Three.js プロトタイプの色・速度・配置をそのまま移植)
- `scenes/Main.tscn` 修正 — `Trains (Node3D)` 追加、配下に 9 編成インスタンス。各 train_data + railway_path を override で指定
- `scripts/world/railway.gd` 修正 — `func get_track_path() -> Path3D` を公開 API として追加(Train から呼ばれる、ただし現状は NodePath で直接アクセスで動作)

### Three.js から移植した 9 編成

| 名前 | body | accent | nose | speed | initial_t |
|------|------|--------|------|-------|-----------|
| はやぶさ | 緑 #009944 | ピンク #ff6b9a | sharp | 0.13 | 0.0 |
| こまち | 赤 #ff5577 | 白 | sharp | 0.11 | 0.9 |
| かがやき | 白 #fafafa | 金 #c9a44d | sharp | 0.14 | 1.8 |
| N700 | 白 | 青 #0066cc | rounded | 0.12 | 2.7 |
| ドクターイエロー | 黄 #ffe066 | 青 | rounded | 0.09 | 3.6 |
| つばさ | 紫 #b6a4ff | 金 #ffd700 | sharp | 0.10 | 4.5 |
| つばめ | 紺 #222244 | 金 | sharp | 0.13 | 1.4 |
| SL人吉 | 黒 #1a1a1a | 赤 #c0392b | steam | 0.07 | 5.0 |
| E235やまのて | 黄緑 #b5e853 | 白 | rounded | 0.15 | 3.0 |

### 重要な設計判断

- **データ駆動**: 新編成追加は .tres を 1 つ作るだけ、コード変更不要
- **PathFollow3D を動的 add_child**: Train.gd の _ready で Railway.Path3D の子に PathFollow3D を作って自身の visual を add_child。9 編成全部が同じ Railway.Path3D を共有
- **メッシュは個別 MeshInstance3D**(9 編成 × 3 両 × ~10 パーツ = 約 270 個、Compatibility で問題ない数)
- **窓は UNSHADED**(夜でも水色に光る感)、本体・アクセントは shaded
- **衝突なし**: 列車同士はすり抜け(子供向けに「ぶつかった!」の悲しみを回避)

### 範囲外(今回は実装せず)

- Phase 2-4 駅停車(Phase 3 駅と同時)
- Phase 2-5 乗車システム(UI 大改修)
- SL の蒸気エフェクト / ヘッドライトの夜間光 / 車輪回転 / パンタグラフ上下動 → Phase 4 演出

次のステップ: Phase 3(駅・動物・星・図鑑)に着手

## v0.8.0 — 2026-05-29 — Phase 1-5(湖の water シェーダー)→ **Phase 1 完了**

- `assets/shaders/water.gdshader` 新規 — Godot Shading Language(GLSL ベース)。`shader_type spatial`、`render_mode cull_back, diffuse_lambert, specular_schlick_ggx`。頂点シェーダーで sin/cos 波(`wave_strength 0.08`、`wave_frequency 1.5`、`wave_speed 0.8`)、フラグメントで水色 albedo + 高スペキュラ(0.85)
- `scripts/world/terrain.gd` 修正 — `_generate_lake` 書き直し: `CylinderMesh` → `PlaneMesh + subdivide 32×32`(波計算用に細分化)、`StandardMaterial3D` → `ShaderMaterial(water.gdshader)`。湖サイズは `LAKE_RADIUS * 2 + 4`(山の壁で余分は隠れる)。水面 Y を `compute_height(中心) + 4.5` に上げて湖の谷の縁近くに配置(深い谷の底だと水面がほぼ地形に隠れる)

### 試行錯誤メモ

- **半透明 + フレネル**(初期案)→ 上から見ると透けすぎて地形が見えるだけで湖が認識できない → 不透明に妥協
- **円形 ArrayMesh**(自作)→ triangle fan は CCW で動くが ring 間の三角形がどの順序でも背面カリングされて描画されない → デバッグに時間使うより `PlaneMesh` で確実に動かす方を選択
- **水面 Y = 湖底 + 0.3**(初期)→ 湖の谷が深さ ~5m に対し水面 30cm 上だと、ほぼ全面が地形に隠れる → +4.5m に上げて湖らしい広さの水面に

### Phase 1 全体の総括

- ✅ 1-1 地形(400×400、山 3 + 湖、頂点カラー、HeightMapShape3D 衝突)
- ✅ 1-2 空と昼夜サイクル(84 秒、SkyColor 関数、太陽の動き)
- ✅ 1-3 線路(楕円 Path3D、レール 2 本統合 ArrayMesh、枕木 MultiMesh 157 本)
- ✅ 1-4 雲(18 個、6 球の集合、水平流れ)
- ✅ 1-5 湖(PlaneMesh + water.gdshader、波 + スペキュラ)
- ✅ 1-6 桜の花びら(GPUParticles3D、Player 追従)
- ✅ 派生: 星 12 個(夜のみ visible)、自動スクリーンショット基盤

子供にとって「歩ける + 線路がある + 空が動く + 雲が流れる + 桜が舞う + 湖がある + 夜に星が出る」世界が立ち上がった。次は Phase 2(列車システム、9 編成の新幹線)。

## v0.7.0 — 2026-05-29 — Phase 1-6(桜の花びら)

- `scenes/fx/CherryPetals.tscn` 新規 — `GPUParticles3D` 単体、スクリプトなし。`ParticleProcessMaterial` + `QuadMesh`(0.4×0.4) + `StandardMaterial3D`(UNSHADED、半透明、BILLBOARD_PARTICLES)を sub_resource として埋め込み
- `scenes/Main.tscn` 修正 — Player ノードの **子** として CherryPetals をインスタンス化(Player に追従して常に取り囲む)、Player の頭上 10m に配置

### 主要パラメータ

- `amount = 250`、`lifetime = 6.0`、`preprocess = 3.0`(起動時から既に降っている)
- `emission_shape = BOX`、`emission_box_extents = (15, 0.1, 15)` で Player 中心 30m 四方の薄い天井から発生
- `direction = (0, -1, 0)`、`gravity = (0, -1.5, 0)`、`initial_velocity 0.3〜0.8`
- `angular_velocity ±30°/s` で回転しながら舞う
- `turbulence_enabled = true`、`turbulence_noise_strength = 0.5` で sin/cos の代替(ふわふわ感)
- `scale 0.4〜1.0` 倍 → 16cm〜40cm の花びら(子供視点で見える + 近距離で巨大化しない)
- 色 `#ffc4dd` 薄ピンクベージュ、alpha 0.8(Three.js プロトタイプと同じ)

### 試行錯誤メモ

- 初期 `scale 0.05〜0.15` だと小さすぎて画面に映らない → 0.4〜1.0 に調整
- `scale 0.5〜1.5` だとカメラ至近距離で巨大な花びらが画面いっぱいに → 0.4〜1.0 に縮小
- Player の頭上 8m だと近すぎ、12m 前方 -3m だと遠すぎ → 真上 10m の中間で落ち着く

### 改善さんのフィードバック対応

「カメラ位置を変えられないので雲は影でしか見えない」→ 桜の花びらは Player を取り囲んで降るのでプレイヤー視点でも直接見える。固定カメラの制約を補う演出

次のステップ: Phase 1-5(湖の water シェーダー)で Phase 1 完了予定

## v0.6.0 — 2026-05-29 — Phase 1-2(空・昼夜)+ 1-4(雲)+ 星

- `scripts/world/sky_color.gd` 新規 — `class_name SkyColor`(+ preload 両対応)。時刻 t(0.0〜1.0)から `background(t)` / `ambient(t)` / `ambient_energy(t)` / `sun_color(t)` / `sun_energy(t)` / `sun_position(t)` / `fog_color(t)` を返す純粋関数 7 つ。Three.js プロトタイプの updateTimeOfDay を移植
- `scripts/world/day_night_cycle.gd` 新規 — `class_name DayNightCycle`。1 サイクル 84 秒で時刻を進め、毎フレーム WorldEnvironment(背景・環境光・fog 色)と DirectionalLight(位置・色・強度)を更新。`time_of_day` プロパティに setter を入れて外部から代入したら即反映
- `scripts/world/clouds.gd` + `scenes/world/Clouds.tscn` 新規 — 18 個の雲を seed 7 で固定配置、各雲は 6 個の SphereMesh の集合、UNSHADED マテリアル(時刻に依存しない常に白)。X 方向に水平移動 + 端でワープ
- `scripts/world/stars.gd` + `scenes/world/Stars.tscn` 新規 — 12 個の星を seed 42 で固定配置(地形高さ + 1.8〜2.3m)。夜のみ visible、ゆっくり自転、emission で発光(黄色 #ffe066)
- `scenes/Main.tscn` 修正 — `DayNightCycle` / `Clouds` / `Stars` ノード追加、Stars に DayNightCycle / Terrain への NodePath 接続、不要な Sky/Sky_material SubResource を削除
- `scripts/dev/auto_capture.gd` 拡張 — `MODE = FOUR_TIMES` で 1 回起動から朝(0.25)/昼(0.50)/夕(0.75)/夜(0.95)の 4 枚を順次撮影、`DayNightCycle.paused` を立ててから時刻を直接代入

### 修正したハマりポイント

- **`class_name` は Godot エディタが project をスキャンしないと CLI で認識されない**(SCRIPT ERROR: Identifier "SkyColor" not declared)→ `const SkyColor = preload("res://...")` を併用して両対応
- **昼の地形が白飛びする** → SUN/AMBIENT energy を下げて Three.js より控えめに(`DAY_SUN_ENERGY 0.9`、`DAY_AMBIENT_ENERGY 0.25`)。Phase 1-1 で経験した「Linear tonemap + 強ライト」と同じ症状の再発
- **夜の空が水色のまま**(背景は紫青なのに) → Godot の Environment は fog が遠景の空を上書きする。`SkyColor.fog_color(t) = SkyColor.background(t)` で fog 色も時刻同期させて解決

### Environment 設定の追加変更

- `WorldEnvironment.fog_light_color` を毎フレーム DayNightCycle が時刻に応じて上書き(夜=紫青、夕=オレンジ、昼=空色)

### UX メモ

- 改善さんから「カメラの位置を変えられないので雲はわかりませんが影は見えます」のフィードバック。三人称固定カメラ(CameraRig)では上空が視界に入りにくいため、雲の存在は地面に落ちる影で間接的に感じてもらう設計。本格的な「空を見上げる UI」は Phase 6 以降の検討事項

次のステップ: Web Export + push → Vercel デプロイ → Phase 1-5(水)/ 1-6(桜)へ

## v0.5.0 — 2026-05-29 — Phase 1-1 + 1-3(地形 + 線路)+ 自動スクリーンショット基盤

- `scripts/world/terrain_height.gd` 新規 — `class_name TerrainHeight` 純粋関数群。`compute_height(x, z)`(Three.js heightAt 移植、山 3+湖+二重正弦波+ノイズ)、`compute_vertex_color(h)`(雪山→草原→砂の高さマッピング)
- `scripts/world/terrain.gd` 新規 — ArrayMesh で 121×121 頂点の地形メッシュを動的生成(28800 三角形)、HeightMapShape3D 201×201 サンプルで衝突(scale で実世界 400×400 に展開)、湖 CylinderMesh 配置
- `scenes/world/Terrain.tscn` 新規 — StaticBody3D + TerrainMesh + TerrainCollision + LakeMesh の最小構成、生成はスクリプト
- `scripts/world/railway.gd` 新規 — 楕円(R_X=100, R_Z=78)を 157 点で表現、レール 2 本を 1 つの ArrayMesh に統合(円柱 8 角形断面を Path に押し出し)、枕木 MultiMeshInstance3D(157 個、地形高さに追従)。`static func ellipse_point(t)` / `ellipse_tangent(t)` で Phase 2 の Train から再利用可能に
- `scenes/world/Railway.tscn` 新規 — Node3D + TrackPath (Path3D) + Rails + Ties
- `scenes/Main.tscn` 修正 — 既存平面 Ground を削除、Terrain と Railway を追加、Sun の `directional_shadow_max_distance=100` に縮小(iPad パフォーマンス)
- `scripts/main.gd` 修正 — `_settle_player_on_terrain()` で Player の Y を `TerrainHeight.compute_height(px, pz) + 1.5` に動的補正(地形のくぼみに埋まる/高山スタート事故防止)
- **自動スクリーンショット基盤**: `scripts/dev/auto_capture.gd` + `scenes/dev/AutoCapture.tscn` 新規 — Godot CLI で起動すると 2 秒待ってスクリーンショットを `user://screenshot.png` に保存して終了。視点モードを PLAYER / BIRD / SIDE で切り替え可能。これにより Claude が改善さんに F5 を依頼しなくても見た目を自動確認できるようになった

### 修正したハマりポイント(failure-log 候補)

- **ArrayMesh の三角形インデックスは反時計回り(CCW)が表面**。最初に時計回り順で `(i0, i2, i1)` と書いて地形の平地が完全に消えていた(山の斜面だけ見えた)。`(i0, i1, i2)` `(i1, i3, i2)` に修正
- **WorldEnvironment のデフォルト Filmic tonemap + 強いライト + fog 0.004 で頂点カラーが淡くなりすぎる**。`tonemap_mode=0`(Linear)、`ambient_light_energy=0.3`、`fog_density=0.002` に調整して Three.js 版に近い鮮やかさを回復

### Environment 値の変更

- `ambient_light_energy`: 0.5 → 0.3
- `tonemap_mode`: 2 (Filmic) → 0 (Linear)
- `fog_density`: 0.004 → 0.002

次のステップ: 改善さんが Web Export(ファイル名 `index` を手動入力、Custom HTML Shell を確認)→ git push で Vercel 自動再デプロイ。PC ブラウザ確認後、Phase 1-2(空・昼夜)/ 1-4(雲)/ 1-5(水)/ 1-6(桜)へ。

## v0.4.0 — 2026-05-28 — Phase 0-6(Vercel デプロイ + 本番動作確認)

- `.gitignore` 修正 — `export/` → `export/*` + `!export/web/` に変更(Git の仕様でディレクトリ全体を ignore すると配下を `!` で例外指定できないため、`export/*` 表記に切り替え)。`export/web/` 以外の `export/*`(将来の iOS/Android Export 等)は引き続き除外
- `vercel.json` 修正 — `outputDirectory: "export/web"` を追加(Vercel UI で Output Directory を手動指定する手間を省くため。Project Settings UI を一切触らず Deploy ボタンだけで完結)
- `export/web/` 配下 12 ファイルを git 管理化(`index.html/js/wasm/pck`、audio worklet 2 種、アイコン 3 種、`.import` メタ 3 種)。`index.wasm` 35.7MB(GitHub 100MB 上限内、LFS 不要)
- GitHub Public リポジトリ作成: https://github.com/fanxingjudao-boop/shinkansen-world-godot (`gh repo create --public --source=. --remote=origin --push` で一発)
- 改善さんが Vercel にサインアップ(GitHub 連携、Hobby プラン)→ `shinkansen-world-godot` をインポート → Deploy。初回の Configure Project 画面では `vercel.json` の設定が効いたため Build/Output 設定は触らず
- Vercel が `https://shinkansen-world-godot.vercel.app/` を払い出し、ステータス Ready(緑)。COEP/COOP/CORP ヘッダーと `Content-Type: application/wasm` も `vercel.json` で適用済み
- 初回アクセスで改善さんが 404 NOT_FOUND を踏んだが、Claude Code 側から WebFetch で確認したところ Vercel は `index.html` を正常返却 → エッジ伝播遅延 or ブラウザキャッシュと判断 → シークレットウィンドウで再アクセスして動作確認 OK
- PC ブラウザ(Chrome)での動作確認完了 — ローディング → ゲーム画面、Player 表示、操作可能
- iPad Safari 実機確認は保留(改善さん判断、Phase 1 と並行でいつでも実施可能。URL は変わらず)
- 次のステップ: Phase 1(ワールド構築: 地形・線路・空・水・桜)に着手

## v0.3.0 — 2026-05-28 — Phase 0-5(Web Export ローカル動作確認)

- `web/template.html` を新規作成 — iPad 向け meta タグ、100dvh、パステル色のローディング画面、ひらがな表示
- `vercel.json` を新規作成 — COEP/COOP/CORP ヘッダー(Phase 0-6 のデプロイ用に先行準備)
- `export_presets.cfg` を新規作成 — Web プリセット(Threading: false、Custom HTML Shell 指定、Compatibility 想定)
- `Main.tscn` 修正 — `background_mode` を Sky(2) → Color(1) に変更し、空色 `#7ec8f5` を `background_color` に直接指定(Compatibility レンダラー + Web Export で ProceduralSky が描画されなかったため)
- `Main.tscn` 修正 — `ambient_light_source` を Sky(3) → Color(2) に変更、`ambient_light_energy` を 0.35 → 0.5 に
- `TouchHUD.tscn` 修正 — D-pad の ▲▼◀▶ ボタンの font_size を 32 → 40、「タッチ」を 22 → 28、「ジャンプ」を 20 → 26 に拡大(改善さんから「ボタン文字つぶれ」フィードバック)
- 改善さんが Godot 4.6 で Web Export Templates をダウンロード、Project > Export > Web → `export/web/index.html` に書き出し成功(初回は ファイル名が「しんかんせんワールド.*」になったため Claude Code がリネーム + HTML 内参照置換、2 回目は最初から `index` 指定で出力)
- ローカル HTTP サーバー(`python -m http.server`)で動作確認完了:操作可能・キャラ移動・ボタン入力すべて動作。背景空色とボタン文字も改善後の Export で適用済み
- 次のステップ: Phase 0-6(Vercel または GitHub Pages へのデプロイ)、その後 iPad 実機での動作確認

## v0.2.0 — 2026-05-27 — Phase 0 着手(0-1 〜 0-4)

- ルート直下の重複ドキュメントを削除(正本は `docs/` 配下に統一)
  - 削除: `ARCHITECTURE.md`, `CLAUDE-godot.md`, `GODOT_NOTES.md`, `ROADMAP-godot.md`
- `project.godot` を作成(Compatibility レンダラー、1920×1080 ビューポート、9.8 重力、空色クリアカラー `#7ec8f5`)
- `icon.svg` を新規作成(新幹線+空+太陽+雲のパステル可愛いアイコン、128×128)
- ディレクトリ構造を作成(`scenes/{entities,ui}/`、`scripts/{entities,world,ui}/`、`.gitkeep` で git 追跡)
- `scripts/main.gd`: InputMap を動的登録(WASD/矢印/Space/E/Enter)、エントリーポイント
- `scripts/entities/player.gd`: CharacterBody3D の移動・ジャンプ、ロジック層(`_compute_horizontal_velocity`, `_compute_yaw`)と Godot 操作層を分離(C# 移行配慮)
- `scripts/world/camera_rig.gd`: 三人称追従カメラ、Lerp で滑らか、ロジック層分離
- `scripts/ui/touch_hud.gd`: タッチボタン → InputMap action ブリッジ
- `scenes/entities/Player.tscn`: カプセル体 + 球頭 + 桜色の鼻、Group "player"
- `scenes/ui/TouchHUD.tscn`: 左下 D-pad(72px、空色)+ 右下ジャンプ(96px、桜色)/タッチ(96px、黄色)ボタン、StyleBoxFlat でパステル彩色、ダーク UI 不使用
- `scenes/Main.tscn`: ProceduralSky(空色〜)、太陽(DirectionalLight3D + 標準シャドウ)、120×120 草原(`#7ec850`)、Player インスタンス、CameraRig+Camera3D、UI レイヤー
- 次のステップ: Godot エディタで F5 実行して動作確認 → 改善さんに引き継ぎ → Phase 0-5(Web Export)

## v0.1.0 — 2026-05-27 — Godot 版への切り替え

- Three.js 版プロトタイプから Godot 4 版への移行を決定
- 引き継ぎ資料一式を整備(CLAUDE.md / HANDOFF.md / ARCHITECTURE.md / ROADMAP.md / GODOT_NOTES.md)
- Three.js プロトタイプを `reference/threejs-prototype/` に保管
- 次のステップ: Phase 0(Godot プロジェクト初期化)
