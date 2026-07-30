shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, blend_mix;

#include "res://assets/shaders/noise_fbm.gdshaderinc"

// Per-pixel drifting cloud alpha on a big flat plane — replaces the old
// approach of baking cloud density into static per-vertex colors once at
// match start (which never moved). Several of these, at different heights/
// scales/speeds/tints, are what actually gives real parallax depth as the
// player moves — the sky dome shader (sky_clouds.gdshader) renders at
// infinite distance and can't provide that on its own.
uniform float noise_scale : hint_range(0.001, 0.05) = 0.006;
uniform float coverage : hint_range(0.0, 1.0) = 0.65;
// World-units/second (not a noise-space rate — see sky_clouds.gdshader's
// cloud_wind_speed doc comment for why that distinction matters: applying
// this before noise_scale, not after, is what keeps "speed" meaning an
// actual, tunable world speed instead of a fast/flickery noise-cycle rate).
uniform vec2 wind_speed = vec2(3.0, 1.5);
uniform vec3 cloud_tint : source_color = vec3(1.0, 1.0, 1.0);
// Blended in for the noise-shaded (non-lit-facing) side of each puff, same
// "fake volume via a second noise pass" trick sky_clouds.gdshader's own
// shade_n uses — gives lit tops/dim undersides without real light-direction
// math against a flat, unshaded plane.
uniform vec3 shadow_tint : source_color = vec3(0.72, 0.72, 0.78);
uniform float opacity : hint_range(0.0, 1.0) = 0.6;
// Radius (in local/world units, plane is built centered on origin) where
// the edge fade begins/ends — keeps the plane's own square boundary from
// ever being visible as a hard edge.
uniform float fade_start = 120.0;
uniform float fade_end = 200.0;

void fragment() {
	vec2 uv = (VERTEX.xz + wind_speed * TIME) * noise_scale;
	float n = fbm(uv, 4);
	float density = smoothstep(1.0 - coverage, 1.0, n);

	float shade_n = fbm(uv * 1.6 + vec2(9.1, 4.7), 3);
	vec3 color = mix(shadow_tint, cloud_tint, shade_n);

	float d = length(VERTEX.xz);
	float edge_fade = 1.0 - smoothstep(fade_start, fade_end, d);

	ALBEDO = color;
	ALPHA = density * opacity * edge_fade;
}
