shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// 湖の水面シェーダー。
// 子供向けの「ふわふわ波打つ水」を、Compatibility レンダラー(WebGL2)で
// 確実に動く範囲で表現する。半透明 + フレネルは試したが透けすぎたので、
// まずは不透明 + 頂点シフト波 + スペキュラ反射で「水らしさ」を出す。

uniform vec4 water_color    : source_color = vec4(0.42, 0.71, 0.94, 1.0);
uniform float wave_speed     : hint_range(0.0, 5.0) = 0.8;
uniform float wave_strength  : hint_range(0.0, 0.3) = 0.08;
uniform float wave_frequency : hint_range(0.1, 5.0) = 1.5;

void vertex() {
	float wx = sin(VERTEX.x * wave_frequency + TIME * wave_speed);
	float wz = cos(VERTEX.z * wave_frequency + TIME * wave_speed * 0.7);
	VERTEX.y += (wx + wz) * wave_strength;

	NORMAL = normalize(vec3(
		-cos(VERTEX.x * wave_frequency + TIME * wave_speed) * wave_frequency * wave_strength,
		1.0,
		sin(VERTEX.z * wave_frequency + TIME * wave_speed * 0.7) * wave_frequency * wave_strength
	));
}

void fragment() {
	ALBEDO = water_color.rgb;
	METALLIC = 0.2;
	ROUGHNESS = 0.15;
	SPECULAR = 0.85;
}
