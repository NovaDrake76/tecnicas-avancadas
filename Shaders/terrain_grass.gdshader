shader_type spatial;

// grassy ground for the generated terrain.
// the close-up turf is done HERE, in one material, rather than with a hundred thousand grass
// instances. that is how shipped games do it: the ground is textured, and real blades are a
// thin scatter near the camera on top of it.

uniform vec3 grass_low : source_color = vec3(0.15, 0.30, 0.10);
uniform vec3 grass_high : source_color = vec3(0.38, 0.52, 0.19);
uniform vec3 dirt : source_color = vec3(0.28, 0.22, 0.14);
uniform vec3 rock : source_color = vec3(0.33, 0.33, 0.30);

// patch is the whole field, clump is about half a metre, blade is the turf you stand on.
uniform float patch_scale = 0.03;
uniform float clump_scale = 0.4;
uniform float blade_scale = 9.0;
uniform float clump_amount : hint_range(0.0, 1.0) = 0.35;
uniform float blade_amount : hint_range(0.0, 1.0) = 0.5;
// the blade layer is finer than a pixel at range, so it is faded out or the ground shimmers.
uniform float blade_near = 6.0;
uniform float blade_far = 40.0;

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

	// the field, broad drifts of lighter and darker green
	float patch = fbm(p * patch_scale);
	vec3 col = mix(grass_low, grass_high, clamp(patch * 1.4, 0.0, 1.0));

	// clumps, so the ground is never one flat wash of colour
	float clump = value_noise(p * clump_scale);
	col *= 1.0 - clump_amount * 0.5 + clump * clump_amount;

	// the turf itself, roughly a blade every ten centimetres, faded out with distance
	float rough = 0.95;
	float fade = 1.0 - smoothstep(blade_near, blade_far, length(VERTEX));
	if (fade > 0.001) {
		float blades = value_noise(p * blade_scale);
		float fine = value_noise(p * blade_scale * 2.7 + vec2(13.0, 5.0));
		float turf = mix(blades, fine, 0.4);
		float amount = blade_amount * fade;
		col *= 1.0 - amount * 0.5 + turf * amount;
		// the darker gaps between blades are what reads as grass rather than paint
		col = mix(col, grass_low * 0.75, clamp((1.0 - turf) * 0.4 * fade, 0.0, 1.0));
		rough = 0.85 + turf * 0.14;
	}

	// steep ground loses its grass, which stops the hills reading as painted cones
	float up = clamp(world_normal.y, 0.0, 1.0);
	col = mix(dirt, col, smoothstep(slope_rock, slope_dirt, up));
	col = mix(rock, col, smoothstep(slope_rock - 0.18, slope_rock, up));

	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.05;
}
