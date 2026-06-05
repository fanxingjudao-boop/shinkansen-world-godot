# HANDOFF — 引き継ぎ資料(Godot 版)

このドキュメントは Three.js 版から Godot 4 版への移行の経緯、設計判断、既知の課題を Claude Code に引き継ぎます。

## 経緯

1. 改善さんから「3D オープンワールドゲームのデモ操作画面を作って」というお題
2. Claude.ai 上で Three.js を使ったサイバーパンク風プロトタイプを作成
3. スマホ・iPad で動作問題が発生 → CDN フォールバック等で対応
4. 「子供向けに作り変えて」の指示で電車・新幹線ワールドにピボット
5. 「左右が反対」「もっと本気」のフィードバックで大幅拡張
6. iPad での PWA 配信を目指して Claude Code に引き継ぎ
7. **改善さんが本格的に作り直すことを決意 → Godot 4 で再構築**
8. 言語・配信・グラフィック品質の選択について議論
9. 最終決定: **GDScript + Web Export(PWA)+ 中間品質グラフィック**

## 重要な設計判断と根拠

### なぜ Godot 4 を選んだか

- **完全無料、商用利用も無料**(MIT ライセンス、ロイヤリティなし)
- **GDScript が Python 似で改善さんに馴染みやすい**
- **エディタが軽量**(80MB)、Unity に比べて起動・ビルドが速い
- **Web Export が標準機能**(PWA 化が自然)
- **長期運用に向く**(オープンソース、開発元の方針変更リスク低)
- **将来 iOS ネイティブ化も可能**(Mac 環境が整えば)

代替案として Unity、Babylon.js、Unreal Engine 5 も検討しましたが、改善さんのソロ開発スタイル(Python ベース、Windows、複数プロジェクト並行)に最も合うのが Godot でした。

### なぜ C# でなく GDScript か

当初 C# が選ばれましたが、以下の問題で GDScript に変更:

1. **C# の Web Export は実験的扱い**(Godot 公式が明言)
2. **C# Web ビルドのサイズが大きい**(GDScript の数倍、30〜80MB)
3. **iPad Safari でのロード時間が長くなる**
4. **改善さんの Python ベーススキルセットには GDScript が親和的**
5. **将来 Unity 移植時のコストは、言語より設計で決まる**

「将来 Unity 併用」考慮は、**ロジックを Godot 操作から分離する設計**で代替します。詳細は `ARCHITECTURE.md` の「C# 移行への配慮」セクション。

### なぜ Web Export(PWA)主体か

- **改善さんが Windows のみ環境**で iOS ネイティブビルド不可(Mac + Xcode が必須)
- **PWA はインストール不要で配布が楽**(URL を送るだけ)
- **HTTPS と最低限のメタタグでアプリ風に起動可能**
- **Service Worker でオフライン動作も可能**
- 将来 Mac 環境が整えば iOS ネイティブ化への移行コストは低い

### なぜ中間品質グラフィックか

当初「ガッチリ作り込み(PBR、ポストエフェクト、SDFGI 等)」が希望されましたが、以下の制約で中間品質に調整:

1. **Web Export では Compatibility レンダラー必須**
2. Compatibility レンダラーは SDFGI、Volumetric Fog、SSAO、SSR 等が**使えない**
3. 子供向けかわいい世界では写実性より「光って、はじけて、ふわふわ」が重要
4. PBR マテリアル、カスタムシェーダー、GPUParticles3D、Glow(部分)は使える

つまり**ポストエフェクトに頼らず、シェーダーとマテリアル設計で「リッチ感」を出す**戦略です。

### なぜ Three.js プロトタイプを残すか

`reference/threejs-prototype/index.html` として保管しています。理由:

- **実証された UI レイアウトの参考**(ボタン配置、HUD 構成)
- **演出・色彩の方向性**(配色、モーションの感覚)
- **「楽しさ」のリファレンス**(子供向けゲームとして何が刺さるか)
- **改善さんの思考の記録**(後から「あの時の判断はなぜ?」を振り返れる)

ただし**コードを直接コピペする意味はありません**(言語もエンジンも全く違うので)。

## Three.js 版から引き継ぐ知見

### UX 設計

- **D-pad が幼児に最適**: ジョイスティックは「方向と距離」が難しい、ボタンは「押せば動く」が直感的
- **HP・スコア・タイマー禁止**: 失敗概念がない方が幼児は楽しめる
- **漢字は使わない**: 3〜7 歳児はほぼ読めない
- **ダーク UI 不可**: 怖いと感じる子がいる、明るい色彩を徹底
- **タッチターゲットは大きく**: 48×48px 最小、64×64px 以上推奨

### 技術的教訓

- **CDN 依存は罠**: Three.js 版で 3 段フォールバックを実装したが、Godot は Web Export でファイル同梱されるので不要
- **左右の座標系**: Three.js で yaw 計算のバグがあった。Godot の `Camera3D` は標準的なので問題なし
- **iOS の AudioContext**: ユーザー操作後でないと初期化できない、これは Godot でも同様
- **CapsuleGeometry の互換性問題**: Three.js 限定の話、Godot では関係なし

### 演出の方向性

- **配色**: パステル基調(空色 `#7ec8f5`・草原緑 `#7ec850`・桜色 `#ff9ec0`・黄色 `#ffe066`・オレンジ `#ffa94d`)
- **モーション**: バネ感のあるイージング(`ease_out_back` 等)
- **音**: 優しい正弦波・三角波(BGM もこの方向で)
- **エフェクト**: キラキラ・ふわふわ・ぴょんぴょん

## 既知の課題

### 1. 学習コスト

改善さんも Claude Code も Godot 4 の経験は限定的。
- 公式ドキュメントとチュートリアルで基礎を学ぶ
- 最初は小さなシーンから(Phase 0 の「キャラが歩く」レベル)
- Phase 1 までで Godot の感覚を掴む

### 2. iPad 実機デバッグの困難さ

Windows のみの開発環境では Safari の開発者ツールが使えない:
- ゲーム内にデバッグログ表示機能を組み込む
- Web 版の動作は PC のブラウザ(Chrome/Firefox)で確認
- iPad 実機は最終確認用

### 3. パフォーマンスの未知数

Web Export のパフォーマンスは実装次第で大きく変わる:
- iPad mini(古い世代)で 30fps を目標
- MultiMeshInstance3D、テクスチャ最適化、シャドウサイズ等で調整

### 4. ファイルサイズ

Godot の Web Export は初回 15〜25MB:
- Service Worker キャッシュで 2 回目以降は瞬時
- ローディング画面で待ち時間を演出

### 5. デプロイ先

GitHub Pages は COEP/COOP ヘッダーが設定不可。
- Vercel が第一候補(`vercel.json` で設定可能)
- 改善さんの好みで選択

## ファイル構造

```
shinkansen-world-godot/
├── project.godot              # Godot プロジェクト設定(Phase 0 で作成)
├── CLAUDE.md                  # Claude Code 作業指示書
├── README.md
├── changelog.md               # verification-agent 用変更履歴
├── .gitignore
├── docs/
│   ├── ARCHITECTURE.md
│   ├── HANDOFF.md             # 本ファイル
│   ├── ROADMAP.md
│   └── GODOT_NOTES.md
├── reference/
│   └── threejs-prototype/
│       └── index.html         # Claude.ai 版プロトタイプ
├── scenes/                    # Phase 0 以降で作成
├── scripts/
├── resources/
├── assets/
└── export/                    # ビルド出力(.gitignore)
```

## 引き継ぎ完了条件

