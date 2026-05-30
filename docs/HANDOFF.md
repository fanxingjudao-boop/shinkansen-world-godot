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

## 進捗(2026-05-30 時点)

**Phase 0〜2 + Phase 3-1〜3-5 + 2-4 + Phase 4 演出(一部)完了**。新幹線に乗れ、6 駅が立ち、8 種の動物がなかよしになり、星を集め、駅で電車が減速し、図鑑で発見状況を見られる。さらに Glow・星のきらきら/獲得バースト・なかよしハート・SL蒸気・UIボタンのぷにっと演出を追加。主要ループ「集める・出会う・乗る・探す」が一通り動く。次は Phase 3-6(ミッション)/ 音 / トゥーンシェーダー / 季節 / 自由アイデア。詳細は `changelog.md` 参照。
- 演出(Phase 4): Glow=Main の Environment、星きらきら/バースト=`stars.gd`、なかよしハート=`animal.gd._pop_heart`、SL蒸気=`train.gd._attach_steam`、UIバウンス=`touch_hud.gd._add_press_bounce`、リムライト=`assets/shaders/rim.gdshader`(animal/player)、ホタル=`fireflies.gd`(夜・Player子)、虹=`rainbow.gd`、ミッション=`mission_manager.gd`、効果音=`sound_fx.gd`(プロシージャル WAV)。Glow/リムライト/音の Web での挙動は要実機確認。
- 列車の車輪回転は負荷(約360個)で見送り中。
- スタート画面 `scenes/ui/TitleScreen.tscn`(title.gd)実装済み。「はじめる」押下で AudioContext 起動+フェードアウト。これで Web でも効果音が鳴る想定(実機要確認)。
- Phase 5 実装済み: BGM=`bgm.gd`(プロシージャル・ループ)、進捗保存=`save_system.gd`(user://save.json、GameState 直後に配置)、PWA=`export/web/manifest.json`+`web/template.html`(apple-touch・manifest link)。
- Phase 5 残り: 完全オフライン化(Service Worker キャッシュ。Export ダイアログで PWA ON or SW 追加)、親モード(音量・データリセット・PIN)。
- 順序の注意: GameState→SaveSystem を最前に。HUD に書く処理(ミッション)は call_deferred で HUD の _ready を待つ。効果音は _ready で prev を現在値に初期化して起動時の誤発火を防ぐ。
- 操作/見た目: 移動=D-pad・WASD/矢印。カメラは**固定追従**(`camera_rig.gd`、yaw0/pitch0.5。orbit は画面酔いするとのことで撤去)。プレイヤーは 3 頭身の運転士キャラ(`player.gd` でスクリプト生成、帽子・大きいうるうる目+キラキラ・ほっぺ・歩行アニメ)。Player.tscn は当たり判定のみ。
- `auto_capture.gd` 検証フック: MODE=AUTO_RIDE/AUTO_BEFRIEND/AUTO_BOOK、ViewMode=STATION/ANIMAL/STEAM。
- 進捗は `scripts/world/game_state.gd`(Main 直下、Autoload 不使用)が一元管理。`signal changed` で HUD カウンターと図鑑が更新。永続セーブは Phase 5。
- 星=`stars.gd`(近接獲得)、HUD カウンター/ずかんボタン=`touch_hud.gd`+`TouchHUD.tscn`、図鑑=`book.gd`+`BookOverlay.tscn`(.tres 走査でマスター化)、駅停車=`train.gd._station_slow_factor`、駅発見=`station_manager.gd`。
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
