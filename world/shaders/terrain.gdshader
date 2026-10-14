shader_type spatial;

uniform sampler2D ground : source_color, filter_linear_mipmap, repeat_disable;
// How strongly the ground is broken into drier and greener patches.
uniform float patchiness : hint_range(0.0, 1.0) = 0.6;
// Bumps that catch the light up close (0 = smooth).
uniform float bumpiness : hint_range(0.0, 2.0) = 0.9;
// Steep ground shows bare basalt and earth.
uniform vec3 rock_color : source_color = vec3(0.36, 0.32, 0.28);
uniform vec3 dry_grass : source_color = vec3(0.66, 0.58, 0.36);
uniform vec3 green_grass : source_color = vec3(0.36, 0.45, 0.22);
uniform vec3 red_earth : source_color = vec3(0.52, 0.38, 0.28);

varying vec3 wpos;
varying vec3 wnrm;

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

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int k = 0; k < 4; k++) {
		s += noise(p) * a;
		p = p * 2.03 + vec2(17.3, 9.1);
		a *= 0.5;
	}
	return s / 0.9375;
}

// Small-scale ground relief: clods, ruts and tufts, in metres.
float relief(vec2 p) {
	return noise(p * 1.3) * 0.6 + noise(p * 4.1) * 0.3 + noise(p * 11.0) * 0.1;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 base = texture(ground, UV).rgb;
	float dist = length(VERTEX);

	// How "natural" this spot is: grey asphalt shoulders and yards stay as baked,
	// earthy and grassy ground takes on the patches.
	float sat = max(base.r, max(base.g, base.b)) - min(base.r, min(base.g, base.b));
	float natural = smoothstep(0.03, 0.12, sat);

	// Patches of dry grass, green grass and red earth at field scale (~40-250 m).
	float big = fbm(wpos.xz * 0.004 + vec2(3.1, 7.7));
	float mid = fbm(wpos.xz * 0.025);
	vec3 tint = mix(red_earth, dry_grass, smoothstep(0.30, 0.55, big));
	tint = mix(tint, green_grass, smoothstep(0.55, 0.78, mid * 0.6 + big * 0.4));
	// Keep the baked colour's brightness, take the hue from the patches.
	float lum = dot(base, vec3(0.299, 0.587, 0.114));
	float tlum = dot(tint, vec3(0.299, 0.587, 0.114));
	vec3 patched = tint * (lum / max(tlum, 0.01));
	vec3 col = mix(base, patched, patchiness * natural * 0.65);

	// Detail: the baked map is 4 m per pixel, so break it up up close.
	float n = noise(wpos.xz * 0.21) * 0.5 + noise(wpos.xz * 1.7) * 0.3 + noise(wpos.xz * 9.0) * 0.2;
	col *= 0.9 + 0.2 * n;
	// Speckle of grass tufts and stones that fades out before it can shimmer.
	float near = 1.0 - smoothstep(30.0, 120.0, dist);
	float tuft = smoothstep(0.55, 0.85, noise(wpos.xz * 1.3 + 5.0)) * natural;
	col = mix(col, col * vec3(0.72, 0.86, 0.55), tuft * near * 0.4);
	float stone = smoothstep(0.86, 0.95, noise(wpos.xz * 6.0 - 3.0));
	col = mix(col, col * 1.25, stone * near * 0.2);

	// Steep ground: bare rock and earth.
	float steep = 1.0 - smoothstep(0.80, 0.92, wnrm.y);
	col = mix(col, rock_color * (0.8 + 0.4 * n), steep * 0.75);

	ALBEDO = col;
	ROUGHNESS = 1.0;

	// Bumped normal from the relief, faded with distance.
	float fade = (1.0 - smoothstep(20.0, 90.0, dist)) * bumpiness;
	if (fade > 0.001) {
		float e = 0.08;
		float h0 = relief(wpos.xz);
		float hx = relief(wpos.xz + vec2(e, 0.0));
		float hz = relief(wpos.xz + vec2(0.0, e));
		vec3 g = vec3(h0 - hx, 0.0, h0 - hz) / e * 0.12 * fade;
		vec3 wn = normalize(wnrm + g);
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
	}
	// Grass in the shadow of a tuft: a touch of ambient occlusion.
	AO = 1.0 - tuft * near * 0.3;
	AO_LIGHT_AFFECT = 0.2;
}
