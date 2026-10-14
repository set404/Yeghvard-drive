shader_type spatial;
// The land around the town out to ~100 km (tools/build_horizon.gd). Everything past
// near_reach is drawn closer to the camera than it really is, slid along the line
// of sight, so it fits inside the far plane yet looks the same size and shape.
// The haze is worked out from the real distance instead of the scene's fog.
render_mode world_vertex_coords, fog_disabled;

uniform float near_reach = 3500.0;
uniform float far_reach = 16000.0;
// A little bluer and darker than the sky at the horizon, so ridges stand out.
uniform vec3 haze_color : source_color = vec3(0.55, 0.63, 0.77);
// Haze per metre at the town's ground level; it thins out higher up. Within near_haze
// metres it matches the scene's fog (so the town's edge does not show), beyond that
// the air is clearer, as on a good autumn day.
uniform float near_haze = 4000.0;
uniform float near_density = 0.00005;
uniform float haze_density = 0.000004;
uniform float haze_height = 1000.0;
// Metres above sea level; mid-October snow sits on the highest peaks only.
uniform float snow_line = 3900.0;

varying vec3 true_pos;
varying float elevation;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	true_pos = VERTEX;
	elevation = UV.x;
	vec3 d = VERTEX - CAMERA_POSITION_WORLD;
	float r = length(d);
	if (r > near_reach) {
		float span = far_reach - near_reach;
		float drawn = near_reach + span * (1.0 - exp(-(r - near_reach) / span));
		VERTEX = CAMERA_POSITION_WORLD + d * (drawn / r);
	}
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float n = noise(true_pos.xz * 0.0015) * 0.6 + noise(true_pos.xz * 0.006) * 0.4;

	// Farmland in the valleys, dry grass on the slopes, bare rock up high.
	vec3 valley = vec3(0.47, 0.47, 0.31);
	vec3 steppe = vec3(0.55, 0.49, 0.34);
	vec3 alpine = vec3(0.44, 0.42, 0.30);
	vec3 rock = vec3(0.38, 0.34, 0.31);
	vec3 col = mix(valley, steppe, smoothstep(1000.0, 1400.0, elevation));
	col = mix(col, alpine, smoothstep(2000.0, 2600.0, elevation));
	col = mix(col, rock, smoothstep(2900.0, 3400.0, elevation));
	col = mix(col, rock * 0.8, 1.0 - smoothstep(0.55, 0.85, wn.y));
	col *= 0.85 + 0.3 * n;

	float snow = smoothstep(snow_line - 120.0, snow_line + 120.0, elevation + (n - 0.5) * 700.0);
	snow *= smoothstep(0.3, 0.6, wn.y);
	col = mix(col, vec3(1.0, 1.0, 1.02) * 1.15, snow);

	// Haze along the real line of sight: the air thins out exponentially with height,
	// so this is the mean of exp(-y / haze_height) between the two ends.
	vec3 d = true_pos - CAMERA_POSITION_WORLD;
	float y0 = max(CAMERA_POSITION_WORLD.y, -500.0);
	float y1 = max(true_pos.y, -500.0);
	float thin = abs(y1 - y0) < 1.0 ? exp(-y0 / haze_height)
			: haze_height * (exp(-y0 / haze_height) - exp(-y1 / haze_height)) / (y1 - y0);
	float dist = length(d);
	float depth = near_density * min(dist, near_haze) + haze_density * max(dist - near_haze, 0.0);
	float haze = 1.0 - exp(-depth * thin);

	ALBEDO = col * (1.0 - haze);
	EMISSION = haze_color * haze;
	ROUGHNESS = 1.0;
	SPECULAR = 0.2;
}
