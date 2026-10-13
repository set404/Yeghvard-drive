shader_type spatial;

// COLOR.rgb: surface colour. COLOR.a * 16 = road class (0..7), plus 8 when the road has lane markings.
// UV.x: 0..1 across the road, UV.y: metres along it.
// UV2.x: road width in metres, UV2.y: lane count, negative for a one-way carriageway.

const float EDGE_INSET = 0.35;
const float LINE_HALF = 0.07;

varying vec3 wpos;
varying float marked;

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

float stripe(float dist) {
	return 1.0 - smoothstep(LINE_HALF, LINE_HALF + 0.04, dist);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float code = round(COLOR.a * 16.0);
	marked = step(7.5, code);
	float road_class = code - 8.0 * marked;
	// The road lies only centimetres above the ground. Draw it a little nearer the
	// camera along the line of sight, which leaves it in the same place on screen
	// but stops the terrain showing through; more so far away, and for bigger roads.
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = length(view.xyz);
	float pull = min((0.04 + 0.004 * dist) * (1.0 + 0.25 * road_class), 0.5 * dist);
	view.xyz -= view.xyz / max(dist, 0.001) * pull;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	float n = noise(wpos.xz * 0.4) * 0.5 + noise(wpos.xz * 4.0) * 0.5;
	vec3 col = COLOR.rgb * (0.85 + 0.3 * n);
	if (marked > 0.5) {
		float lanes = max(1.0, round(abs(UV2.y)));
		bool one_way = UV2.y < 0.0;
		float half_w = UV2.x * 0.5 - EDGE_INSET;
		float x = (UV.x - 0.5) * UV2.x;
		float lane_w = 2.0 * half_w / lanes;

		// Solid line along each edge.
		float paint = stripe(abs(abs(x) - half_w));

		// Dashed line between neighbouring lanes.
		float boundary = round((x + half_w) / lane_w);
		float dist = abs(x + half_w - boundary * lane_w);
		float dash = step(fract(UV.y / 9.0), 0.4);
		bool inner = boundary > 0.5 && boundary < lanes - 0.5;
		bool centre = !one_way && abs(boundary * 2.0 - lanes) < 0.1;
		if (inner && !(centre && lanes > 2.5)) {
			paint = max(paint, stripe(dist) * dash);
		}
		// Four lanes or more: double solid line between the two directions.
		if (centre && lanes > 2.5) {
			paint = max(paint, stripe(abs(dist - 0.14)));
		}
		col = mix(col, vec3(0.75), paint * 0.85);
	}
	ALBEDO = col;
	ROUGHNESS = 0.92;
}
