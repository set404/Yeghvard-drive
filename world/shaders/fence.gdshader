shader_type spatial;
// Walls and fences round house plots (tools/build_world.gd, _build_fences).
// UV is (metres along the fence, metres above its foot); UV2.x is the kind:
// 0 stone blocks, 1 corrugated metal sheet, 2 chain-link mesh, 3 plain metal (posts).
render_mode cull_disabled;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float kind = UV2.x;
	vec3 col = COLOR.rgb;
	float fw = fwidth(UV.x) + fwidth(UV.y);
	float rough = 0.92;
	float metal = 0.0;
	if (kind < 0.5) {
		// Blocks 0.6 m long in courses 0.35 m high, every other course half a block on.
		float row = floor(UV.y / 0.35);
		float x = UV.x / 0.6 + row * 0.5;
		vec2 f = fract(vec2(x, UV.y / 0.35));
		col *= 0.84 + 0.3 * hash(vec2(floor(x), row));
		float edge = min(min(f.x, 1.0 - f.x) * 0.6, min(f.y, 1.0 - f.y) * 0.35);
		float mortar = 1.0 - smoothstep(0.01, 0.01 + fw, edge);
		col = mix(col, col * 0.6 + 0.04, mortar * (1.0 - smoothstep(0.03, 0.1, fw)));
	} else if (kind < 1.5) {
		// Ribs every 11 cm, faded out where they would shimmer; a little rust low down.
		float rib = 0.5 + 0.5 * sin(UV.x * TAU / 0.11);
		col *= mix(0.8 + 0.28 * rib, 0.94, smoothstep(0.02, 0.06, fw));
		float rust = smoothstep(0.75, 1.0, hash(vec2(floor(UV.x / 0.35), 3.0))) * (1.0 - smoothstep(0.0, 1.4, UV.y));
		col = mix(col, vec3(0.3, 0.14, 0.06), rust * 0.5);
		rough = 0.6;
		metal = 0.25;
	} else if (kind < 2.5) {
		// Diamonds 6 cm across. Far off, where single wires are under a pixel, drop
		// a share of the pixels instead so the mesh reads as a see-through grey.
		vec2 g = vec2(UV.x + UV.y, UV.x - UV.y) / 0.06;
		vec2 f = min(fract(g), 1.0 - fract(g));
		float d = min(f.x, f.y);
		float cells_per_px = fw / 0.06;
		if (cells_per_px < 0.35) {
			if (d > 0.07 + cells_per_px) {
				discard;
			}
		} else if (hash(floor(FRAGCOORD.xy)) > 0.3) {
			discard;
		}
		rough = 0.5;
		metal = 0.6;
	} else {
		rough = 0.6;
		metal = 0.4;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metal;
}