Claude Code に以下を渡せれば引き継ぎ完了:
1. このフォルダ一式(`docs/`、`reference/`、各種ドキュメント)
2. 改善さんが GitHub に新規リポジトリ作成、`git push`
3. Claude Code に「`CLAUDE.md` を読んで、`docs/ROADMAP.md` の Phase 0 から始めてください」と指示
4. Claude Code は verification-agent LIGHT モードで作業、changelog.md に履歴記録

## 進捗(2026-06-06 — v0.53 B-7 / v0.54 銀河鉄道 / v0.55 本格線路・踏切・道路・各地分岐 / v0.56 ミニマップ・踏切修正)

### ▶ 現在地(次セッションはここから)

- **ブランチ**: `main`(作業は main 直接)。
- **コミット状況**: 本番 `origin/main` は **v0.56.0(ミニマップ)+その Web 再エクスポートまで push 済(ライブ=v0.56.0)**。**未 push が 3 つ**: `507884f`(v0.56.1 踏切バグ修正+各地分岐に doctor_yellow/tsubame 追加)→ `db4ddb8`(不具合調査・ミニマップの乗車中ガード整理)→ 本コミット(引き継ぎ更新+`minimap.gd.uid`)。⚠️ **v0.56.1 でソース(crossing/route_data)が変わったので export/web は v0.56.0 のまま。ライブを v0.56.1 にするには `! git push origin main` 後に Web 再エクスポートをやり直すこと**(手順は下記)。
  - **v0.56.1(踏切バグ修正+電車が自由に行き来)**: 踏切「電車が通る前に閉まる」を修正(`crossing.gd`=`get_route_slug()` で実トラックの編成を追い、弧長 `CLOSE_AHEAD=16`/`PASS_CLEAR=7` で判定)。各地分岐に doctor_yellow・tsubame を追加し 全地上ルート到達可能に。**踏切の開閉タイミングは実機体感確認推奨**。
  - **不具合調査済み(2026-06-06)**: 実行時エラー一斉チェック + 2観点コードレビュー(電車/分岐/踏切・別世界/ミニマップ/道路)→ **重大な不具合なし**。`AUTO_WORLDSEL` 終了時の ObjectDB leak 警告のみ(終了時の解放漏れ・実害なし)。
  - **v0.55.0 = 本格線路+踏切+道路+電車で各地へ**(改善さんリクエスト「電車を各地へ/本格踏切/街をつなぐ道路/本格線路」):
    - **本格線路**(`railway.gd`): 砂利バラスト道床(`_build_ballast_for`)+枕木を密に(`TIE_SPACING=1.8`)+鋼レール。
    - **踏切 3→8**(`town.gd CROSSINGS`、`crossing.gd` は既存本格版)。
    - **街をつなぐ道路**(`town.gd _build_roads/_road_ribbon`、メイン↔集落3本・帯メッシュ+白線)。
    - **電車で各地へ**(`route_data.gd branches()`+`ride_controller.gd`): 本線はやぶさをハブに みずうみ/やま/まち/おしろ/まちのまんなか への往復分岐(フェードで載せ替え=離れたルートOK・編成入れ替えで1ルート1編成維持。`label`=地名表示)。`AUTO_FIXCHECK` で重複なし確認。
    - **要実機調整**: 各地分岐の運転体験(2択の出る場所・酔い)・枕木密度(性能)・道路の通り道・踏切位置。
  - **v0.56.0 = ミニマップ**(`scripts/ui/minimap.gd`・`_spawn_extra`): 右上に小さく半透明の地図(主人公=矢印・湖/山/街/城)。別世界/乗車/モーダル中は隠す。`_spawn_extra` を任意 Node 対応に変更(CanvasLayer 用)。調整候補: `MAP_SIZE/MAP_RANGE`/位置/色。
  - **📄 docs/GAME_OVERVIEW.html**: 現在の機能・あそびのフロー・専門用語かみ砕き・ファイル地図を 1枚の HTML にまとめた(ブラウザで開く)。
  - **v0.54.0 = 第9の目玉 銀河鉄道** + **v0.54.1 = 星々を渡り歩く旅路に作り替え**: 星空を夢の汽車で自動巡航する別世界。新規 `scripts/world/ginga_railway.gd`(`_spawn_extra`・`Main.tscn`/`TouchHUD.tscn` 不変・HUDボタンも実行時生成)。`game_state.visited_ginga`+save "ginga"+mission+おでかけメニュー7枚目。**v0.54.1**: 巡航を「星々を渡る長い旅路」に(`_build_journey`/`GALAXY_R=95`/`STAR_WAVE_Y=22`/速度9.0)。**v0.54.2**: 止まり先を **6つの世界のミニチュア**(そら/ゆき/おかし/つき/きょうりゅう/うみ・浮かぶ島+ひらがなラベル)+大きな星6 に。各 `_build_stop_*` で生成(本物のワールドは不変)。**調整候補**: ミニチュアの見え方/大きさ/並び・旅の長さ/速度/うねり(酔い)・星空の明るさ・メニュー7枚目が画面下に近い(パネル高さ)。`AUTO_GINGA`/`AUTO_WORLDSEL` で確認済。
  - **v0.53.0 = B-7 かくれた でんしゃ(夜のレア車両)**: 夜だけ にじいろ「ゆめ」しんかんせんが専用ルート出現。新規 `scripts/world/rare_train.gd`(`_spawn_extra`)+ `route_data.gd` "yume" ルート + `resources/train_data/yume.tres`。図鑑は .tres 自動で「?」隠し枠。発見=乗車(`boarded_trains` 流用=セーブ増やさない)。**調整候補**: "yume" ルート位置/大きさ・色。`AUTO_RARE` で出現確認済。
  - このセッションの実装: v0.51.0 A-5乗客 → v0.51.1 腕削除 → v0.51.2 全機能監査+月・空の戻る常時表示 → v0.52.0 B-5楽器 → Web再エクスポート → **v0.53.0 B-7レア車両**。
- **Web 再エクスポート: ライブは v0.56.0 まで(push済)。⚠️ v0.56.1 は未エクスポート**。手順: `! git push origin main` → `Godot --headless --export-release "Web" export/web/index.html` → 検証(`export_presets.cfg` 非破壊・`index.*` 日本語化なし・noindex/robots 維持)→ `git add -u export/web` → commit(差分は実質 `index.html`+`index.pck` のみ)→ push。push 後ライブで ①起動 ②文字 ③外部通信なし を確認(CLAUDE.md)。**push はこの環境でブロック → 改善さんが `! git push origin main`**。
- **🎯 次セッションの最重要 = 改善さんの実機/ブラウザ体感確認**(v0.50.0〜v0.56.1 の新要素。特に **踏切の開閉タイミング・各地分岐の運転体験・ミニマップの見やすさ**)。新規実装を続けるなら候補は `docs/PLAYFUL_DETAILS.md` の **A-2 動物のしぐさ / C-3 季節と天気** ほか(いずれも `_spawn_extra` 寄生方式で追加可)。
  - **v0.52.0 = B-5 楽器(押すと音)**: 新規 `scripts/world/instruments.gd`(`_spawn_extra` で生成)。**もっきん**(ドレミ8鍵盤・各鍵盤タップでその音・自分でメロディが弾ける・低音ほど長い木琴風)+ **ラッパ**(タップでファンファーレ)。B-2(`interactables.gd`)の物理ピッキング+sound_fx の作法を流用。音量ひかえめ・Master バスのミュート連動。`AUTO_MUSIC`(新規)でスクショ確認済。**置き場所** `XYLO_POS`(12,8)/`TRUMPET_POS`(4,-12) は実機で他構造物と重なれば調整。
  - **v0.51.2(全機能監査+月・空の戻るボタン常時表示)**: 全機能を3観点で点検。実在した不足は「つき/そら の戻るボタンが乗り物近接でしか出ない」のみ(修正済=常時表示に統一、`moon_trip.gd`/`sky_castle.gd`)。他候補(candy gravity・submarine rotation・空 fog・各種ループ)は実コード確認で問題なし。**6ワールドすべて いつでも おうちへ かえれる**。
  - **push は この環境ではブロックされる**ので、改善さんに `! git push origin main` を依頼する運用(プロンプトに `!` 付きで入力 → このセッション内で実行)。push 後 Vercel が自動デプロイ。
  - **ライブ状況**: v0.54.2 まで再エクスポート済(`74d7e04`・export/web と一致)。**未 push** なので `! git push origin main` でデプロイ反映。push 前のライブは v0.53.0。

