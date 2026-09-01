shader_type spatial;

// grassy ground for the generated terrain.
// two greens broken up by noise, with dirt showing through wherever the slope gets steep.

uniform vec3 grass_low : source_color = vec3(0.16, 0.31, 0.11);
uniform vec3 grass_high : source_color = vec3(0.35, 0.47, 0.18);
uniform vec3 dirt : source_color = vec3(0.28, 0.22, 0.14);
uniform vec3 rock : source_color = vec3(0.33, 0.33, 0.30);

uniform float patch_scale = 0.035;
uniform float detail_scale = 0.55;
uniform float detail_amount : hint_range(0.0, 1.0) = 0.5;
// blade scale break-up, this is what stops close ground reading as flat paint.
uniform float blade_scale = 3.5;
uniform float blade_amount : hint_range(0.0, 1.0) = 0.3;
// cos of the angle past which grass gives way to dirt.
uniform float slope_dirt : hint_range(0.0, 1.0) = 0.82;
uniform float slope_rock : hint_range(0.0, 1.0) = 0.62;

varying vec3 world_pos;
varying vec3 world_normal;


float hash(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}


float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}


float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amp;
		p = p * 2.03 + vec2(7.1, 3.7);
		amp *= 0.5;
	}
	return total;
}


void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	vec2 p = world_pos.xz;

	float patch = fbm(p * patch_scale);
	vec3 col = mix(grass_low, grass_high, clamp(patch * 1.4, 0.0, 1.0));

	// a fine break-up so a hillside is never one flat wash of colour.
	float detail = value_noise(p * detail_scale);
	col *= 1.0 - detail_amount * 0.5 + detail * detail_amount;

	// and a blade-sized layer on top, which is what the eye reads as grass up close.
	float blades = value_noise(p * blade_scale);
	col *= 1.0 - blade_amount * 0.5 + blades * blade_amount;
	col = mix(col, grass_low, clamp((1.0 - blades) * 0.35, 0.0, 1.0));

	// steep ground loses its grass, which is what stops the hills reading as painted cones.
	float up = clamp(world_normal.y, 0.0, 1.0);
	col = mix(dirt, col, smoothstep(slope_rock, slope_dirt, up));
	col = mix(rock, col, smoothstep(slope_rock - 0.18, slope_rock, up));

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.05;
}
