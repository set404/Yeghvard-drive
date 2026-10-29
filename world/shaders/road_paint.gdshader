shader_type spatial;
render_mode cull_disabled;

// Plain asphalt and white paint laid over the roads (world/junction.gd,
// world/traffic_light.gd, world/crosswalk.gd). road.gdshader draws the road
// pulled towards the camera so the terrain does not show through; this pulls
// further still, by `layer`, so it is always drawn on top of the road: asphalt
// (layer 1) over the road's lane lines, paint (layer 2) over that.

uniform bool asphalt = false;
// The road's own colour (its vertex colour), for the asphalt.
uniform vec3 road_color = vec3(0.0353, 0.0353, 0.0392);
uniform vec3 paint_color : source_color = vec3(0.92, 0.92, 0.88);
uniform float layer = 2.0;

varying vec3 wpos;

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
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// As road.gdshader for its biggest roads (class 7), and a little more.
	vec4 view = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float dist = length(view.xyz);
	float pull = min((0.04 + 0.004 * dist) * (2.75 + 0.15 * layer) + 0.01 * layer, 0.6 * dist);
	view.xyz -= view.xyz / max(dist, 0.001) * pull;
	POSITION = PROJECTION_MATRIX * view;
}

void fragment() {
	// Lit the same from either side, whichever way its triangles were wound.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	if (asphalt) {
		// The same grain as road.gdshader, from where it lies, so it joins unseen.
		float n = noise(wpos.xz * 0.4) * 0.5 + noise(wpos.xz * 4.0) * 0.5;
		ALBEDO = road_color * (0.85 + 0.3 * n);
		ROUGHNESS = 0.92;
	} else {
		ALBEDO = paint_color;
		ROUGHNESS = 0.75;
	}
}