- **v0.51.0 = A-5 電車の窓から乗客が手を振る**(`docs/PLAYFUL_DETAILS.md` 第3弾):
  - `scripts/entities/train.gd` に乗客を追加。**静止乗客=車両ごと MultiMesh**(1つおきの窓×両側・110m 距離カリング `_update_passenger_cull`)、**挨拶する乗客=各車両 1 人の実ノード**(胴体のみ、`_wavers`)。公開 `wave_passengers()` が **ぴょこっと上下バウンス**(`animal.wave_back` のやさしい動き)+ ♥(`animal._pop_heart` 流用)。`_wave_cooldown=3.5s`・遠景(>110m)はスキップ。顔なし・真っ黒なし・**音なし**(やさしい音厳守)。**⚠️ v0.51.1 で「腕」を削除**(改善さんフィードバック=細い腕が幼児に怖い)。腕の見た目は今後も復活させない。
  - 新規 `scripts/world/train_greeters.gd`(`main.gd` が `_spawn_extra` で生成): 0.2秒毎に観測者(乗車中=乗る編成アンカー/歩行中=Player)の **45m 以内(`GREET_RANGE`)** を通る編成へ `wave_passengers()`。乗る編成自身は除外=自分が振られる側。`ride_controller.gd` に `get_current_train()` 追加。
  - **コミット対象ファイル**: `scripts/entities/train.gd` / `scripts/world/train_greeters.gd`(新規)/ `scripts/world/ride_controller.gd` / `scripts/main.gd` / `scripts/dev/auto_capture.gd` / `changelog.md` / `docs/HANDOFF.md` / `docs/PLAYFUL_DETAILS.md`。`Main.tscn` は不変(load_steps 64 据え置き)。**`export/web` はコミットしない**(再エクスポートは別途)。
  - **次の最重要 = 改善さんの体感確認(v0.50.0 + v0.51.0)**。v0.51.0 の確認点: 乗客シルエットの可愛さ・怖くなさ、手振りの速さ・頻度、すれ違い距離(`GREET_RANGE` 45m が適切か)、まどぎわ/うんてんせき視点での見え方、fps。**調整候補**: `GREET_RANGE`・`WAVE_COOLDOWN`・乗客の色/大きさ(`PASSENGER_RADIUS`)/間引き密度・距離カリング距離(現在 `WHEEL_ANIM_RANGE=110` を流用)。
- **遊び心の追加分(第1弾 v0.49.0 + 第2弾 v0.50.0)の要点**:
  - 仕様は `docs/PLAYFUL_DETAILS.md`。実装方式は **`main.gd` の `_spawn_extra(name, script)` で Main 直下に小ノードを起動時生成**(`Main.tscn` 不変・`load_steps` 据え置き・セーブ項目を増やさない)。各本体が `find_child("Player")` 等で自分の参照を探す。
  - 第1弾(v0.49.0): **A-1 手をふるとみんなが応える** / **B-1 かくれんぼ動物**(`scripts/world/hide_and_seek.gd`)。
  - 第2弾(v0.50.0): **B-6 きらきらふみいし**(`scripts/fx/magic_steps.gd`)/ **C-1 くしゃみ・あくび・うとうと**(`scripts/entities/animal.gd` に追記)/ **B-2 たたくと反応するもの**(`scripts/world/interactables.gd`)。
  - **A-3 足元の鳥・蝶は改善さんの判断で見送り**(2026-06-04)。一度 `scripts/fx/critters.gd` を実装したが削除済。`PLAYFUL_DETAILS.md` に〔見送り〕明記、再着手しない。
  - **B-2 は唯一 物理ピッキング方式**: `interactables.gd` が `get_viewport().physics_object_picking = true` にして `Area3D.input_event` でタップを拾う(他の小ネタは近接式)。**Web/iPad でタップが確実に効くか・HUD ボタンと干渉しないかは実機未確認**(最優先の確認項目)。
- **次セッションの最重要タスク = 改善さんの実機/ブラウザ体感確認**(v0.50.0): ①B-2 のタップが効くか(物理ピッキングの実機挙動)②ふみいしの位置(`magic_steps.gd SPOTS`)・頻度・かわいさ ③動物の小しぐさ(`animal.gd` の `QUIRK_MIN/MAX`・音量 `_voice.volume_db`)の可愛さ・うるささ。OK なら Web 再エクスポート→push。
- **デプロイ手順**: Web は CLI `Godot --headless --export-release "Web" export/web/index.html` で再エクスポート → 検証(`for_mobile=false`・presets 差分なし・`index.*` で日本語化なし・noindex)→ `export/web/index.html`+`index.pck` を明示 add でコミット → push。`export/web` は CLI 実行で毎回汚れるので、ソースのコミット前は必ず `git checkout -- export/web`。
- **実装済みの全体像**: 電車(乗る/運転/分岐)・6つの別世界(つき/そら/うみ/おかし/きょうりゅう/ゆき、いずれも乗り物→ワープ)・**おでかけメニュー「どこへ いく?」**(1タップで各世界)・**集めるとごほうび**(げんき=速度UP/ほし=お祝い+ほしのき/なかよし=動物がほしをくれる)・なかよし/星/図鑑/ミッション/親モード/昼夜。
- **残る最重要タスク = 改善さんの iPad 実機確認**(push 後): ①各ワールドの fps(草4200・魚48・雪粒・列車最適化済)②酔い(自動巡航/惑星カメラ)③音量 ④速度UPが速すぎないか ⑤ごほうび(ほしのき/プレゼント)の頻度・嬉しさ ⑥ゆきの明るさ。
- **検証の流儀**: 各 .gd は `--check-only --script` で構文 → `--quit-after` で Main 起動 → `AutoCapture`(`scripts/dev/auto_capture.gd` の `MODE` を該当 `AUTO_*` にして起動→スクショ、終了後 **必ず SINGLE に戻す**)。`AUTO_*` 実行は `user://save.json` を汚すことがある(`add_star` 等)→ 確認後 **ローカル save.json を削除**(配信版の子のセーブは別ストレージなので無関係)。
- **調整したくなったら**: 速度上限=`reward_manager.gd ENERGY_MAX_BONUS`/係数 `ENERGY_STEP`。ほしのき位置=`STAR_TREE_POS`。ギフト間隔=`animal_manager.gd GIFT_INTERVAL_*`。各ワールドの巡航=各 `*_land.gd`/`submarine.gd` の `CRUISE_R/CRUISE_Y/CRUISE_SPEED`、丘は巡航リング外(内縁>CRUISE_R+α)に置くこと(v0.48.1 で yuki/dino を是正済)。

