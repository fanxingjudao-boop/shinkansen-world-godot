# しんかんせんワールド — 現状仕様書(SPEC)

> **基準バージョン: v0.48.1(2026-06-03 時点)**

---

## 1. このドキュメントについて

これは、Godot 4 製の子供向け 3D Web ゲーム **「しんかんせんワールド」** の **現状仕様(as-is)** を 1 枚にまとめた総括ドキュメントです。時系列の差分は `changelog.md`、設計の詳細は `docs/ARCHITECTURE.md`、開発経緯と既知の課題は `docs/HANDOFF.md`、今後の計画は `docs/ROADMAP.md` に分かれていますが、**「今このゲームがどういうものか」を全体として把握する**ための単一ソースがありませんでした。本書がそれにあたります。

- **想定読み手**: このプロジェクトのコードに直接アクセスできない人や AI(Claude.ai 等)。レビュー・改善提案・相談に使えるよう、前提を補って自己完結的に書いています。
- **記載範囲**: 主に現状の実装仕様。今後の方向性は §12 に概要のみ。
- **正確性**: コードと既存ドキュメントで確認できた事実・数値のみを記載しています。

---

## 2. プロジェクト概要

### 何のゲームか
新幹線をはじめとする電車が走る、やさしいオープンワールドを散歩するゲームです。子供が世界を歩き回り、星を集め、動物と仲良くなり、電車に乗り、駅を見つけ、図鑑を埋めていきます。さらに、ロケット・飛行機・潜水艦・特別な乗り物で **6 つの別世界**(月・空の城・海底・お菓子・恐竜・雪)へワープして遊べます。

### ターゲットユーザー
**3〜7 歳児**(幼稚園〜小学校低学年)。身内のお子さん・お孫さんが iPad で遊ぶことを主目的にしていますが、「身内向けだから」と手を抜かず、子供にとって最高の体験を目指す創作プロジェクトです。

### 設計哲学(厳守事項)
- **失敗概念がない**: HP・スコア・タイマー・ゲームオーバー・敵キャラ・ダメージ表現は一切なし。
- **怖くない**: 暗すぎる夜・不気味な音・急に出てくるもの・ジャンプスケアを避ける。恐竜も草食のやさしい種だけ。
- **読める**: ひらがな・カタカナのみ。漢字は使わない。
- **押せる**: タッチターゲットは最小 48×48px、推奨 64×64px。
- **わかる**: 何をすればよいか常に明示(ミッション通知など)。
- **やさしい音**: 大きすぎる音・不快な周波数を避ける。
- **公平**: ランダム要素は必ず良い結果に寄せる。
- **達成感**: 「やったね!」の瞬間をできるだけ多く作る。

---

## 3. 技術スタック / 全体構成

