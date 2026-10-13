extends Node3D
## Lamps of a car built by tools/build_car.gd: brake, reverse and tail lights,
## turn signals and headlights.
##
## Z: left signal   C: right signal   X: hazards
## L: cycles off -> parking lights -> low beam -> high beam

enum Beam { OFF, PARKING, LOW, HIGH }

const BLINKS_PER_SECOND := 1.5
## Glow of a lamp that is off; textured lenses look black behind their glass without a little.
@export var idle_glow := 0.3
## Brightness of all lamps. Plain tinted lenses need far less than textured ones to keep their colour.
@export var glow_scale := 1.0

var beam := Beam.OFF
var signal_left := false
var signal_right := false

var _blink_time := 0.0
var _last_blink := false
var _tick: AudioStreamPlayer
var _tick_sound: AudioStream
var _tock_sound: AudioStream
var _materials := {} # zone name -> materials of the pieces of that lamp
var _clear_alpha := {} # material -> its alpha when the lamp is off
@onready var _car := get_parent() as VehicleBody3D
@onready var _beams: Array[Node] = find_children("Beam*", "SpotLight3D", false, false)


func _ready() -> void:
	if ResourceLoader.exists("res://audio/tick.res"):
		_tick_sound = load("res://audio/tick.res")
		_tock_sound = load("res://audio/tock.res")
		_tick = AudioStreamPlayer.new()
		_tick.volume_db = -8.0
		add_child(_tick)
	for child in get_children():
		var lamp := child as MeshInstance3D
		if lamp and lamp.name.begins_with("Lamp_"):
			# A copy per car, or every car sharing the model would light up together.
			var own := lamp.mesh.surface_get_material(0).duplicate()
			lamp.set_surface_override_material(0, own)
			# "Lamp_indicator_l" and "Lamp_indicator_l__mirror" are pieces of one lamp.
			var zone := String(lamp.name).trim_prefix("Lamp_").get_slice("__", 0)
			if not _materials.has(zone):
				_materials[zone] = []
			_materials[zone].append(own)
			_clear_alpha[own] = (own as StandardMaterial3D).albedo_color.a


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not _car.get("player_controlled"):
		return
	var hazards := signal_left and signal_right
	match key.physical_keycode:
		KEY_Z:
			_set_signals(hazards or not signal_left, false)
		KEY_C:
			_set_signals(false, hazards or not signal_right)
		KEY_X:
			_set_signals(not hazards, not hazards)
		KEY_L:
			beam = (beam + 1) % Beam.size() as Beam


func _set_signals(left: bool, right: bool) -> void:
	signal_left = left
	signal_right = right
	_blink_time = 0.0


## True during the lit half of the turn-signal cycle.
func blink_on() -> bool:
	return fmod(_blink_time * BLINKS_PER_SECOND, 1.0) < 0.5


func _process(delta: float) -> void:
	_blink_time += delta
	var blink := blink_on()
	# The relay clicks on every flash, heard in the car being driven.
	var flashing: bool = (signal_left or signal_right) and _car.get("player_controlled")
	if flashing and blink != _last_blink and _tick:
		_tick.stream = _tick_sound if blink else _tock_sound
		_tick.play()
	_last_blink = blink
	var lit := beam != Beam.OFF
	var braking: bool = _car.get("braking")
	var reversing := _car.engine_force < 0.0

	_glow("indicator_l", 5.0 if signal_left and blink else 0.0)
	_glow("indicator_r", 5.0 if signal_right and blink else 0.0)
	_glow("stop", 6.0 if braking else (1.2 if lit else 0.0))
	_glow("tail", 1.5 if lit else 0.0)
	_glow("reverse", 4.0 if reversing else 0.0)
	_glow("low", [0.0, 0.8, 4.0, 4.0][beam])
	_glow("high", 5.0 if beam == Beam.HIGH else 0.0)

	for node in _beams:
		var spot := node as SpotLight3D
		spot.visible = beam >= Beam.LOW
		var high := beam == Beam.HIGH
		spot.light_energy = 14.0 if high else 7.0
		spot.spot_range = 140.0 if high else 55.0
		# Lights shine along -Z, so they face backwards in car space; dip the low beam.
		spot.rotation_degrees = Vector3(-1.0 if high else -6.0, 180.0, 0.0)


func _glow(zone: String, energy: float) -> void:
	for mat: StandardMaterial3D in _materials.get(zone, []):
		# A little glow even when off, or the lenses look black behind their glass.
		mat.emission_energy_multiplier = maxf(energy * glow_scale, idle_glow)
		# A see-through lens only shows a fraction of its glow, so a lit one turns solid.
		var clear: float = _clear_alpha[mat]
		if clear < 1.0:
			mat.albedo_color.a = lerpf(clear, 1.0, clampf(energy / 2.0, 0.0, 1.0))
