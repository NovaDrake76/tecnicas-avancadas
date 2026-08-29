shader_type spatial;

uniform vec3 base_color : source_color = vec3(0.27, 0.30, 0.28);
uniform vec3 minor_color : source_color = vec3(0.36, 0.40, 0.37);
uniform vec3 major_color : source_color = vec3(0.56, 0.61, 0.57);
uniform float minor_spacing = 1.0;
uniform float major_spacing = 10.0;
uniform float minor_fade_distance = 70.0;

float grid_mask(vec2 p, float spacing, float thickness) {
	vec2 coord = p / spacing;
	vec2 deriv = max(fwidth(coord), vec2(0.00001));
	vec2 g = abs(fract(coord - 0.5) - 0.5) / deriv;
	return 1.0 - min(min(g.x, g.y) / thickness, 1.0);
}

void fragment() {
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = world.xz;

	float dist = distance(world.xz, CAMERA_POSITION_WORLD.xz);
	float minor_fade = 1.0 - clamp(dist / minor_fade_distance, 0.0, 1.0);

	float minor = grid_mask(p, minor_spacing, 1.2) * minor_fade;
	float major = grid_mask(p, major_spacing, 1.6);

	vec3 col = base_color;
	col = mix(col, minor_color, minor * 0.7);
	col = mix(col, major_color, major);

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
