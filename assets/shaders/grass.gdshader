shader_type spatial;
render_mode cull_disabled;

// 草の房。MultiMesh で大量に生やし、頂点シェーダーで上部だけを風に揺らす。
// 下端(VERTEX.y=0)は固定、上端(=blade_height)ほど大きく横に揺れる。
// NORMAL を上向き固定にして地面と同じ陰影にする(統一感 + 夜は自然に暗くなる=怖くない)。
// Compatibility(WebGL2)で動く単純な vertex/fragment のみ。

uniform float blade_height = 0.6;
uniform float wind_speed = 1.6;
uniform float wind_strength = 0.12;
uniform vec4 base_color : source_color = vec4(0.30, 0.55, 0.24, 1.0);
uniform vec4 tip_color : source_color = vec4(0.55, 0.82, 0.40, 1.0);

varying float v_w;

void vertex() {
	float w = clamp(VERTEX.y / blade_height, 0.0, 1.0);
	v_w = w;
	vec3 inst = MODEL_MATRIX[3].xyz;                 // 株ごとの位置で位相をずらす
	float phase = TIME * wind_speed + inst.x * 0.2 + inst.z * 0.2;
	VERTEX.x += sin(phase) * wind_strength * w;       // 上ほど揺れる
	NORMAL = vec3(0.0, 1.0, 0.0);                     // 地面と同じく上向き
}

void fragment() {
	ALBEDO = mix(base_color.rgb, tip_color.rgb, v_w);
	ROUGHNESS = 0.95;
	METALLIC = 0.0;
}
