shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// 子供向けのやさしいリムライト。
// 物体の輪郭(視線に対して斜めの面)が rim_color で光り、
// Glow と相まって「ふんわり光る」可愛い見た目になる。
// 色は albedo uniform で受けるので、1 つのシェーダーを動物・キャラに使い回せる。

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 1.0, 0.95, 1.0);
uniform float rim_power : hint_range(0.5, 6.0) = 2.5;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.5;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.85;

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness_val;
	METALLIC = 0.0;
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
	EMISSION = rim_color.rgb * rim * rim_strength;
}
