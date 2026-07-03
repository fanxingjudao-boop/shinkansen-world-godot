# HANDOFF — 引き継ぎ資料(Godot 版)

このドキュメントは Claude Code のセッション間で「いまどこにいるか」と「変わらない決定事項」を引き継ぎます。

- **現在地**: このファイルの「▶ 現在地」(セッション開始時に必読)
- **変更履歴の詳細**: `changelog.md`(v0.1.0 からすべて記録)
- **検証・デプロイ手順**: `.claude/skills/`(godot-check / godot-screenshot / web-export)
- **機能の全体像を1枚で**: `docs/GAME_OVERVIEW.html`(ブラウザで開く)

## ▶ 現在地(次セッションはここから)— 2026-07-03 更新

- **リポジトリ**: https://github.com/fanxingjudao-boop/shinkansen-world-godot (Public)
- **本番 URL**: https://shinkansen-world-godot.vercel.app/ (push で Vercel が自動デプロイ)
- **ブランチ**: `main`(作業は main 直接)。**origin より 2 コミット先行=未 push**:
  - `8105751` = **v0.58.2 まぶしさ抑制+そら線路の単調さ解消**(2026-06-21・Web 再エクスポート済)
  - `820ca9d` = CLAUDE.md 最適化+プロジェクトスキル導入(2026-07-03・ドキュメントのみ)
  - つまり**ライブは v0.58.1 のまま**。改善さんに `! git push origin main` を依頼すると v0.58.2 がライブ反映される。
- **🆕 v0.59.0 = えほんのき(2026-07-03・未 push・未エクスポート)**: 寓話(ファブル)が実る木。草原(-16,14)に絵本の木+近接「えほんを よむ」→ 絵本オーバーレイで 3 ページの小さなおとぎばなし(6 話・ひらがなのみ・やさしい結末)。新規 `scripts/world/story_tree.gd`(`_spawn_extra`・Main.tscn 不変・セーブなし)。`AUTO_STORY` で検証済。**要 改善さんの確認**: 文章・木の見た目・文字サイズ・場所・音量。おはなしの追加は `STORIES` 配列に足すだけ。
- **v0.58.2 の内容**(詳細は changelog.md): 白飛び対策(Main の glow 調整・candy/dino/submarine の ambient 抑制・流れ星の発光減。トーンマップ Linear は据え置き)+ 唯一の完全円だった そらでんしゃを蛇行楕円に(`route_data.gd`)。**push 後、改善さんの実機確認待ち**: まぶしさが取れたか・発色・そらでんしゃの見え方。
- **🎯 次セッションの最重要 = 改善さんの iPad 実機/ブラウザ体感確認**(たまっている確認項目): 踏切の開閉タイミング・各地分岐の運転体験・草の fps・B-2 物理ピッキングのタップ精度・キツネの体感(大きさ・可愛さ・切替の分かりやすさ)・v0.58.0 スマホ操作性(D-pad 寸法・たて持ち案内・ノッチ)・v0.58.1 タイトル文字切れ・v0.58.2 まぶしさ。
- **新規実装するなら候補**: `docs/PLAYFUL_DETAILS.md` の **A-2 動物のしぐさ / C-3 季節と天気(虹・桜・雪)**、ROADMAP 6-1 **駅前のお店**(いずれも `_spawn_extra` 寄生方式で `Main.tscn` 不変・低リスク)。
- **実装済みの全体像**: 電車(乗る/運転/分岐で各地へ)・6つの別世界(つき/そら/うみ/おかし/きょうりゅう/ゆき)+銀河鉄道・おでかけメニュー「どこへ いく?」・集めるとごほうび(げんき=速度UP/ほし=お祝い+ほしのき/なかよし=プレゼント)・かくれんぼ/楽器/ふみいし/レア車両などの遊び心・なかよし/星/図鑑/ミッション/親モード/昼夜・ミニマップ・主人公えらび(うんてんしさん/きつね)。

## 恒久ルール(セッションをまたいで守ること)

### 運用

- **push はこの環境ではブロックされる** → 改善さんに `! git push origin main` を依頼する(プロンプトに `!` 付きで入力するとセッション内で実行される)。
- **検証の流儀**: .gd 変更 → **godot-check** スキル(構文+シーン起動)→ 見た目に関わるなら **godot-screenshot** スキル(AutoCapture)→ 挙動/UI を変えたら **web-export** スキル(再エクスポート〜デプロイ)。
- **`export/web` は Godot 実行で勝手に汚れる**(AutoCapture 実行で index.* が debug ビルドに化けた実績あり)→ ソースのコミット前に `git checkout -- export/web`。正規反映は web-export スキルの CLI 手順のみ。
- **`export_presets.cfg` の `for_mobile` は必ず `false`**(`true` だと Web export が「configuration errors」で失敗し、headless では原因が表示されない)。エディタ起動系(`--headless --editor` 含む・原則使わない)を使ったら `git diff export_presets.cfg` で確認・復元。
- **再帰削除(`rm -rf` / `Remove-Item -Recurse`)は環境ポリシーで拒否される** → 消したいものは `mv` で退避する。ルートの `.godot_bak/` はその退避残骸(未追跡・コミットしない。改善さんの判断で削除可)。
- **コミットは個別ファイル指定で行う**(`git add -A` は `.godot_bak/` 等を拾うので使わない)。
- changelog.md に変更履歴を記録し、本ファイルの「▶ 現在地」を更新してからセッションを終える。

### 実装方式の標準