**集めると ごほうび(v0.48.0)**: ほし/なかよし/げんき に payoff(改善さん選択)。新規 `scripts/world/reward_manager.gd`(Main 直下 `RewardManager`)。①**げんき→スピードアップ**: `player.gd` に `energy_speed_scale`(移動を `SPEED*speed_scale*energy_speed_scale`、地上+月の両方)、reward_manager が `min(1+energy*0.03, 1.5)` を設定(上限+50%=怖くない・永続=energy はセーブ済)。②**ほし→お祝い+ほしのき**: 5の倍数毎に お祝い通知+キラキラ+音(`_last_milestone` を読込値で初期化=起動時は祝わない)、スポーン前方(6,-14)の「ほしのき」の実が star_count 分 金色点灯。③**なかよし→プレゼント**: `animal_manager.gd` に `_try_gift`(12〜20s毎・近くの なかよしが ほしをくれる→add_star)。全て energy/star_count から派生=**セーブ項目を増やさない**。`Main.tscn` load_steps 64。`AUTO_REWARD` で検証(speed 1.30/1.50・ほしのき点灯・ギフト+1)。**注意**: 速度上限/木の位置/ギフト間隔は実機で調整可。`reward_manager.gd.uid`/`world_select.gd.uid` はエディタ起動で自動生成。

**わかりやすさ(v0.47.0)— おでかけメニュー「どこへ いく?」**: ゲームが大きくなり 6つの世界の乗り物が散在し見つけにくい(特に潜水艦)問題への対応(改善さん選択)。新規 `scenes/ui/WorldSelect.tscn`+`scripts/ui/world_select.gd`(Main 直下 `WorldSelect`、`book.gd` と同じ overlay 方式)。HUD 桃色「どこへ いく?」`WorldButton`(上部左)→ 6つの絵カード(つき/そら/うみ/おかし/きょうりゅう/ゆき)→ タップで `warp_in()` 即ワープ。各世界6つに 公開 `warp_in()`+`is_active()` を追加(既存 `_go_moon`/`_go_sky`/`_dive`/`_go_candy`/`_depart` を呼ぶ薄いラッパ・現在地に依存しない)。ボタンは **地上+非乗車のみ表示**(world_select の `_process` が `is_active()`×6 と `is_riding()` で制御)。`Main.tscn` load_steps 63。`AUTO_WORLDSEL` で検証(地上表示/6カード/warp_in→on_moon=true/世界内非表示)。`paused` は close で必ず解除。`world_select.gd.uid` 未生成(エディタ起動で自動・Main は path 参照)。乗り物・既存ワープ・ミッション文言は不変。

**第8の目玉(v0.46.0)— そりで「ゆきの くに」**: 改善さん選択(AskUserQuestion)。新規 `scripts/world/yuki_land.gd`(Main 直下 `YukiLand`・潜水艦/恐竜と同じ自動巡航)。地上(`SLED_DOCK=(-56,8)`)に そり→近接で `YukiButton`「ゆきの くにへ いこう」→ フェード →`YUKI_POS=(0,60,-2600)`。雪原・もみの木・ゆきだるま・ペンギン・しろいうさぎ・かまくら・**あったか温泉(湯けむり)**・**オーロラ(明滅)**・**降る雪(GPUParticles)**。明るい夕暮れ空(暗くしない)。**クリスタル近接で add_star**。「おうちへ かえる」常時。env は海/おかし/恐竜と同じ fog 退避/復元。`game_state.visited_yuki`+セーブ+ミッション+`AUTO_YUKI`。`Main.tscn` load_steps 62。`YukiButton` は他ワールドボタンと同 278 スロット(同時に出ない)。`yuki_land.gd.uid` 未生成(エディタ起動で自動生成)。**注意**: 初回 AUTO_YUKI 実行(コールド)で巡航移動量が異常表示=ワールド遅延生成のタイミング一過性、再実行で安定(moved≈10.7・実プレイは問題なし)。**調整候補**: fps(雪粒/オブジェクト数)、地上そり位置(-56,8)の重なり。

**第7の目玉(v0.45.0)— サファリカーで「きょうりゅうランド」**: 改善さんリクエスト。新規 `scripts/world/dino_land.gd`(Main 直下 `DinoLand`)。**潜水艦と同じ自動巡航**(歩行でなく `_drive_cruise`)。地上(`SAFARI_DOCK=(8,-58)`)に サファリカー→近接で `DinoButton`「きょうりゅうランドへ いこう」→ フェード →`DINO_POS=(2600,60,0)`。**草食のやさしい恐竜だけ**(サウロポッド/トリケラ/ステゴ/あかちゃん/プテラノドン・牙や襲う系なし・大声なし)。ジャングル(木/しだ/岩)。**たまご近接で かえる→あかちゃん+ほし**。「おうちへ かえる」常時。env は海/おかしと同じ fog 退避/復元。`game_state.visited_dino`+セーブ+ミッション+`AUTO_DINO`。`Main.tscn` load_steps 61。`DinoButton` は Sub/Candy と同座標(278・同時に出ない)。`dino_land.gd.uid` 未生成(エディタ起動で自動生成・Main は path 参照)。**実機後の調整候補**: fps(恐竜数)、地上サファリカー位置(8,-58)の重なり。

**第6の目玉(v0.44.0)— おかしの きしゃで「おかしの くに」**: 改善さん選択(AskUserQuestion)。新規 `scripts/world/candy_land.gd`(Main 直下 `CandyLand`)。地上(`CANDY_DOCK=(44,-30)`)に チョコの機関車→近接で `CandyButton`「おかしの くにへ いこう」→ フェード →`CANDY_POS=(2000,60,-2000)` の **歩ける** 甘い世界(潜水艦の自動巡航とちがい歩行・物理ON)。**落ちない**=`StaticBody`+`CylinderShape` の床 + リング状 見えない壁 + 床下安全網。中身: チョコの丘/ロリポップ/クッキーの家/ゼリーの川/カップケーキ/キャンディケーン/わたあめ雲/グミのくま。**お菓子近接で `add_energy`(げんき連動)・ほしも**。「おうちへ かえる」常時表示。env は海と同じく fog 退避/復元。`game_state.visited_candy`+セーブ+ミッション+`AUTO_CANDY`。`Main.tscn` load_steps 60。**注意**: `candy_land.gd.uid` は未生成(エディタ起動で自動生成・Main は path 参照なので runtime 不要)。`CandyButton` は SubButton と同座標(278・両者同時に出ない)。**実機後の調整候補**: fps(オブジェクト数)、地上きしゃ位置(44,-30)の他構造物との重なり。

**性能の予防策(v0.43.0)— 列車描画の最適化**: 過去評価で唯一残していた積み残し③。`train.gd` の `_make_material` 系を**色キーの static 共有キャッシュ**に(定数色のパーツが1000個超→十数個に集約)+ **窓を車両ごとに MultiMesh 化**(窓 draw call 約600→約55)。**見た目は不変**。車輪は回転するため据え置き(近接ゲート済み・iPad でなお重ければ台車/車輪 MultiMesh が次候補)。`AUTO_RIDE`/`TRAIN_CLOSE` で見た目不変を確認。

**フィードバック反映(v0.42.0)**: ①**さくらふぶき削除**(`Main.tscn` の Player 子 `CherryPetals` ノード+ext_resource を撤去、load_steps 60→59。各 `_set_petals` は `if _petals:` ガードで無害)。②**草をリアル&まんべんなく**(`grass.gd`/`grass.gdshader`: 1枚ペラ→**X字クロス**(SurfaceTool ArrayMesh・cull_disabled・1 draw call 維持)、`FIELD_RADIUS` 95→170・`BLADE_COUNT` 1400→4200、根元濃い/先端明るい+株ごと濃淡ゆらぎ)。③**カメラ左右ボタン反転**(`camera_rig.rotate_view` の符号反転)。**実機後の調整候補**: 草の fps(重ければ `BLADE_COUNT`/`FIELD_RADIUS` を下げる)。

