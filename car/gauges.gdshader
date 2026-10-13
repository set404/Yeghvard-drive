shader_type spatial;

// Instrument cluster of the W210 model. The dial texture has its needles painted
// in at rest; this blanks them out and draws live ones.
// All positions are in texture pixels (the dial texture is 512 x 512).

uniform sampler2D dial : source_color, filter_linear_mipmap;
uniform float speed_kmh = 0.0;
uniform float rpm = 800.0;
uniform float backlight = 0.7;

const float TEX = 512.0;
const vec2 SPEED_HUB = vec2(255.0, 178.0);
const vec2 SPEED_REST_TIP = vec2(110.0, 76.0);
const vec2 RPM_HUB = vec2(402.0, 398.0);
const vec2 RPM_REST_TIP = vec2(314.0, 338.0);
const vec3 NEEDLE_COLOR = vec3(0.72, 0.17, 0.02);

// Angles are measured in the texture, in degrees, growing from +U towards +V.
// Speedometer: 0 km/h at 215 degrees, 0.9 degrees per km/h, up to 280.
// Rev counter: 0 rpm at 221 degrees, 35 degrees per 1000 rpm, up to 7000.

float needle(vec2 p, vec2 hub, float angle_deg, float len) {
	float a = radians(angle_deg);
	vec2 dir = vec2(cos(a), sin(a));
	vec2 d = p - hub;
	float along = dot(d, dir);
	float across = abs(d.x * dir.y - d.y * dir.x);
	float half_width = mix(3.2, 1.2, clamp(along / len, 0.0, 1.0));
	return step(-10.0, along) * step(along, len) * (1.0 - smoothstep(half_width, half_width + 1.0, across));
}

float near_segment(vec2 p, vec2 a, vec2 b, float radius) {
	vec2 ab = b - a;
	float t = clamp(dot(p - a, ab) / dot(ab, ab), 0.0, 1.0);
	return 1.0 - smoothstep(radius, radius + 2.0, length(p - a - ab * t));
}

void fragment() {
	vec2 p = UV * TEX;
	vec3 col = texture(dial, UV).rgb;
	col *= 1.0 - max(near_segment(p, SPEED_HUB, SPEED_REST_TIP, 5.0), near_segment(p, RPM_HUB, RPM_REST_TIP, 9.0));

	float live = max(
		needle(p, SPEED_HUB, 215.0 - 0.9 * clamp(speed_kmh, 0.0, 280.0), 150.0),
		needle(p, RPM_HUB, 221.0 - 0.035 * clamp(rpm, 0.0, 7200.0), 84.0));
	col = mix(col, NEEDLE_COLOR, live);
	float cap = max(1.0 - smoothstep(13.0, 14.5, length(p - SPEED_HUB)), 1.0 - smoothstep(10.0, 11.5, length(p - RPM_HUB)));
	col = mix(col, vec3(0.02), cap);

	ALBEDO = col;
	EMISSION = col * backlight;
	ROUGHNESS = 0.6;
}
