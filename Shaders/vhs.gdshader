shader_type canvas_item;

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform float grain : hint_range(0.0, 1.0) = 0.10;
uniform float bleed : hint_range(0.0, 0.02) = 0.0022;
uniform float scanline : hint_range(0.0, 1.0) = 0.16;
uniform float vignette : hint_range(0.0, 1.0) = 0.42;
uniform float wobble : hint_range(0.0, 0.01) = 0.0012;
uniform float tracking : hint_range(0.0, 1.0) = 0.0;
uniform float band_y = 2.0;
uniform float band_height = 0.035;
uniform float wash : hint_range(0.0, 1.0) = 0.28;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float line = floor(uv.y / SCREEN_PIXEL_SIZE.y);
	float jitter = (hash(vec2(line, floor(TIME * 24.0))) - 0.5);
	uv.x += sin(uv.y * 60.0 + TIME * 5.0) * wobble * (1.0 + tracking * 6.0);
	uv.x += jitter * wobble * 4.0 * tracking;
	float band = 1.0 - smoothstep(0.0, band_height, abs(uv.y - band_y));
	uv.x += band * (0.012 + tracking * 0.05) * jitter * 3.0;
	uv.y += tracking * 0.02 * sin(TIME * 40.0 + uv.y * 30.0);
	float r = texture(screen, uv + vec2(bleed, 0.0)).r;
	float g = texture(screen, uv).g;
	float b = texture(screen, uv - vec2(bleed, 0.0)).b;
	vec3 col = vec3(r, g, b);
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(lum), wash) * 0.92 + vec3(0.035, 0.03, 0.04);
	col *= 1.0 - scanline * (0.5 + 0.5 * sin(line * 3.14159));
	col += (hash(uv * 900.0 + vec2(TIME * 7.0, TIME * 3.0)) - 0.5) * grain;
	float snow = hash(vec2(line * 0.5, floor(TIME * 60.0)));
	col = mix(col, vec3(snow * 0.8 + 0.1), band * (0.35 + tracking * 0.5));
	col = mix(col, vec3(snow), tracking * tracking * 0.35);
	float d = distance(uv, vec2(0.5));
	col *= 1.0 - vignette * d * d * 2.2;
	COLOR = vec4(col, 1.0);
}
