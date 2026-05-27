# GODOT_NOTES — Godot 4 固有の技術メモ

Web Export(iPad Safari)で本気で動かすために知っておくべきこと。

## バージョン

- **Godot 4.3 以降推奨**(2024 年以降の Web Export 改善が大きい)
- 4.2 でも動くが、4.3 で WebGL2 サポートが安定
- 最新の 4.x 安定版を使う方針

## レンダラー選択

Godot 4 には 3 種類のレンダラーがあります:

| レンダラー | 用途 | Web Export | 機能 |
|-----------|------|------------|------|
| **Forward+** | デスクトップ・高品質 | ❌ 不可 | 全機能(SDFGI、Volumetric Fog 等) |
| **Mobile** | モバイルネイティブ | △ 一部 | 多くの機能 |
| **Compatibility** | Web、古い端末 | ✅ 標準 | 基本機能のみ |

**このプロジェクトでは Compatibility 一択**です。

`project.godot` での設定:
```
rendering/renderer/rendering_method="gl_compatibility"
rendering/renderer/rendering_method.mobile="gl_compatibility"
```

## Compatibility レンダラーで使える/使えない機能

### 使える ✅

- 基本 3D レンダリング(メッシュ、マテリアル、ライト)
- **PBR マテリアル**(`StandardMaterial3D`、`ORMTextureRect` 等)
- **DirectionalLight3D**(太陽光、標準シャドウ)
- **OmniLight3D**, **SpotLight3D**(動的、ただし制限あり)
- **環境光**(`Environment` リソース、`background`、`ambient_light`、`fog`)
- **GPUParticles3D**(花びら、紙吹雪、蒸気)
- **MultiMeshInstance3D**(大量オブジェクトの統合)
- **カスタムシェーダー**(`.gdshader` ファイル、Godot Shading Language)
- **AnimationPlayer**、**AnimationTree**
- **Path3D** + **PathFollow3D**(列車の線路追従)
- **Camera3D**(視点制御、ポストプロセス除く)
- **基本的な Tonemap**(Linear、ACES Filmic)

### 使えない ❌

- **SDFGI**(リアルタイムグローバルイルミネーション)
- **VoxelGI**
- **Volumetric Fog**(ボリュメトリック霧)
- **SSAO**(スクリーンスペースアンビエントオクルージョン)
- **SSR**(スクリーンスペース反射)
- **SSIL**(スクリーンスペース間接照明)
- **Bloom**(完全版、簡易版は別途実装可能)
- **Glow**(部分的に使える、効果は限定)

### 子供向けゲームでの代替戦略

ポストエフェクト系が使えなくても、以下で「リッチ感」は出せます:

1. **明るく彩度の高い配色** — ポストエフェクトに頼らない色彩設計
2. **カスタムシェーダー** — トゥーンシェーディング、リムライト、海面波シェーダー
3. **GPUParticles3D** — 桜の花びら、紙吹雪、星のキラキラ、蒸気
4. **Tween + AnimationPlayer** — モーション過剰演出
5. **エミッシブマテリアル** — 自発光で「キラキラ」を表現

実例:
- 星: `StandardMaterial3D` の `emission` を強めに設定 → 自発光で輝く
- 水面: `gdshader` で頂点シフト + フレネル反射 → 高度な見た目
- 桜: `GPUParticles3D` + `BillboardMode` → ふわふわ落ちる花びら

## Web Export の罠

### 1. COEP/COOP ヘッダー問題

Godot 4 の Web Export は **SharedArrayBuffer** を使ったマルチスレッド版が標準ですが、これには以下のヘッダーがサーバーから返ってくる必要があります:

```
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Opener-Policy: same-origin
```

- **Vercel**: `vercel.json` で設定可能 ✅
- **GitHub Pages**: 設定不可 ❌
- **Cloudflare Pages**: `_headers` ファイルで設定可能 ✅

**回避策**: エクスポート設定で `Threading > Thread Support: false` にすると、SharedArrayBuffer が不要になります。パフォーマンスは若干低下しますが、子供向けゲーム規模なら問題ありません。

### 2. ビルドサイズ

GDScript 版でも初回ロードは 15〜25MB 程度。iPad で初回起動時に時間がかかります。
- Service Worker でキャッシュすれば 2 回目以降は瞬時
- ローディング画面で待ち時間を演出(電車のアニメーション)

### 3. 起動時の AudioContext

iOS Safari は **AudioContext がユーザー操作後にしか開始できない**制約があります。
- タイトル画面の「スタート」ボタンタップで初期化
- Three.js 版で実装済みの方式を Godot でも踏襲

### 4. iPad のタッチ入力

`InputEventScreenTouch` と `InputEventScreenDrag` を使います:

```gdscript
func _input(event):
    if event is InputEventScreenTouch:
        if event.pressed:
            _on_touch_start(event.index, event.position)
        else:
            _on_touch_end(event.index)
    elif event is InputEventScreenDrag:
        _on_touch_drag(event.index, event.position, event.relative)
```