**仕上げ調整(v0.40.0)— 子供が遊びやすく**: ①導線: タイトル「はじめる」で `signal started`→`mission_manager` が現在ミッションを `show_notice` で案内、達成時は次も通知(パネルは「メニュー」で開く方式を維持)。②やさしい夜: `sky_color.gd` の夜を明るく(`NIGHT_AMBIENT_ENERGY`0.10→0.17・`NIGHT_BG` 明るい青紫・`NIGHT_SUN_ENERGY`0.42)。③空の城: 城を大きく(天守10×12×10・塔も)、**雲を平らに(球 scale0.42 が城を埋めていた→上面=歩く面)**+影色で立体感、到着導線(城正面 spawn・welcome・めじるしほし)。④`AirplaneButton` を下げ Moon と分離。

**潜水艦で海底(v0.41.0)— 新規 `scripts/world/submarine.gd`(Main 直下 `Submarine`)**: 湖(`TerrainHeight.LAKE_POS`)に**半透明の水面(新規・湖に水が無かった)**+黄色い潜水艦。近接で `SubButton`「うみに もぐる」→ フェード →`SEA_POS=(-2000,-600,2000)` の明るい海中。**自動巡航のみ**(`_begin_ride` で潜水艦をプレイヤーに装着・物理OFF・gravity0、`_drive_cruise` が `_cruise` waypoint を一定速度で周回・潜水艦は進行方向へ yaw、既存カメラ追従)。海の世界: 砂床・サンゴの庭・海藻(揺れ)・岩・宝箱・**魚6群れ48匹**(`_update_fish` の sin 周回+尾ゆれ)・くじら/かめ(Tween)・泡(GPUParticles)・**しんじゅ**(近接自動獲得→ほし+1)。「うみから あがる」常時表示でいつでも浮上。`game_state.visited_submarine`+セーブ+ミッション追加。`Main.tscn` load_steps 60。**env 復帰の注意**: 海で `fog_density/enabled` を変えるので、起動時に退避し浮上時に復元(DayNightCycle 再適用では fog密度は戻らない)。
**潜水艦の次の調整候補(実機後)**: 潜水艦の追従カメラの見え方(巡航中に潜水艦が中心に来るか)、巡航ループの形/速度、魚の数(fps)、湖の水面の波(`water.gdshader` 適用は未/簡易マテリアルで実装)。

## 進捗(2026-06-03 時点 — 第4ウェーブ: 月の充実 + 飛行機で空の城 + フィードバック反映)

ブランチは引き続き `feature/driver-mode`(**まだ未 push**)。計画は `C:\Users\papa\.claude\plans\radiant-hopping-anchor.md`(第4ウェーブ用に上書き済み)。changelog の v0.37.0〜v0.39.0 が該当。

**月の作り直し(v0.37.0):** 薄い円盤をやめ 大きな球体ドーム + もちつきうさぎ(うす/きね/もち/つき手・返し手) + 帰りのロケット(近接で「おうちへ かえる」) + ピンク旗の削除。`moon_trip.gd`。

**第4ウェーブ — 月の充実(v0.38.0、`moon_trip.gd`):** ①もちだんご(三色だんご、近接で `add_energy(1)`、`stars.gd` 方式) ②宇宙の演出(回る地球 `_earth_node`/ふわふわ UFO/星) ③月面カー(バギーを `_mount_buggy` で**プレイヤーの子に reparent**、`player.speed_scale=1.8`、エンジン音ループ。MoonButton を文脈で のる/おりる/かえる に出し分け)。

**第4ウェーブ — 飛行機で「そらの おしろ」(v0.38.0、新規 `scripts/world/sky_castle.gd` = Main 直下 `SkyCastle`):**
- moon_trip と同じワープ骨格。**飛行機は1機**(`_plane`)で、着陸した所に駐機(`_park_pos` で近接判定)、飛行中はプレイヤーの子に装着。
- **自動遊覧飛行**(改善さん選択): `_begin_flight` で `player.set_physics_process(false)`+`gravity_scale=0`、`_climb_then` が上昇アークを Tween(**既存 CameraRig がプレイヤー追従するので飛ぶ絵になる**=追加カメラ不要)→ `_transition` フェード中点で空の城へ。
- **空の城ワールド**(`SKY_POS=(-2000,400,-2000)`、初回のみ `_build_sky`): 歩ける雲の島(円柱コリジョン)+ お城 + 飛び石の雲(`SKY_GRAVITY=0.4`)+ レインボーの橋 + 城の上空を旋回する新幹線(`_decor`)+ ほし(`add_star`)。**落下防止**=ふちの見えない壁 + `_process` 安全網。**明るい夢空**(env 退避/復帰)。
- HUD: `TouchHUD.tscn` に `AirplaneButton`(押下/表示は sky_castle.gd が直接管理、`touch_hud.gd` はバウンスのみ)。記録: `game_state.visited_sky_castle`+`set_sky_castle_visited()`、`save_system` に `"sky_castle"`、`mission_manager` に「ひこうきで そらの おしろへ いこう」+「ほし9こ」。`Main.tscn` load_steps 58→59。

**フィードバック反映(v0.39.0):**
- **月を「小さな惑星」に(裏側まで歩ける)** — 最重要。`player.gd` に **`planet_mode`/`planet_center`** を追加し `_planet_process`(重力を球中心へ・`up_direction`=球面法線・接平面へ射影した移動・ジャンプは法線方向・`_orient_to_surface` で体を法線に傾ける)。`camera_rig.gd` に **`set_surface_up()`**(惑星では「上」を法線に合わせる。`_surface_offset` は平行移送で安定化、`UP` のとき従来と**完全一致**=地上/空に回帰なし)。`moon_trip.gd` は **半径22mの1球+`SphereShape3D`**(`PLANET_R`)、ふち壁撤去、装飾は `_place_on_planet`/`_surface_basis` で**法線に合わせて配置**(ロケット=てっぺん、もちつきは傾いた root の下に local 再構成、もちだんご/月面カー/クレーターも)。`_go_moon` で `planet_mode=true`+`gravity_scale=0.42`、`_go_home` で `planet_mode=false`+`rotation=ZERO`+`up_direction=UP`+rig を UP に戻す。`_process(月)` で毎フレーム rig の surface_up を更新。**検証**: `AUTO_MOON` 歩行テストで中心からの距離が R=22 一定(落ちない)・updot 1.0→0.08(連続歩行)・カメラ上向き法線追従。
- **さくらふぶき停止**: `CherryPetals`(Player 子で常時追従)を 月/空で `emitting=false`、地球帰還で `true`(moon_trip/sky_castle の env 切替で)。
- **空の視認性**: `sky_castle._apply_sky_env` の `ambient_light_energy` 0.95→0.5、`SKY_BG` を濃いめ(0.45,0.68,0.95)でコントラスト確保。
- **眼の出っ張り解消**: `player._build_head` の目/ほっぺを `_face_pt()`(顔球の (x,y) 表面に沿わせる)で配置し奥行きスケールも薄く。

**次にやること(この第4ウェーブ・フィードバック分):**
- **改善さんの iPad 確認待ち**: ①月の球面歩行が酔わないか・楽しいか(`MOON_GRAVITY=0.42`/カメラ法線追従)②空の城で落ちて怖くないか・視認性 ③月面カー・もちだんご・ほし ④飛行が酔わないか ⑤眼の見た目 ⑥月/空で桜が消えるのが自然か ⑦Web export 後に「そらへ いく」が出るか。
- **未 push**: 実機 OK 後に main マージ → **Web 再エクスポート** → push(`export/web` は CLI 実行で毎回汚れるので、コミット前に `git checkout -- export/web`、`git add` は明示パスで)。`sky_castle.gd.uid` も忘れず add。
- 調整候補: 空の城のお城をもっと大きく(存在感)/ 惑星の半径や重力の体感 / 飛行アークの時間 を実機フィードバックで。

