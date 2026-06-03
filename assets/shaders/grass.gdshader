shader_type spatial;
render_mode cull_disabled;

// 草の房。MultiMesh で大量に生やし、頂点シェーダーで上部だけを風に揺らす。
// メッシュは X 字クロス(2枚直交)なので横からも見えて立体的=リアル。
// 下端(VERTEX.y=0)は固定、上端(=blade_height)ほど大きく揺れる。
// 株ごとに緑の濃淡をずらして「まんべんなく自然に生えた」見た目に。
// NORMAL を上向き固定にして地面と同じ陰影にする(統一感 + 夜は自然に暗くなる=怖くない)。
// Compatibility(WebGL2)で動く単純な vertex/fragment のみ。

uniform float blade_height = 0.6;
uniform float wind_speed = 1.6;
uniform float wind_strength = 0.12;
uniform vec4 base_color : source_color = vec4(0.22, 0.42, 0.16, 1.0);  // 根元=濃い緑
uniform vec4 tip_color : source_color = vec4(0.56, 0.83, 0.41, 1.0);   // 先端=明るい緑
uniform float color_variation = 0.16;  // 株ごとの濃淡の幅

varying float v_w;
varying float v_tint;

// 株ごとに 0..1 の安定した乱数(位置から)
float hash12(vec2 p) {
	return fract(sin(dot(p, vec2(41.31, 289.17))) * 43758.5453);
}

void vertex() {
	float w = clamp(VERTEX.y / blade_height, 0.0, 1.0);
	v_w = w;
	vec3 inst = MODEL_MATRIX[3].xyz;                 // 株ごとの位置
	v_tint = hash12(inst.xz);
	float phase = TIME * wind_speed + inst.x * 0.2 + inst.z * 0.2;
	// 2 方向にゆらして自然な風に(上ほど大きく揺れる)
	VERTEX.x += sin(phase) * wind_strength * w;
	VERTEX.z += cos(phase * 0.8) * wind_strength * 0.6 * w;
	NORMAL = vec3(0.0, 1.0, 0.0);                    // 地面と同じく上向き
}

void fragment() {
	vec3 col = mix(base_color.rgb, tip_color.rgb, v_w);
	// 株ごとに緑の濃淡をずらす(まだら=リアル)
	col *= (1.0 - color_variation) + color_variation * 2.0 * v_tint;
	ALBEDO = col;
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
