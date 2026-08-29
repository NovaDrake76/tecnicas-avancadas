shader_type sky;

uniform vec3 top_color : source_color = vec3(0.11, 0.32, 0.68);
uniform vec3 horizon_color : source_color = vec3(0.63, 0.77, 0.89);
uniform vec3 ground_color : source_color = vec3(0.20, 0.22, 0.24);
uniform vec3 cloud_color : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 cloud_shadow : source_color = vec3(0.52, 0.59, 0.70);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.40;
uniform float cloud_sharpness : hint_range(0.01, 0.6) = 0.25;
uniform float cloud_scale : hint_range(0.05, 4.0) = 0.6;
uniform float horizon_softness : hint_range(0.02, 0.6) = 0.15;
uniform float sun_glow : hint_range(0.0, 2.0) = 0.6;

float hash(vec2 p) {
	p = fract(p * vec2(233.34, 851.73));
	p += dot(p, p + 23.45);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		total += value_noise(p) * amp;
		p = p * 2.02 + vec2(3.7, 1.3);
		amp *= 0.5;
	}
	return total;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	if (dir.y < 0.0) {
		COLOR = mix(horizon_color, ground_color, clamp(-dir.y * 4.0, 0.0, 1.0));
	} else {
		float h = clamp(dir.y, 0.0, 1.0);
		vec3 base = mix(horizon_color, top_color, pow(h, 0.42));

		vec2 uv = (dir.xz / (dir.y + horizon_softness)) * cloud_scale;

		float shape = fbm(uv);
		shape = clamp((shape - 0.30) / 0.36, 0.0, 1.0);
		float detail = fbm(uv * 3.1 + vec2(17.0, 9.0));

		float low = smoothstep(0.0, 0.26, dir.y);

		float density = smoothstep(cloud_cover, cloud_cover + cloud_sharpness, shape);
		density *= low;

		vec3 cloud = mix(cloud_shadow, cloud_color, clamp(detail * 1.7, 0.0, 1.0));
		cloud = mix(horizon_color, cloud, low);
		COLOR = mix(base, cloud, density * 0.95);

		if (LIGHT0_ENABLED) {
			float s = max(dot(dir, -LIGHT0_DIRECTION), 0.0);
			COLOR += LIGHT0_COLOR * pow(s, 28.0) * sun_glow;
		}
	}
}