## 進捗(2026-06-02 時点 — 作りこみ本格化 Phase 6 / 第3ウェーブ + プロダクト評価対応)

改善さんが「もっと本格的に作りこみ」と指示。方向は「電車を深く + 駅まわりを楽しく」を選び、「1テーマを深く磨く」方針で中心の目玉に **うんてんしゅモード** を実装(v0.27.0、ブランチ `feature/driver-mode`)。計画は `C:\Users\papa\.claude\plans\radiant-hopping-anchor.md`。

**プロダクト評価と対応(v0.34.0〜v0.36.0):** 4観点の独立監査で採点(総合 B+ 8.1/10。安全10・子供UX9.5・コンテンツ8.5・保守8.0・正しさ6.5・性能6.5)。指摘のうち**列車描画の最適化(③)以外をすべて実施**:
- **P0 バグ修正(v0.34.0)**: B1 乗車中の月ボタン抑止 / B2 分岐の二重編成をルート入れ替え方式で解消 / B3 `_active_slug` で実トラック追従 / B4 月リム18m / B5 駅ホーム段差0.16m。AUTO_FIXCHECK で実測。
- **P1 コンテンツ(v0.35.0)**: 図鑑の詳細パネル(`train_data` に description/top_speed_kmh、`book.gd` でタップ詳細)/ ミッションの目玉ツアー(うんてん・おしろ・つき を追加、GameState に visited_moon/drove_train)。
- **P1 性能(v0.35.1、列車描画以外)**: 月の遅延生成 / 駅の柱コリジョン削除 / 歩行プロンプト間引き。
- **P2 仕上げ(v0.36.0)**: 親モード(`Settings.tscn`/`settings.gd` + HUD「おとな」: 数字ゲート→音ON/OFF・あそんだ かいすう・データけす)/ DBG print・dbg.html 除去・陳腐化コメント修正。
- **未実施(意図的)**: ③ 列車マテリアル共有/MultiMesh化(描画最適化)。iPad mini 30fps の本命対策として今後の課題。`train.gd` の `_make_material` 系を色キーで共有 or 窓/台車を MultiMesh 化する想定。

**柱撤去/カメラ基準移動/月旅行(v0.32.0):**
- 線路の柱撤去: `railway.gd` の `_build_piers_for()` 呼び出しを停止(視界優先・空に浮く線路)。
- カメラ基準移動: `player.gd` の `_camera_relative_move()`。いまのカメラの前/右基準で動く(「うえ」=画面奥)。`get_viewport().get_camera_3d()` の basis を使用。
- 月旅行: 新規 `moon_trip.gd`(Main 直下 `MoonTrip`)。地球の発射台ロケット近接で HUD `MoonButton`「つきへ いく」→ フェードして `MOON_POS`(2000,60,2000)へワープ。`player.gravity_scale`(月=0.16)、`camera_rig.snap_to_target()`、`DayNightCycle.paused` で宇宙の環境に切替。月: 台(当たり判定)+ふち壁+落下復帰、地球・星・うさぎ・旗。「おうちへ かえる」で帰還。HUD は find_child で取得。検証 AutoCapture `AUTO_MOON`。

**お城(v0.30.0):** 新規 `scripts/world/castle.gd`(Main 直下 `Castle` ノード、CASTLE_CENTER(150,135))。中央アーチ(X方向トンネル)を**おしろでんしゃ**(`route_data` "oshiro" 地上ループ、北点=城中心)がくぐり、**そらでんしゃ**(`route_data` "sora" +17m 高架ループ、自動支柱)が上空をめぐる。TrainData は `resources/train_data/oshiro.tres`・`sora.tres`、Main.tscn の Trains に2ノード追加(図鑑11編成に自動増加・おしろは乗車可)。城壁(±Z)と四隅の塔のみ当たり判定(通路は空ける)。検証は AutoCapture 新 `AUTO_CASTLE`。route_data の "oshiro" center+(0,rz) と castle.gd の CASTLE_CENTER は一致させること。

**当たり判定(v0.29.0):** これまで地形とプレイヤーだけが固く、他は全すり抜けだった(改善さん指摘)。改善さんの選択で**たてもの(家/お店/ビル)と駅(ホーム+柱)**を `StaticBody3D + BoxShape3D`(`town.gd`/`station.gd` の `_add_box_collision`、既定レイヤー1=プレイヤーのマスク1)で固くした。電車・動物・星・木・小物は意図的にすり抜けのまま。検証は AutoCapture 新 `AUTO_COLLISION`(建物へ歩かせ 1.85m 手前で停止=blocked)。**今後、新しく置く大きな構造物には当たり判定を付けるか都度判断する**(動く電車・小動物・収集物は付けない方針)。

**踏切の本格化(v0.28.0):**
- 新規 `scripts/world/crossing.gd`(自己完結の踏切ノード)。`town.gd` は CROSSINGS の slug+ratio を渡して生成。遮断機バーの開閉(自ルート編成が22m以内で閉)・黄黒縞バー・2灯の交互点滅(1.6Hz)・×警標・やさしい警報音(閉動作中かつプレイヤー34m以内のみ、-16dB ループ)。接近検知は slug 一致の編成の `get_ride_anchor_position()` とのワールド距離。検証は AutoCapture 新 `AUTO_CROSSING` モード。

**第3ウェーブ(v0.27.0 — うんてんしゅモード):**
- **すすむ・とまる**(`train.gd`): 運転スロットル `_driver_throttle`(`move_toward` で ease=バネ感)を RUNNING の前進量に乗算。`enter/exit_driver_mode`・`set_driver_throttle`・`is_driver_stopped`。opt-in(非運転時は throttle=1.0 恒等で自動走行不変)。駅自動停車は運転中も併用。
- **ぶんきで みちを えらぶ(ワープ式)**(`train.switch_route` + `route_data.branches()` + `railway.get_route_length` + `ride_controller`): 運転中の編成を別ルート Path3D へ reparent + 弧長系差し替え。必ず `_transition` フェード中点で実行。分岐は本線3編成間をキュレート。`_check_branch` が接近監視→2択(のりかえ/まっすぐ)、選ばなければ直進。逆戻り即提示は `_branch_cooldown` で抑止。
- **添え**: 自分で減速して駅に止めると「ぴったり とうちゃく!」(上昇音 + 星+1)。
- **UI**(`TouchHUD.tscn` + `touch_hud.gd`): 「うんてん」(運転中「じどう」)/「ゴー」「とまれ」(左下)/分岐2択(中央縦積み)。降車で運転UIを畳む。
- 検証: AutoCapture 新 `AUTO_DRIVE` モードで運転突入・分岐2択・ワープ後前面展望を確認(`screenshot_drive/branch/warp.png`)。

(以前の指示)3方向「世界をにぎやかに・見た目を磨く・電車を深く」のうち第1・第2ウェーブを実装済み。詳細は `changelog.md` の v0.25.0 / v0.26.0、当時の計画は `C:\Users\papa\.claude\plans\golden-humming-shamir.md`。

**第1ウェーブ(v0.25.0・commit `0fdda30`):**
- 車輪回転(`train.gd` `_wheels`/`_spin_wheels`、カメラ110m以内のみ)/ 駅メロ(`train.gd` `arrived` シグナル + `station_manager.gd` の `_make_jingle`、6駅ぶん)/ トゥーンシェーディング(`rim.gdshader` に `light()` 追加・`toon_steps`)/ おだんごで げんき(`GameState.energy` 新規・保存、HUD「げんき」カウンタ、おかし駅で近接トリガー)/ 流れ星(新規 `scripts/fx/shooting_star.gd`、夜にランダム)。