- **新機能は `main.gd` の `_spawn_extra(name, script)` で Main 直下に実行時生成**(寄生方式)。`Main.tscn` 不変・load_steps 据え置き・セーブ項目を増やさない。各本体が `find_child("Player")` 等で自分の参照を探す(常駐ノードは `world_refs.gd` の `WorldRefs.req()` 経由)。CanvasLayer(UI)も同方式で追加可。
- 進捗は `scripts/world/game_state.gd`(Main 直下・Autoload 不使用)が一元管理。セーブは `save_system.gd`(`user://save.json`、slug と数値のみ=個人情報なし)。
- スクリプトは preload 規約(`class_name` 不使用)。
- 大きな構造物を新しく置くときは当たり判定を付けるか都度判断(動く電車・小動物・収集物は付けない方針)。
- **Label3D は既定テーマのフォントが効かない** → `station.gd`/`animal.gd` のように `font` を個別指定(Web に日本語システムフォントは無いので埋め込みフォント必須、`assets/fonts/`)。
- 新しい主人公の追加 = `scripts/entities/characters/` の基底継承スクリプト+`character_roster.gd` に1行(player/title は触らない)。

### やらない決定(再着手しない)

- **BaseWorld 抽出(別世界スクリプトの共通化)**: 「5000行重複」は過大評価で、実際の重複 helper は世界ごとにドリフト済み(単純統合すると見た目が変わる)。2026-06-07 に改善さんが「ここで止める」を選択。helper を直すときは各世界個別に直す。詳細は memory `project-world-scripts-duplication`。
- **A-3 足元の鳥・蝶**: 一度実装したが改善さんの判断で削除済み(2026-06-04)。`PLAYFUL_DETAILS.md` に〔見送り〕明記。
- **乗客・背景キャラの細い腕(棒状の可動パーツ)**: 幼児に怖い(v0.51.1 で削除)。挨拶はバウンス+♥で表す。今後も復活させない。

### 調整したくなったら(パラメータ索引)

- 速度上限 = `reward_manager.gd` の `ENERGY_MAX_BONUS` / 係数 `ENERGY_STEP`。ほしのき位置 = `STAR_TREE_POS`。ギフト間隔 = `animal_manager.gd` の `GIFT_INTERVAL_*`。
- 各ワールドの巡航 = 各 `*_land.gd` / `submarine.gd` の `CRUISE_R/CRUISE_Y/CRUISE_SPEED`(丘は巡航リング外=内縁>CRUISE_R+α に置く)。
- 昼夜サイクル = `day_night_cycle.gd` の `CYCLE_SEC`(現在 840 秒)。草の密度 = `grass.gd` の `BLADE_COUNT`(4200)/`FIELD_RADIUS`(170)。
- 基準解像度 = `project.godot`(896×504・stretch viewport)。D-pad 寸法 = `TouchHUD.tscn`。たて持ち案内の文言 = `web/template.html`。
- 踏切の開閉 = `crossing.gd` の `CLOSE_AHEAD`(16)/`PASS_CLEAR`(7)。ミニマップ = `minimap.gd` の `MAP_SIZE/MAP_RANGE`。
- キツネの大きさ = `fox_character.gd` の `MODEL_SCALE`(0.55)。名前/色 = `character_roster.gd`。タイトルカード寸法 = `title.gd`(240×170)。
- 楽器の置き場所 = `instruments.gd` の `XYLO_POS`(12,8)/`TRUMPET_POS`(4,-12)。すれ違い挨拶の距離 = `train_greeters.gd` の `GREET_RANGE`(45m)。

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

## 既知の課題

1. **iPad 実機デバッグの困難さ**: Windows のみの開発環境では Safari の開発者ツールが使えない。Web 版の動作は PC ブラウザで確認し、iPad 実機は最終確認用(改善さんに依頼)。
2. **パフォーマンス**: iPad mini(古い世代)で 30fps が目標。重ければ草(`BLADE_COUNT`)・別世界のオブジェクト数・雪粒などを下げる。列車描画は v0.43.0 で最適化済み(マテリアル共有+窓 MultiMesh)。
3. **ファイルサイズ**: Web Export は初回 約20MB(wasm 圧縮後)。Service Worker キャッシュで 2 回目以降は瞬時。

## ファイル構造

```
shinkansen-world-godot/
├── project.godot              # 基準解像度・レンダラー等
├── CLAUDE.md                  # 作業指示書(最初に読む)
├── changelog.md               # 全変更履歴(v0.1.0〜)
├── .claude/skills/            # godot-check / godot-screenshot / web-export
├── docs/                      # 本ファイル・ARCHITECTURE・ROADMAP・GODOT_NOTES・PLAYFUL_DETAILS・SPEC・GAME_OVERVIEW.html
├── scenes/                    # Main.tscn・UI(TouchHUD 等)・dev/AutoCapture.tscn
├── scripts/                   # main / entities(train・player・characters)/ world / ui / fx / dev
├── resources/                 # train_data / station_data(.tres データ駆動)
├── assets/                    # fonts(同梱必須)/ shaders
├── web/template.html          # Custom HTML Shell(safe-area・たて持ち案内・noindex)
├── export/web/                # Web ビルド出力(コミット対象=ライブ配信物)・robots.txt
├── vercel.json                # セキュリティヘッダー(CSP 等・CLAUDE.md 参照)
└── reference/threejs-prototype/  # Three.js 版プロトタイプ(資料)
```

## 過去の進捗ログについて

かつて本ファイルに堆積していたバージョンごとの進捗ログ(v0.25〜v0.58 の詳細)は、`changelog.md` に同内容の完全な記録があるため 2026-07-03 に整理しました。過去の実装詳細・調整経緯は `changelog.md` を、機能の全体像は `docs/GAME_OVERVIEW.html` を参照してください。
