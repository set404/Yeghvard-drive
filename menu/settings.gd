extends RefCounted
## Player options: display, graphics and sound. Saved to user://settings.cfg and
## applied to the window, the viewport and the world in main.tscn.

const PATH := "user://settings.cfg"

const QUALITY_NAMES := ["Low", "Medium", "High", "Ultra", "Custom"]
const CUSTOM := 4
const AA_NAMES := ["Off", "FXAA", "SMAA", "TAA", "MSAA 4x + SMAA", "MSAA 4x + TAA"]
const AA_FXAA := 1
const AA_SMAA := 2
const AA_TAA := 3
const AA_MSAA_SMAA := 4
const AA_MSAA_TAA := 5
const SHADOW_NAMES := ["Off", "Low", "Medium", "High"]
const FPS_NAMES := ["30", "60", "120", "Unlimited"]
const FPS_VALUES := [30, 60, 120, 0]

## What each quality preset sets. Medium is the default.
const PRESETS := [
	{"render_scale": 0.6, "antialiasing": AA_FXAA, "shadows": 1, "ssao": false, "ssil": false, "ssr": false, "glow": false, "post_fx": false},
	{"render_scale": 0.75, "antialiasing": AA_TAA, "shadows": 2, "ssao": false, "ssil": false, "ssr": false, "glow": true, "post_fx": true},
	{"render_scale": 1.0, "antialiasing": AA_TAA, "shadows": 3, "ssao": true, "ssil": false, "ssr": true, "glow": true, "post_fx": true},
	{"render_scale": 1.0, "antialiasing": AA_MSAA_TAA, "shadows": 3, "ssao": true, "ssil": true, "ssr": true, "glow": true, "post_fx": true},
]
## Shadow atlas size and how far the sun casts shadows, per shadow level.
const SHADOW_ATLAS := [0, 2048, 4096, 8192]
const SHADOW_DISTANCE := [0.0, 80.0, 150.0, 250.0]

var fullscreen := false
var vsync := true
var max_fps := 1
var quality := 1
var render_scale := 0.75
## An index into AA_NAMES. Saved under a new key so old "aa" indices are ignored.
var antialiasing := AA_TAA
var shadows := 2
var ssao := false
var ssil := false
var ssr := false
var glow := true
## Sharpen, colour grade and vignette (menu/post_fx.gdshader).
var post_fx := true
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
	Engine.max_fps = FPS_VALUES[max_fps]
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	# Run from the editor (F5) the game sits inside the editor's Game tab, and
	# changing the window mode or V-Sync there crashes it.
	if is_embedded():
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


## True when the game window is parented into another window, as the editor does.
static func is_embedded() -> bool:
	return Engine.is_embedded_in_editor() or "--wid" in OS.get_cmdline_args()


## Applies the graphics options to the window's viewport and to the world.
func apply_graphics(viewport: Viewport, main: Node) -> void:
	var temporal := antialiasing == AA_TAA or antialiasing == AA_MSAA_TAA
	viewport.scaling_3d_scale = render_scale
	# Below full scale, FSR 2 upscales and does the temporal AA itself (so plain
	# TAA stays off); FSR 1 sharpens the upscale for the other modes. At full
	# scale plain is cheaper.
	if render_scale >= 1.0:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	elif temporal:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
	else:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR
	viewport.use_taa = temporal and render_scale >= 1.0
	viewport.screen_space_aa = {
		AA_FXAA: Viewport.SCREEN_SPACE_AA_FXAA,
		AA_SMAA: Viewport.SCREEN_SPACE_AA_SMAA,
		AA_MSAA_SMAA: Viewport.SCREEN_SPACE_AA_SMAA,
	}.get(antialiasing, Viewport.SCREEN_SPACE_AA_DISABLED)
	viewport.msaa_3d = Viewport.MSAA_4X if antialiasing >= AA_MSAA_SMAA else Viewport.MSAA_DISABLED
	# Smooths the banding in the sky gradient and fog.
	viewport.use_debanding = post_fx
	_apply_post_fx(main)

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
		env.ssr_enabled = ssr
		env.ssr_max_steps = 48
		env.ssr_fade_in = 0.2
		env.ssr_fade_out = 2.0
		env.glow_enabled = glow
		env.glow_intensity = 0.4
		env.glow_bloom = 0.05


## Adds (once) a full-screen sharpen/grade/vignette pass over the 3D image.
## Its layer sits under the HUD (1) and the menu (10), so text stays untouched.
func _apply_post_fx(main: Node) -> void:
	var layer := main.get_node_or_null("PostFX") as CanvasLayer
	if not post_fx:
		if layer:
			layer.visible = false
		return
	if layer == null:
		layer = CanvasLayer.new()
		layer.name = "PostFX"
		layer.layer = -1
		var rect := ColorRect.new()
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://menu/post_fx.gdshader")
		rect.material = mat
		layer.add_child(rect)
		main.add_child(layer)
	layer.visible = true


func _keys() -> PackedStringArray:
	return ["fullscreen", "vsync", "max_fps", "quality", "render_scale", "antialiasing", "shadows", "ssao", "ssil", "ssr", "glow", "post_fx", "volume"]
