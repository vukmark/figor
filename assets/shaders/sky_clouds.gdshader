shader_type sky;

#include "res://assets/shaders/noise_fbm.gdshaderinc"

// Plane-projected 2D noise clouds, not a raymarched volumetric — EYEDIR is
// projected onto a flat plane at cloud_height and sampled with fbm, same
// "cheap approximation, not a real 3D volume" tradeoff ArenaTerrain's own
// vertex-color height gradient makes. Chosen over a cloud texture/panorama
// since no such asset exists in this project (Kenney packs only), and this
// needs no texture at all — every peer renders byte-identical clouds from
// the same TIME uniform with no synced state required.
uniform float cloud_height : hint_range(50.0, 2000.0) = 400.0;
uniform float cloud_scale : hint_range(0.0005, 0.02) = 0.0022;
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.72;
// World-units/second wind speed (not a noise-space rate) — apply cloud_scale
// to the whole position+wind sum, not to EYEDIR alone, or wind ends up in
// different units than the position term and either barely moves or races
// past in seconds depending on cloud_scale (this bit us once already: the
// old wind was added post-scale, which read as fast, flickery motion since
// a "speed" of ~1 was actually crossing most of a noise cycle every second).
uniform float cloud_wind_speed : hint_range(0.0, 20.0) = 4.0;
uniform vec3 sky_top_color : source_color = vec3(0.2, 0.42, 0.82);
uniform vec3 sky_horizon_color : source_color = vec3(0.78, 0.82, 0.85);
uniform vec3 cloud_color_light : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_color_shadow : source_color = vec3(0.62, 0.6, 0.65);
// Zenith color looking straight down, mirroring sky_top_color looking
// straight up — there's no real ground in this game (floating islands over
// a void), so looking down should still read as sky/cloud, not a flat
// dirt-colored fill. Kept separate from sky_top_color rather than reusing
// it so the down-view can stay a touch darker/hazier for depth if wanted.
uniform vec3 void_color : source_color = vec3(0.35, 0.45, 0.6);

// Shared by both the upward and downward hemisphere — same cloud band,
// mirrored, so the game reads as "floating island surrounded by clouds in
// every direction" rather than clouds up top and a flat void below.
void sky() {
	float horizon_t = clamp(1.0 - abs(EYEDIR.y) * 2.5, 0.0, 1.0);
	vec3 zenith_color = EYEDIR.y >= 0.0 ? sky_top_color : void_color;
	vec3 base_sky = mix(zenith_color, sky_horizon_color, pow(horizon_t, 1.3));

	float abs_y = max(abs(EYEDIR.y), 0.01);
	float t = cloud_height / abs_y;
	vec2 wind_world = vec2(TIME * cloud_wind_speed, TIME * cloud_wind_speed * 0.6);
	vec2 cloud_uv = (EYEDIR.xz * t + wind_world) * cloud_scale;

	// Two scales combined: a slow, large-scale "coverage mass" (big cumulus
	// silhouettes, matching the reference image's huge cloud banks) eroded
	// by a faster, finer detail pass (wispy edges) — a single fbm frequency
	// alone read as either "all big blobs" or "all fine texture," never
	// both at once the way real cloud banks do.
	float macro = fbm(cloud_uv * 0.22, 4);
	float detail = fbm(cloud_uv * 1.4 - wind_world * cloud_scale * 0.5, 4);
	float n = mix(macro, detail, 0.25);
	float density = smoothstep(1.0 - cloud_coverage, 1.0, n);
	// Fades clouds out right at the zenith/nadir and right at the horizon so
	// they read as a band filling most of the sky (matching the reference
	// image) rather than a flat dome all the way up/down.
	density *= smoothstep(0.0, 0.08, abs_y) * smoothstep(1.0, 0.55, abs_y);

	float shade_n = fbm(cloud_uv * 1.7 + vec2(5.2, 1.3), 3);
	vec3 cloud_col = mix(cloud_color_shadow, cloud_color_light, shade_n);
	if (LIGHT0_ENABLED) {
		// Wide, strong sunlit brightening (low exponent, high multiplier) —
		// the reference image's clouds are lit by the sun across most of
		// their visible mass, not just a small hard hotspot.
		float sun_dot = clamp(dot(EYEDIR, LIGHT0_DIRECTION), 0.0, 1.0);
		cloud_col += LIGHT0_COLOR * pow(sun_dot, 3.0) * 1.4;
		// Warm horizon glow toward the sun, the way a low sun tints an
		// entire cloud bank, not just a small hotspot — reference image's
		// warm cream/pink cloud tones came from exactly this.
		float horizon_glow = pow(horizon_t, 2.0) * clamp(dot(normalize(vec3(EYEDIR.x, 0.0, EYEDIR.z)), normalize(vec3(LIGHT0_DIRECTION.x, 0.0, LIGHT0_DIRECTION.z))), 0.0, 1.0);
		base_sky = mix(base_sky, LIGHT0_COLOR, horizon_glow * 0.35);
		cloud_col = mix(cloud_col, LIGHT0_COLOR * 1.3, horizon_glow * 0.5);
	}

	COLOR = mix(base_sky, cloud_col, density);
}