| 項目 | 内容 |
|---|---|
| エンジン | **Godot 4.6**(最新安定版) |
| 言語 | **GDScript**(C# ではない) |
| レンダラー | **Compatibility**(`gl_compatibility`、WebGL2 準拠) |
| 配信形態 | **Web Export(PWA)**。将来 iOS ネイティブ展開も視野 |
| ホスティング | **Vercel**(Hobby + GitHub 連携で自動再デプロイ) |
| 開発環境 | Windows 11 のみ(Mac 不要) |
| バージョン管理 | Git + GitHub(Public リポジトリ) |
| 基準解像度 | 1024×576(viewport stretch / expand) |
| 本番 URL | https://shinkansen-world-godot.vercel.app/ |
| リポジトリ | https://github.com/fanxingjudao-boop/shinkansen-world-godot |

### 主要な技術選定の根拠(要約)
- **GDScript を採用**: C# の Web Export は実験的扱いでビルドサイズが大きく(30〜80MB)iPad Safari でのロードが現実的でない。GDScript は軽量で、開発者の Python ベースのスキルと親和的。
- **Compatibility レンダラー**: Web Export で必須。SDFGI / Volumetric Fog / SSAO / SSR は使えない。そのため**写実性ではなく「光る・はじける・ふわふわする」表現**(シェーダーとマテリアル設計)で作り込む方針。PBR マテリアル・カスタムシェーダー・GPUParticles3D・Glow(部分)は使用可。

---

## 4. アーキテクチャ概要

### エントリーポイントとシーン構成
メインシーンは `res://scenes/Main.tscn`(スクリプト `scripts/main.gd`)。**Autoload(シングルトン)は使わず、各システムを `Main` 直下のノードとして配置**する方針です(C# 移行を見据え、ロジックをエンジン操作から分離する設計判断)。

`Main` 直下の主な構成:
- **システム系ノード**: `GameState` / `SaveSystem` / `Bgm` / `MissionManager` / `SoundFX` / `DayNightCycle` / `RewardManager` / `RideController` / `CameraRig`
- **ワールド系**: `WorldEnvironment`(Fog/Glow/Ambient)、`Sun`(DirectionalLight3D・影あり)、`Terrain` / `Railway` / `Town` / `Grass` / `Clouds` / `Stars` / `Rainbow`
- **乗り物・キャラ**: `Trains`(11 編成)、`Stations`(6 駅)、`Animals`(8 種)、`Player`
- **別世界系**: `MoonTrip` / `SkyCastle` / `Submarine` / `CandyLand` / `DinoLand` / `YukiLand` / `Castle` / `Landmarks`
- **UI 系(CanvasLayer)**: `TouchHUD` / `TitleScreen` / `BookOverlay`(図鑑)/ `WorldSelect`(おでかけメニュー)

### 通信方式
`GameState` の `signal changed` を中心とした **Signal ベースの疎結合**。値が変わるたびに `changed` が発火し、HUD カウンター・ミッション・報酬システム・図鑑が反応します。

### スクリプト配置
```
scripts/
├── main.gd                 # 入力マップ登録・シーン管理
├── entities/               # player, train, animal, train_data, animal_data
├── world/                  # terrain, railway, route_data, camera_rig,
│                           # day_night_cycle, game_state, save_system,
│                           # ride_controller, *_manager, reward_manager,
│                           # moon_trip, sky_castle, submarine, candy_land,
│                           # dino_land, yuki_land, castle, grass, town ...
├── ui/                     # touch_hud, title, book, settings, world_select
├── fx/                     # fireflies, shooting_star
└── dev/                    # auto_capture(検証用スクリーンショット)
```

### データ駆動
電車・動物・駅は `.tres` リソース(`resources/train_data/`, `animal_data/`, `station_data/`)で定義され、対応する `*_data.gd` がスキーマを持ちます。図鑑のマスターはこれらの `.tres` を走査して生成されます。

---

## 5. ゲームプレイ仕様(中核)

### 5.1 メインワールド(地上)
- **地形**: `terrain.gd`。`WORLD_SIZE 700` の広域、`MESH_SUBDIV 180` で起伏を表現。湖もある。
- **線路網**: `railway.gd` + `route_data.gd`。**9 ルートの閉ループ**を編成ごとに割り当て、曲線を共有しないため速度差があっても衝突・数珠つなぎが構造的に起きない。交差は高さ(高架)で分離。
- **駅**: 6 駅。近接(約 26m)で自動アナウンス、駅メロ、看板表示。
- **動物**: 8 種。3m 以内に近づくと**自動でなかよし成立**(タッチ不要)。なかよしの子は歌い、ときどき星をくれる。
- **星・町・踏切**: 近接で星を獲得。町(`town.gd`)には街・駅前広場・街路樹・踏切(遮断機の開閉・警報音・点滅)。
- **昼夜サイクル**: `day_night_cycle.gd`。約 840 秒で 1 日(実機で速すぎたため 84→840 秒に調整)。夜も「怖くない明るさ」を保つ。
- **その他演出**: 流れ星(夜)、ホタル(夜・Player の子)、虹、桜(地上のみ)。

### 5.2 6 つの別世界(ワープ)
すべて「地上に乗り物がある → 近づくと専用ボタン → フェード → 別座標へワープ」という共通骨格で、各世界に「おうちへ かえる」が常時表示されます。地上の **おでかけメニュー(§5.5)** からは 1 タップで直接ワープも可能です。

| 世界 | 乗り物 | 移動方式 | 収集物 | 主な登場要素 |
|---|---|---|---|---|
| **つき(月)** | ロケット / 月面カー | 球面歩行(裏側まで歩ける小惑星)・低重力 0.42 | ─(三色だんごで げんき) | クレーター・回る地球・星・UFO・もちつきうさぎ・月面カー(乗ると速度1.8倍) |
| **そらの おしろ** | ひこうき | 自動上昇飛行 → 雲の島を歩行・低重力 0.4 | ほし 7 個 | 雲の島・お城・虹の橋・上空を旋回する装飾新幹線。落下防止の見えない壁+自動復帰 |
| **うみの そこ** | せんすいかん | 自動巡航(上下に波打つコース) | しんじゅ 5 個 | 魚 6 群れ計 48 匹・サンゴ・海藻・岩・宝箱・クジラ・カメ・泡 |
| **おかしの くに** | おかしの きしゃ | **歩行**(物理ON・落下防止の床+壁) | ほし 5 個 / お菓子で げんき | クッキーの家・ロリポップ・キャンディケーン・わたあめ雲・ゼリーの川・グミのくま |
| **きょうりゅうランド** | サファリカー | 自動巡航 | たまご 5 個(かえると赤ちゃん恐竜+ほし) | 草食恐竜のみ(サウロポド・トリケラ・ステゴ・赤ちゃん・プテラノドン)・ジャングル |
| **ゆきの くに** | そり | 自動巡航(半径 28m のループ) | クリスタル 5 個 | 雪原・もみの木・雪だるま・ペンギン・うさぎ・かまくら・温泉(湯けむり)・オーロラ・降る雪 |

**実装メモ**: 各別世界は対応する `scripts/world/*.gd`(`moon_trip.gd` 等)で、初回ワープ時に遅延ビルド。env(fog/ambient)は各世界用に退避→復元します。各世界は公開 API `warp_in()` / `is_active()` を持ち、おでかけメニューから呼べます。

### 5.3 乗り物・操作体系
- **移動**: D-pad(4 方向)+ WASD / 矢印キー。**カメラ基準移動**(画面の奥が常に「前」)で幼児にも直感的。ジョイスティックは「距離」が難しいため不採用。
- **カメラ**: `camera_rig.gd`。固定追従(orbit は酔うため撤去)。左右ボタンで 45°ずつ滑らかに回転。
- **電車の乗降**(`ride_controller.gd`): 近接(14m 以内)で「◯◯に のる?」→ タッチで乗車。視点は「やね / うんてんせき / まどぎわ」の 3 種を「ながめ」ボタンで切替。
- **運転手モード**: 「うんてん」ボタンで ON。「ゴー / とまれ」で加減速、分岐点で「のりかえ / まっすぐ」の 2 択。自分で減速して駅にぴったり止めると「ぴったり とうちゃく!」+ 星 +1。
- **自動巡航**(海・恐竜・雪): `player.set_physics_process(false)` + `gravity_scale=0` で乗り物をプレイヤーに装着し、waypoint を一定速度で周回。**カメラは位置のみ追従(向きには影響されない)= 酔わない設計**。
- **球面歩行**(月): `player.gd` の `planet_mode` で重力を球中心へ向け、`up_direction` を球面法線に。裏側まで歩ける。

### 5.4 収集・報酬システム
3 種の収集要素があり、いずれも `reward_manager.gd` / `animal_manager.gd` が報酬(payoff)を与えます。**報酬は `energy` / `star_count` から都度計算するため、セーブ項目は増えません。**

| 要素 | 入手 | 報酬(payoff) |
|---|---|---|
| **げんき** | お菓子・だんご等を食べる | 移動速度アップ。`ENERGY_STEP=0.03`(1 個 +3%)、上限 `ENERGY_MAX_BONUS=0.5`(+50%=1.5 倍)。永続(`energy` はセーブ済) |
| **ほし** | 別世界で拾う / なかよし動物がくれる | **5 個ごと**(`MILESTONE=5`)にお祝い通知+キラキラ+音。スポーン前方 `(6,-14)` の「ほしのき」の実(`FRUIT_COUNT=20`)が集めた数だけ金色に点灯(トロフィー) |
| **なかよし** | 動物に 3m 以内で自動成立 | 図鑑記録。なかよしの子が 12〜20 秒ごとに近くで星をくれる(`animal_manager.gd`) |

> お祝いの起動時誤発火を防ぐため、`reward_manager` は読込済みの星数を `_last_milestone` に初期化し、ロード分は祝いません。

### 5.5 UI
- **TouchHUD**(`touch_hud.gd` + `TouchHUD.tscn`): D-pad、ジャンプ、乗降(タッチ/おりる)、ながめ、うんてん、ゴー/とまれ、分岐 2 択、カメラ左右、図鑑(本)、メニュー、おとな(親モード)、各別世界ボタン。通知(Notice)・プロンプト(Prompt)・フェードもここ。ボタン押下で「ぷにっ」と縮む演出。
- **おでかけメニュー**(`world_select.gd` / `WorldSelect.tscn`、v0.47.0): 桃色の「どこへ いく?」ボタン → 6 つの絵カード(つき/そら/うみ/おかし/きょうりゅう/ゆき)→ タップで即ワープ。**地上 + 非乗車時のみ表示**。
- **図鑑**(`book.gd` / `BookOverlay.tscn`): でんしゃ / どうぶつ / えき の 3 ページ。発見状況を表示。`.tres` 走査でマスター化。
- **親モード**(`settings.gd` / `Settings.tscn`、v0.36.0): 「おとな」ボタン → 数字ゲート → 音 ON/OFF・あそんだ かいすう表示・データ削除。

### 5.6 ミッション(`mission_manager.gd`)
13 個のミッションを順次クリアしていく方式。**失敗概念はなく**、達成すると「クリア!」+「つぎは:◯◯」を通知。タイトルの「はじめる」押下時に現在ミッションを案内します。内容は「でんしゃに のる」「どうぶつと なかよし」「ほしを 3こ/9こ」「えきを みつける」「うんてんしゅに」「おしろ電車」と、6 つの別世界それぞれへの誘導です。

---

## 6. データ資産(`resources/`)

| 種別 | 数 | スラッグ例 |
|---|---|---|
| 電車(`train_data/`) | 11 編成 | hayabusa, komachi, kagayaki, n700, doctor_yellow, tsubasa, tsubame, sl_hitoyoshi, e235_yamanote, **oshiro**, **sora** |
| 動物(`animal_data/`) | 8 種 | usagi, kuma, kitsune, neko, panda, inu, penguin, buta |
| 駅(`station_data/`) | 6 駅 | midori, hana, mizuumi, yama, okashi, niji |

`oshiro`(お城電車・乗車可)と `sora`(空電車・装飾)はこのゲームのオリジナル。3D モデルは外部ファイルではなく**スクリプトでプログラム生成**しています。

---

## 7. 演出・音・シェーダー

- **シェーダー**(`assets/shaders/`): `rim.gdshader`(リムライト + トゥーンの `light()` ステップ)、`grass.gdshader`(草の揺れ・X 字クロスメッシュ)、`water.gdshader`(水面)。
- **パーティクル**(GPUParticles3D): キラキラ獲得バースト、雪、湯けむり、海底の泡、桜(地上)。
- **草**(`grass.gd`): X 字クロスメッシュを MultiMesh で 1 draw call、半径 170m に約 4200 株(v0.42.0)。
- **音**(`sound_fx.gd` / `bgm.gd`): すべて**プログラム生成**(`AudioStreamWAV`、正弦波・三角波中心)。きらきら音・エンジン音(ループ)・駅メロ・チャイム・警報音など。BGM はプロシージャルなループ。大きな音・不気味な音は避ける(警笛も -16dB)。
- **描画最適化**(v0.43.0): 電車のマテリアルを色キーで static 共有キャッシュ化、窓を MultiMesh 化(draw call 約 1200 から大幅削減)。車輪回転はカメラ 110m 以内のみ。

---

## 8. セーブ仕様(`save_system.gd`)

`user://save.json`(Web では IndexedDB に永続化)に **数値と識別子(slug)のみ**を保存。プレイヤー位置・向き・時刻・電車の進捗などの一時状態は保存しません。

保存する項目:
```json
{
  "star_count": 0,
  "boarded":    [],   // 乗車済み電車の slug
  "befriended": [],   // なかよし動物の slug
  "stations":   [],   // 訪問済み駅の slug
  "energy":     0,
  "moon": false, "sky_castle": false, "submarine": false,
  "candy": false, "dino": false, "yuki": false,
  "drove": false,
  "play_count": 0
}
```
読込時は `changed` を発火させず値だけセット(各 listener は自身の `_ready` で現在値を反映)。起動ごとに `play_count` を +1 して保存します。

---

## 9. 子供向け配慮 & セキュリティ原則(例外なく厳守)

子供が遊ぶ Web 配信物として、子供への配慮と同格で以下を厳守しています。

- **個人情報を一切収集・保存しない**(セーブは §8 の数値・slug のみ)。
- **外部広告・アナリティクス・トラッキングを導入しない**。
- **外部リンク・SNS 連携・テキスト入力欄を作らない**(`LineEdit`/`TextEdit`/`OS.shell_open`/`HTTPRequest` 不使用)。
- **外部リソースへの通信を発生させない**(フォントは CDN ではなくプロジェクト同梱)。完全オフライン動作。
- **セキュリティヘッダーを維持**(`vercel.json`、§10)。
- **検索エンジンに載せない**(`robots.txt` の `Disallow: /` + `noindex` + `X-Robots-Tag`)。
- 新機能で「入力欄/外部通信/外部リンク/個人データ/トラッキング」が必要になったら実装前に確認(原則は不要)。

UX 面: 失敗・タイマー・敵なし、漢字なし、ダーク UI なし、落下しても自動復帰、自動運転は判断負担なし・低速で酔わない。

---

## 10. Web Export / 配信

- **Export 設定**(`export_presets.cfg`): プリセット "Web"、出力 `export/web/index.html`、カスタム HTML シェル `res://web/template.html`、`vram_texture_compression/for_mobile=false`(**`true` だと Web export が失敗する**ので必ず維持)、Emscripten 8 スレッド / Godot 4 スレッド。
- **セキュリティヘッダー**(`vercel.json`): COEP(`require-corp`)/ COOP(`same-origin`)/ CORP / X-Frame-Options(`DENY`)/ X-Content-Type-Options(`nosniff`)/ Referrer-Policy(`no-referrer`)/ Permissions-Policy(カメラ・マイク等すべて無効、autoplay/fullscreen は self のみ)/ **CSP**(`script-src` に `'wasm-unsafe-eval' 'unsafe-inline'`、`worker-src blob:`、`object-src 'none'` 等、Godot Web が動く最小範囲)。
- **HTML テンプレート**(`web/template.html`): `lang="ja"`、`noindex,nofollow`、背景/テーマカラー `#7ec8f5`、M PLUS Rounded 1c、`100dvh` 対応、日本語ローディング表示。
- **PWA**(`manifest.json`): フルスクリーン・横向き固定・apple-touch-icon。AudioContext はタイトルの「はじめる」押下で初期化(iOS の制約)。
- **配信フロー**: CLI `Godot --headless --export-release "Web" export/web/index.html` で再エクスポート → 検証 → `export/web/index.{html,pck}` を明示パスでコミット → push → Vercel 自動デプロイ。

---

## 11. 既知の制約・実機確認待ち事項

### 技術的制約
- **Compatibility レンダラー**: SDFGI / Volumetric Fog / SSAO / SSR 使用不可。
- **iPad 実機デバッグ困難**: Windows のみの環境で Safari 開発者ツールが使えない。PC ブラウザ(Chrome/Firefox)で確認し、iPad は最終確認用。
- **初回ロード 15〜25MB**: Service Worker キャッシュで 2 回目以降は瞬時。
- **エディタ起動で `export_presets.cfg` の `for_mobile` が `true` に書き換わることがある** → export 前に要確認・復元。
- **パフォーマンス目標**: iPad mini(旧世代)で 30fps。

### v0.48.1 時点の実機確認待ち(改善さんのチェック項目)
1. 各ワールドの fps(草 4200 株・魚 48 匹・雪粒・列車最適化済)
2. 酔い(自動巡航・惑星カメラ)
3. 音量バランス
4. げんきの速度アップが速すぎないか
5. ごほうび(ほしのき・プレゼント)の頻度・嬉しさ
6. ゆきの くにの明るさ(v0.48.1 で軽減済)

> **調整ポイント**: 速度上限=`reward_manager.gd` の `ENERGY_MAX_BONUS` / 係数 `ENERGY_STEP`、ほしのき位置=`STAR_TREE_POS`、ギフト間隔=`animal_manager.gd` の `GIFT_INTERVAL_*`、各世界の巡航=各 `*_land.gd` / `submarine.gd` の `CRUISE_R/CRUISE_Y/CRUISE_SPEED`。

---

## 12. 現在地と今後の方向性(概要)

開発は **ROADMAP の Phase 6「体験を深める」を進行中**です。Phase 0〜5(ワールド構築・列車システム・駅/動物/星/図鑑/ミッション・美的演出・PWA 化/配信)は完了。Phase 6 で別世界ワープ・運転手モード・ごほうび・おでかけメニューが実装され、現在は **改善さんの iPad 実機確認待ち**の段階です。

今後の候補(詳細は `docs/ROADMAP.md`):
- 駅前のお店(お団子・お花・おみやげ交換)
- ミニクエスト / 季節モード(桜が散る・紅葉する等)/ 隠し電車 / 撮影強化 / アクセシビリティ
- 自由枠: 動物との会話、お花摘み、季節通知、電車から手を振ると沿線が応える、など

---

*この仕様書は v0.48.1 時点の現状を反映しています。実装が進んだら本書も更新してください。*
