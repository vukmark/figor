// Shared by every cloud shader (sky dome + drifting cloud-layer planes) so
// the hash/noise/fbm math exists in exactly one place — cheap value-noise
// fbm, not a texture lookup, so no cloud texture asset is needed anywhere.
float fbm_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fbm_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float a = fbm_hash(i);
	float b = fbm_hash(i + vec2(1.0, 0.0));
	float c = fbm_hash(i + vec2(0.0, 1.0));
	float d = fbm_hash(i + vec2(1.0, 1.0));
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u.x) + (c - a) * u.y * (1.0 - u.x) + (d - b) * u.x * u.y;
}

// `octaves` as a param (not a fixed loop count) since the sky dome wants
// more detail (viewed close-up, fills the whole screen) than the far-off
// cloud-layer planes do (cheaper, and distance already hides the difference).
float fbm(vec2 p, int octaves) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		value += amp * fbm_noise(p);
		p *= 2.02;
		amp *= 0.5;
	}
	return value;
}
