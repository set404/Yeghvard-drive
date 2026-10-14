shader_type spatial;
render_mode cull_disabled;

// Instrument cluster of the Land Cruiser. The dial texture is painted by
// tools/build_car.gd (see _lc80_draw_dial) without the two big needles and with
// the turn arrows dark; this draws the needles and lights the arrows. The fuel
// gauge's needle is painted in at 0.7 full; this blanks it and draws a live one.
// All positions are in texture pixels (the dial texture is 1280 x 512).

uniform sampler2D dial : source_color, filter_linear_mipmap;
uniform float speed_kmh = 0.0;
uniform float rpm = 800.0;
uniform float signal_left = 0.0;
uniform float signal_right = 0.0;
uniform float fuel = 0.7;
uniform float backlight = 0.7;

const vec2 TEX = vec2(1280.0, 512.0);
const vec2 RPM_HUB = vec2(397.0, 280.0);
const vec2 SPEED_HUB = vec2(883.0, 280.0);
const vec2 ARROW_LEFT = vec2(569.0, 66.0);
const vec2 ARROW_RIGHT = vec2(711.0, 66.0);
const vec2 ARROW_HALF = vec2(34.0, 28.0);
const vec2 FUEL_HUB = vec2(100.0, 310.0);
const vec3 NEEDLE_COLOR = vec3(0.85, 0.2, 0.03);

// Angles are in degrees, anticlockwise from the right as the driver sees the dial.
// Both dials start at 210 degrees and sweep 240 clockwise:
// the speedometer over 200 km/h, the rev counter over 7000 rpm.
// The fuel gauge runs from E at 140 degrees to F at 40.

float needle(vec2 p, vec2 hub, float angle_deg, float len) {
	float a = radians(angle_deg);
	vec2 dir = vec2(cos(a), -sin(a));
	vec2 d = p - hub;
	float along = dot(d, dir);
	float across = abs(d.x * dir.y - d.y * dir.x);
	float half_width = mix(5.0, 1.8, clamp(along / len, 0.0, 1.0));
	return step(-24.0, along) * step(along, len) * (1.0 - smoothstep(half_width, half_width + 1.0, across));
}

float inside(vec2 p, vec2 centre, vec2 half_size) {
	vec2 d = abs(p - centre);
	return step(d.x, half_size.x) * step(d.y, half_size.y);
}

void fragment() {
	vec2 p = UV * TEX;
	vec3 col = texture(dial, UV).rgb;
	// Blank the painted fuel needle (it stops short of the scale's ticks).
	vec2 painted = vec2(cos(radians(70.0)), -sin(radians(70.0)));
	vec2 fd = p - FUEL_HUB;
	float fa = clamp(dot(fd, painted), 0.0, 72.0);
	col = mix(col, vec3(0.012, 0.012, 0.016), 1.0 - smoothstep(4.0, 5.5, length(fd - painted * fa)));

	float live = max(max(
		needle(p, SPEED_HUB, 210.0 - 1.2 * clamp(speed_kmh, 0.0, 200.0), 182.0),
		needle(p, RPM_HUB, 210.0 - 240.0 / 7000.0 * clamp(rpm, 0.0, 7000.0), 182.0)),
		needle(p, FUEL_HUB, 140.0 - 100.0 * clamp(fuel, 0.0, 1.0), 70.0));
	col = mix(col, NEEDLE_COLOR, live);
	float cap = max(1.0 - smoothstep(19.0, 20.5, length(p - SPEED_HUB)), 1.0 - smoothstep(19.0, 20.5, length(p - RPM_HUB)));
	cap = max(cap, 1.0 - smoothstep(9.0, 10.5, length(p - FUEL_HUB)));
	col = mix(col, vec3(0.03), cap);

	float lit = max(inside(p, ARROW_LEFT, ARROW_HALF) * signal_left, inside(p, ARROW_RIGHT, ARROW_HALF) * signal_right);

	ALBEDO = col;
	EMISSION = col * (backlight + 9.0 * lit);
	ROUGHNESS = 0.6;
}