**第2ウェーブ(v0.26.0・commit `f5e4ee8`):**
- 車内視点(`ride_controller.gd` `RIDE_VIEWS`/`cycle_ride_view`、前面=`train.get_ride_mount_front`、HUD「ながめ」ボタン)/ 車内アナウンス(`train.departed` シグナル + 到着/発車テロップ + 発車チャイム、`stations_path` で駅名)/ 動物の歌(`animal.sing` + `animal_manager` が定期発火)/ パンタ可動(`train._panto`/`_process`)/ 草の揺れ(新規 `assets/shaders/grass.gdshader` + `scripts/world/grass.gd`、MultiMesh 1 draw call・中央95m約1400株)。

**その後の調整:**
- 昼夜サイクルを 84秒→840秒(約10倍ゆっくり、commit `2729e70`)。実機で日替わりが速すぎたため。`day_night_cycle.gd` `CYCLE_SEC`。さらに調整するならここ。

**未完・次にやること:**
- **改善さんの iPad 確認待ち(第3ウェーブ・うんてんしゅモード)**: ゴー/とまれの加減速が気持ちよいか(`train.gd` `THROTTLE_EASE`)/ 分岐2択が分かりやすいか・ワープが酔わず一瞬か / 止めっぱなしで壊れて見えないか / 「ぴったり とうちゃく」が嬉しいか / 分岐点の出る場所(`route_data.branches()` の `at_ratio`)が適切か。**まだ push していない**(`feature/driver-mode` ブランチ。実機確認後に Web 再エクスポート→push 予定)。
- **改善さんの iPad 確認待ち(第1・2ウェーブ)**: 車輪の回る向き / おだんご / 駅メロ・もぐもぐ音 / 流れ星 / 視点切替の酔い・前面展望 / 車内アナウンス・発車チャイム / 動物の歌 / パンタの動き / **草の fps 影響(最重要・密度上限の判断、`grass.gd` の `BLADE_COUNT`/`FIELD_RADIUS`)**。
- **第3ウェーブの残り候補**: A4 手を振ると沿線が応える / A5 動物の家(MultiMesh か統合メッシュで draw call 抑制)/ B5 仕上げチューニング。うんてんしゅモードの拡張(本線以外のルートにも分岐を増やす場合は route 同士の近接が必要=route_data の地理調整 or 専用コネクタ線路を検討)。
- 上記とは別に、旧 v0.24.0 の片付け(下記)も残っている。

## 進捗(2026-05-31 時点 — iPad 実機フィードバック対応)

iPad/スマホ実機で遊んでもらい、出た不具合を順次修正・デプロイ。最新は commit `5e8bcaf`。

**この日のデプロイ内容(すべて push 済み・要 iPad 再確認):**
- **日本語フォント埋め込み**(文字化け解消): `assets/fonts/MPLUSRounded1c-Medium.ttf`(本文・既定 `project.godot gui/theme/custom_font`)+ `MochiyPopOne-Regular.ttf`(見出し)。**Label3D は既定テーマが効かない**ので `station.gd`/`animal.gd` で個別に `font` 指定。Web には日本語システムフォントが無いので埋め込み必須(PC エディタ実行で出るのは OS フォント補完のため)。
- **電車を `_physics_process` に移動**(`train.gd`): プレイヤーは `_physics_process`(固定60Hz・低fpsでもキャッチアップ)、電車は `_process`(描画fps依存)だったため、iPad の低fpsで「キャラは滑らかなのに電車だけ止まる」状態だった。物理プロセス化で解決。初期化は再試行式(ルート未生成でも諦めない)。
- **ベース解像度 1920×1080 → 1024×576**(`project.godot`): UI が小さく操作しにくい対策。UI が相対的に約1.9倍・iPad 描画も軽量化。
- **セキュリティ強化(子供向け配信)**: `vercel.json` に CSP / Permissions-Policy / X-Frame-Options(DENY)/ Referrer-Policy / X-Content-Type-Options / X-Robots-Tag。検索除外 `export/web/robots.txt` + `noindex`(`web/template.html` の meta)。`CLAUDE.md` に「セキュリティ原則」節を追加。コード調査で PII無し・入力欄無し・外部リンク無し・通信無し・トラッキング無しを確認。CSP はローカル headless 検証で違反0件・wasm 起動到達を確認済み。
- **実機4点修正**(`dff2b14`): ①「ミッション クリア!」通知をミッション表示と重ならないよう画面中央へ移動(`TouchHUD.tscn` Notice)②ドクターイエローを車庫待機(park)→走行(dwell)に(`route_data.gd`、子供には故障に見えるため)③動物が顔と逆向きに走る→`animal.gd` で `rotation.y = _heading + PI`(モデルの顔は -Z)④**カメラ手動回転ボタン**追加: `camera_rig.gd` に `rotate_view(dir)`(45°ずつ・なめらか=酔いにくい)、`TouchHUD.tscn` に緑「カメラ ◀ ▶」、`touch_hud.gd` で配線。
- **降車できない不具合修正**(`5e8bcaf`): タッチの「おりる」は `interact` action のエッジ検出だったが、タッチ/Web で**指離しが取りこぼされ action が押されっぱなし**になり2回目タップでエッジが立たず降車不可だった。**タッチボタンを `Button.pressed` 直結**にし `RideController.toggle_ride()` を呼ぶ方式へ(タップごとに確実)。キーボード(E/Enter)は `_process` の interact 経由で `toggle_ride()` を呼び維持。

**⚠️ 重要な落とし穴(次回のために):**
- **`export_presets.cfg` の `vram_texture_compression/for_mobile` は必ず `false`**。`true` だと Web export が「Cannot export ... due to configuration errors」で失敗する(headless では詳細が出ず原因特定に苦労した)。`Godot --headless --editor` を実行するとこの値が勝手に `true` に書き換わることがある → エディタ起動系を使ったら export 前に `git diff export_presets.cfg` で確認・復元する。
- 再帰削除(`rm -rf`)・`powershell Remove-Item -Recurse` はこの環境のポリシーで拒否される。ディレクトリを消したい時は `mv` で退避するしかない。
- `.godot` を `mv` で退避した残骸 **`.godot_bak/` が未追跡で残っている**(コミット対象外。手元で削除可)。`git add -A` で拾わないよう、コミットは個別ファイル指定で行うこと。

**未完・次にやること:**
- **改善さんの iPad 再確認待ち**: 降車できるか / 前回4点(ミッション重なり・黄色い電車・動物の向き・カメラ◀▶)が直ったか。OK なら下記の片付けへ。
- **診断ログの除去**: `train.gd` の `[DBG Train]` の `print`(`_try_init` と `_physics_process` 内、`_dbg_frames`)はコンソールのみの一時診断。動作確定後に削除。
- **診断ページ `export/web/dbg.html`**: コンソールを画面表示する診断用(電車停止調査で作成)。不要になったら削除(公開URLにも出る)。
- **親モード**(音量・データリセット・誤操作防止)は改善さんの希望で「不具合修正が落ち着いてから」。仕様相談から。
- パフォーマンス余地: 描画が重い場合、電車の見た目を保ったままメッシュ統合で draw call(約1200)を削減する案がある。

## 進捗(2026-05-30 時点)

