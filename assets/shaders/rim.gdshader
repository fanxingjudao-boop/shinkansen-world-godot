shader_type spatial;
render_mode cull_back, specular_disabled;

// 子供向けのやさしいリムライト + トゥーン(セル)シェーディング。
// - 物体の輪郭(視線に対して斜めの面)が rim_color で光り、Glow と相まって
//   「ふんわり光る」可愛い見た目になる。
// - 光のあたり方を toon_steps 段に量子化して、絵本のようなセル調にする。
// 色は albedo uniform で受けるので、1 つのシェーダーを動物・キャラに使い回せる。
// ※ Compatibility(WebGL2)レンダラーで動く範囲の単純な light() 関数のみ使用。

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 0.95, 1.0);
uniform float rim_power : hint_range(0.5, 6.0) = 2.5;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.5;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.85;
uniform float toon_steps : hint_range(1.0, 5.0) = 3.0;     // 階調数(2〜3 が絵本っぽい)
uniform float toon_softness : hint_range(0.0, 0.25) = 0.06; // 段の境目のやわらかさ

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = rim_color.rgb * rim * rim_strength;
}

void light() {
	// ハーフランバート(陰を真っ黒にしない)を toon_steps 段に量子化してセル調に。
	float ndl = dot(normalize(NORMAL), normalize(LIGHT));
	float half_lambert = ndl * 0.5 + 0.5;     // 0..1
	float x = half_lambert * toon_steps;
	float lower = floor(x);
	float f = x - lower;                       // 段内の位置 0..1
	// 段の境目だけをほんの少しなめらかに(硬すぎるエッジを避ける=怖くない)
	float smooth_f = smoothstep(0.5 - toon_softness, 0.5 + toon_softness, f);
	float stepped = (lower + smooth_f) / toon_steps;
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * stepped;
}