`event.index` が指の ID なので、マルチタッチも管理できます。

### 5. キャンバスサイズの動的調整

`100vh` 問題は HTML テンプレート側で対応:

```html
<!-- カスタム HTML シェル(エクスポート時に指定) -->
<style>
  html, body { 
    width: 100%; 
    height: 100dvh; /* dynamic viewport height */
    overflow: hidden;
  }
  canvas { width: 100%; height: 100%; }
</style>
```

Godot のエクスポート設定で「Custom HTML Shell」を指定し、カスタマイズした HTML を使う。

### 6. フォント

Web フォント(Mochiy Pop One、M PLUS Rounded 1c)は以下のどちらかで読み込む:

**A. Godot に同梱**(推奨)
- `assets/fonts/` に `.ttf` を配置
- `Theme` で適用
- ロード時に確実に表示される

**B. CSS で Web フォント**
- HTML 側で読み込み
- Godot 内では System Font として参照
- 初回起動時に未適用の瞬間あり

A の方が確実です。

## iOS Safari の制約

### Web Audio

- AudioContext は最初のタッチ後に初期化
- BGM のループは `AudioStreamPlayer` の `stream.loop = true` で OK
- 音量制御は Godot の AudioServer で

### フルスクリーン

iOS Safari は `requestFullscreen()` が iPad では効きません。
- 「ホーム画面に追加」した PWA は自動でフルスクリーン
- `apple-mobile-web-app-capable` メタタグ必須(HTML シェルに記述)

### スリープ防止

iPad は一定時間操作がないとスリープします。
- Wake Lock API は Safari iOS でサポート(2023〜)
- 効果音や BGM が鳴っていれば自動スリープしにくい

## パフォーマンス最適化

### MultiMeshInstance3D

木 150 本、花 200 個、雲 18 個など、同じメッシュを大量配置する場合は必須:

```gdscript
extends MultiMeshInstance3D

func _ready():
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.instance_count = 150
    for i in range(150):
        var t = Transform3D()
        t.origin = Vector3(randf_range(-100, 100), 0, randf_range(-100, 100))
        multimesh.set_instance_transform(i, t)
```

これによりドローコールが大幅に削減されます。

### LOD(Level of Detail)

Godot 4 は自動 LOD があるが、子供向けではモデルが単純なので不要。

### Shadow Atlas

`DirectionalLight3D` のシャドウマップサイズを抑える:
```
shadow_atlas/size = 2048   # 4096 から 2048 に
```

iPad のメモリ制約を考慮。

### テクスチャサイズ

- UI テクスチャは 2048×2048 以下
- 3D モデル用テクスチャは 1024×1024 以下
- 圧縮形式は Web では BPTC または WebP

## デバッグ

### Web Export デバッグ

ブラウザのコンソールに Godot のログが出ます。
`Project > Export > Web > Variant: Export with Debug` でビルドすると、より詳細なログとブレークポイント機能が使えます(ファイルサイズは大きくなる)。

### iPad 実機デバッグ

PC とブラウザを Safari 開発者ツールで接続:
1. iPad の Safari > 設定 > 詳細 > Web インスペクタを ON
2. Mac の Safari > 開発 > [iPad 名] でインスペクタを開く
3. Windows ユーザーは Mac を借りるか、`weinre` などの代替ツール

Windows のみで実機デバッグするのは難しい。コンソールログを画面に表示する仕組みを Godot 内に作っておくと便利。

## 既知の問題と回避策

### Issue 1: WebGL コンテキストロスト

iPad で別タブに切り替えると WebGL コンテキストが失われ、戻ったときに画面が真っ黒になる。
- 解決: シーン再起動の仕組みを作る
- 検出: JavaScript で `webglcontextlost` を監視 → Godot に通知

### Issue 2: 初回タッチで音が出ない

- 解決: スタートボタンの `_input` 内で `AudioServer.set_bus_volume_db(0, 0.0)` を呼ぶ
- これにより AudioContext が確実に開始

### Issue 3: メモリ不足でクラッシュ

iPad のメモリ制限は端末によって異なる(1GB〜)。
- 解決: テクスチャを最小限に、MultiMesh を活用、不要なノードは `queue_free()`

## 学習リソース

### 公式

- [Godot 公式ドキュメント](https://docs.godotengine.org/en/stable/)
- [Godot Web Export チュートリアル](https://docs.godotengine.org/en/stable/tutorials/platform/web/index.html)

### 日本語

- [Godot Engine 日本語コミュニティ](https://godotengine.org/community/)
- [@matnesis のチュートリアル](https://github.com/matnesis/Godot-tutorials)
- Qiita の Godot 4 タグ

### 動画

- GDQuest(英語、最高品質)
- KidsCanCode(英語、初心者向け)

### コミュニティ

- Godot Discord(英語が中心、日本語チャンネルあり)
- Reddit r/godot