**Phase 0〜2 + Phase 3-1〜3-5 + 2-4 + Phase 4 演出(一部)完了**。新幹線に乗れ、6 駅が立ち、8 種の動物がなかよしになり、星を集め、駅で電車が減速し、図鑑で発見状況を見られる。さらに Glow・星のきらきら/獲得バースト・なかよしハート・SL蒸気・UIボタンのぷにっと演出を追加。主要ループ「集める・出会う・乗る・探す」が一通り動く。次は Phase 3-6(ミッション)/ 音 / トゥーンシェーダー / 季節 / 自由アイデア。詳細は `changelog.md` 参照。
- 演出(Phase 4): Glow=Main の Environment、星きらきら/バースト=`stars.gd`、なかよしハート=`animal.gd._pop_heart`、SL蒸気=`train.gd._attach_steam`、UIバウンス=`touch_hud.gd._add_press_bounce`、リムライト=`assets/shaders/rim.gdshader`(animal/player)、ホタル=`fireflies.gd`(夜・Player子)、虹=`rainbow.gd`、ミッション=`mission_manager.gd`、効果音=`sound_fx.gd`(プロシージャル WAV)。Glow/リムライト/音の Web での挙動は要実機確認。
- 列車の車輪回転は負荷(約360個)で見送り中。
- スタート画面 `scenes/ui/TitleScreen.tscn`(title.gd)実装済み。「はじめる」押下で AudioContext 起動+フェードアウト。これで Web でも効果音が鳴る想定(実機要確認)。
- Phase 5 実装済み: BGM=`bgm.gd`(プロシージャル・ループ)、進捗保存=`save_system.gd`(user://save.json、GameState 直後に配置)、PWA=`export/web/manifest.json`+`web/template.html`(apple-touch・manifest link)。
- Phase 5 残り: 完全オフライン化(Service Worker キャッシュ。Export ダイアログで PWA ON or SW 追加)、親モード(音量・データリセット・PIN)。
- 順序の注意: GameState→SaveSystem を最前に。HUD に書く処理(ミッション)は call_deferred で HUD の _ready を待つ。効果音は _ready で prev を現在値に初期化して起動時の誤発火を防ぐ。
- 操作/見た目: 移動=D-pad・WASD/矢印。カメラは**固定追従**(`camera_rig.gd`、yaw0/pitch0.5。orbit は画面酔いするとのことで撤去)。プレイヤーは 3 頭身の運転士キャラ(`player.gd` でスクリプト生成、帽子・大きいうるうる目+キラキラ・ほっぺ・歩行アニメ)。Player.tscn は当たり判定のみ。
- オープンワールド(v0.23.0 で広域+線路網化): 地形 `WORLD_SIZE 700`/`MESH_SUBDIV 180`。線路は **9 ルートの線路網**(`scripts/world/route_data.gd` でデータ駆動定義 → `railway.gd` が各ルートの Curve3D/Path3D/レール/枕木/橋脚を生成)。**各編成に専用の閉ループ**を与え曲線を共有しないので、速度差があっても衝突・数珠つなぎが構造的に起きない。交差は高さ(elevation)で分離。波打つ 3 車線本線 + 名所ループ(湖/山/街)+ 高架立体交差(つばめ)。駅・名所・街は `railway.get_route_sample(slug, ratio)` でルート脇に配置。`get_route_path/get_route_stops/get_route_start_offset` が公開 API。
- 街は `town.gd`+`Town.tscn`: メイン街(中央)+ 各駅のそばの小集落、駅前広場(噴水/ベンチ/街灯)、街路樹、踏切(track_t 0.55/2.65/4.75)。窓・街灯・水は夜光る。
- 線路の見どころ `landmark.gd`(Main の Landmarks): トンネルを つばさルート(山B)に配置(レンガ坑口+かまぼこ天井)。湖の鉄橋は railway の自動橋脚(線路が水上に出る所)で表現。
- 建物・小物が増えたので負荷は実機要確認(重ければ town/landmark の数・窓を減らす)。
- `auto_capture.gd` 検証フック: MODE=AUTO_RIDE/AUTO_BEFRIEND/AUTO_BOOK、ViewMode=STATION/ANIMAL/STEAM。
- 進捗は `scripts/world/game_state.gd`(Main 直下、Autoload 不使用)が一元管理。`signal changed` で HUD カウンターと図鑑が更新。永続セーブは Phase 5。
- 星=`stars.gd`(近接獲得)、HUD カウンター/ずかんボタン=`touch_hud.gd`+`TouchHUD.tscn`、図鑑=`book.gd`+`BookOverlay.tscn`(.tres 走査でマスター化)、駅停車=`train.gd` の状態機械(`_slow_factor_at` で減速→ dwell/park、`get_route_stops` 由来)、駅発見=`station_manager.gd`。列車は弧長 `progress` で等速移動 + 各車両を個別 PathFollow で屈折(v0.22)。ドクターイエローは車庫で park(`depart()` で将来発車)。
- interact(タッチ)は乗車専用。なかよし・星・駅発見はすべて近接自動で競合回避。
- `auto_capture.gd` の検証フック: AUTO_RIDE(乗車)/ AUTO_BEFRIEND(なかよし)/ AUTO_BOOK(図鑑)、ViewMode に STATION / ANIMAL。
- 乗車システムは `scripts/world/ride_controller.gd`(Main 直下ノード)が中核。視点は屋根上俯瞰(改善さん選択)。運転席視点・列車運転は将来候補。
- 駅は `scripts/world/station.gd` + `station_data.gd` + `resources/station_data/*.tres` 6 個(データ駆動)。看板は Label3D の Y ビルボード(空中表示)。立て看板化は改善さんの判断待ち。駅停車・降車を最寄り駅に寄せる連携は未実装。

- リポジトリ: https://github.com/fanxingjudao-boop/shinkansen-world-godot (Public)
- 本番 URL: https://shinkansen-world-godot.vercel.app/ (Vercel Hobby + GitHub 連携で自動再デプロイ)
- PC ブラウザでの Phase 0 動作確認 OK / iPad Safari 実機確認は保留(改善さん判断、いつでも実施可能)
- Phase 1-2(空・昼夜)/ 1-4(雲)/ 1-5(水)/ 1-6(桜)が次の周回

### Claude による自動見た目確認

`scripts/dev/auto_capture.gd` + `scenes/dev/AutoCapture.tscn` を Bash から起動すると、改善さんに F5 を依頼しなくても Claude がスクリーンショットを取れる:

```
"C:/Users/papa/Desktop/Godot_v4.6.3-stable_win64.exe" \
  --path "C:/Users/papa/Desktop/shinkansen-world-godot" \
  "res://scenes/dev/AutoCapture.tscn"
```

出力先: `user://screenshot.png`(= `C:/Users/papa/AppData/Roaming/Godot/app_userdata/しんかんせんワールド/screenshot.png`)。視点は `auto_capture.gd` の `VIEW` 定数(`PLAYER` / `BIRD` / `SIDE`)で切替。

## 以降の開発フロー(Phase 1〜)

```
Godot エディタで変更
  ↓
Project > Export > Web で export/web/index.html に書き出し
  ↓ (出力ファイル名は必ず "index" に手動入力する。日本語化されると Vercel 配信不可)
git add export/web && git commit -m "..." && git push
  ↓
Vercel が自動で再デプロイ(1〜2 分)
  ↓
PC ブラウザ / iPad Safari で確認
```

注意: `export_presets.cfg` と `web/template.html` は Phase 0-5 で先行設定済みなので、再 Export のたびに改善さんが手動で:
1. Project > Export ダイアログでファイル名を `index` に入力
2. Options > Html > Custom Html Shell に `res://web/template.html` を入力

を確認する必要がある(Godot 4.6 が `export_presets.cfg` の手書き値を初回起動時に正規化して消す問題、詳細は memory: feedback-godot-web-export)。
