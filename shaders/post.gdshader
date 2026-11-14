shader_type canvas_item;
// 2004 consumer-TV look for the 512x384 game image: composite softness, a hair of
// chroma offset, 16-bit-framebuffer dither, faint scanlines, gentle vignette.
// Everything is subtle and scaled by `strength` (0 = untouched).

uniform float time_s = 0.0;
uniform float strength = 1.0;
uniform vec2 src_size = vec2(512.0, 384.0);

// 2x2 / 4x4 ordered Bayer threshold in [0, 1), from integer pixel coords.
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(a * 0.5) * 0.25 + bayer2(a);
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	float s = clamp(strength, 0.0, 2.0);
	vec2 uv = UV;
	float px = 1.0 / src_size.x;

	// 1. horizontal composite softness (3 taps, ~0.6 source px)
	vec2 soft = vec2(0.6 * px * s, 0.0);
	vec3 col = texture(TEXTURE, uv).rgb * 0.5
		+ texture(TEXTURE, uv - soft).rgb * 0.25
		+ texture(TEXTURE, uv + soft).rgb * 0.25;

	// 2. tiny chroma offset: red and blue pulled +-0.35 source px
	vec2 ca = vec2(0.35 * px * s, 0.0);
	float r_shift = texture(TEXTURE, uv - ca).r;
	float b_shift = texture(TEXTURE, uv + ca).b;
	col.r = mix(col.r, r_shift, 0.6);
	col.b = mix(col.b, b_shift, 0.6);

	// 6a. black-level lift and a mild warm/green cast in the shadows (whites stay neutral)
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	float shadow = 1.0 - smoothstep(0.0, 0.45, lum);
	float lift = 0.022 * s;
	col = col * (1.0 - lift) + lift * vec3(1.0, 1.0, 0.86);
	col *= mix(vec3(1.0), vec3(1.025, 1.04, 0.95), shadow * min(s, 1.0));

	// 4. faint scanlines aligned to source rows + interlace-like field flicker
	vec2 spx = floor(uv * src_size);
	float fy = fract(uv.y * src_size.y);
	float edge = abs(fy - 0.5) * 2.0;
	float scan = 1.0 - 0.05 * s * edge * edge;
	float field = mod(floor(time_s * 60.0), 2.0);
	float flick = 1.0 - 0.015 * s * mod(spx.y + field, 2.0);
	col *= scan * flick;

	// 5. gentle vignette (about 14% at the corners)
	vec2 d = uv - 0.5;
	d.x *= 1.06;
	col *= 1.0 - 0.14 * s * smoothstep(0.25, 0.74, length(d));

	// 6b. faint animated noise (+-1.2%)
	float frame = mod(floor(time_s * 30.0), 61.0);
	float n = hash12(spx + vec2(frame * 17.0, frame * 9.0)) - 0.5;
	col += vec3(n * 0.024 * s);

	// 3. ordered 4x4 dither on source pixels, quantised to 6 bits per channel
	float levels = 63.0;
	float th = bayer4(spx);
	vec3 q = floor(clamp(col, 0.0, 1.0) * levels + th) / levels;
	col = mix(col, q, clamp(s, 0.0, 1.0));

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
