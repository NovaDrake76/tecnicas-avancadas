shader_type spatial;
render_mode cull_disabled;

uniform sampler2D cloth : source_color;
uniform float wave = 1.0;

void vertex() {
	float free = UV.x;
	VERTEX.z += (sin(UV.x * 7.0 - TIME * 4.2) * 0.09 + sin(UV.y * 5.0 + TIME * 2.3) * 0.03) * free * wave;
	VERTEX.y += sin(UV.x * 5.0 - TIME * 3.1) * 0.035 * free * wave;
}

void fragment() {
	ALBEDO = texture(cloth, UV).rgb;
	ROUGHNESS = 0.92;
}
