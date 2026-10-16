extends RefCounted
## Player options: display, graphics and sound. Saved to user://settings.cfg and
## applied to the window, the viewport and the world in main.tscn.

const PATH := "user://settings.cfg"

const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra", "Custom"]
const CUSTOM := 4
const AA_NAMES := ["Off", "FXAA", "MSAA 2x", "MSAA 4x"]
const SHADOW_NAMES := ["Off", "Low", "Medium", "High"]
const FPS_NAMES := ["30", "60", "120", "Unlimited"]
const FPS_VALUES := [30, 60, 120, 0]

## What each quality preset sets. Medium is the default.
const PRESETS := [
	{"render_scale": 0.6, "aa": 0, "shadows": 1, "ssao": false, "ssil": false, "glow": false},
	{"render_scale": 0.75, "aa": 1, "shadows": 2, "ssao": false, "ssil": false, "glow": true},
	{"render_scale": 1.0, "aa": 2, "shadows": 3, "ssao": true, "ssil": false, "glow": true},
	{"render_scale": 1.0, "aa": 3, "shadows": 3, "ssao": true, "ssil": true, "glow": true},
]
## Shadow atlas size and how far the sun casts shadows, per shadow level.
const SHADOW_ATLAS := [0, 2048, 4096, 8192]
const SHADOW_DISTANCE := [0.0, 80.0, 150.0, 250.0]

var fullscreen := false
var vsync := true
var max_fps := 1
var quality := 1
var render_scale := 0.75
var aa := 1
var shadows := 2
var ssao := false
var ssil := false
var glow := true
var volume := 0.8


func load_file() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	for key in _keys():
		set(key, cfg.get_value("settings", key, get(key)))


func save_file() -> void:
	var cfg := ConfigFile.new()
	for key in _keys():
		cfg.set_value("settings", key, get(key))
	cfg.save(PATH)


## Switches to a preset; any graphics change after that makes it Custom.
func use_preset(index: int) -> void:
	quality = index
	if index == CUSTOM:
		return
	for key in PRESETS[index]:
		set(key, PRESETS[index][key])


func apply_window() -> void:
	var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = FPS_VALUES[max_fps]
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


## Applies the graphics options to the window's viewport and to the world.
func apply_graphics(viewport: Viewport, main: Node) -> void:
	viewport.scaling_3d_scale = render_scale
	# FSR sharpens a lowered render scale; at full scale plain is cheaper.
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if render_scale < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if aa == 1 else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][aa]

	if shadows > 0:
		RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[shadows], true)
		RenderingServer.directional_soft_shadow_filter_set_quality(
			[RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_VERY_LOW,
			RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM][shadows])
	var sun := main.get_node_or_null("Sun") as DirectionalLight3D
	if sun:
		sun.shadow_enabled = shadows > 0
		sun.directional_shadow_max_distance = SHADOW_DISTANCE[shadows]

	var world_env := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env and world_env.environment:
		var env := world_env.environment
		env.ssao_enabled = ssao
		env.ssil_enabled = ssil
		env.glow_enabled = glow
		env.glow_intensity = 0.4
		env.glow_bloom = 0.05


func _keys() -> PackedStringArray:
	return ["fullscreen", "vsync", "max_fps", "quality", "render_scale", "aa", "shadows", "ssao", "ssil", "glow", "volume"]
