extends Node3D
## Moving parts of the cabin of a car built by tools/build_car.gd: the steering
## wheel follows the front wheels, the speedometer and rev counter needles move
## and, on dials that have them, the turn arrows blink.

## Turns of the steering wheel per turn of the road wheels.
@export var steering_ratio := 5.0

@onready var _car := get_parent() as VehicleBody3D
@onready var _wheel := get_node_or_null("SteeringWheel") as Node3D
@onready var _gauges := get_node_or_null("Gauges") as MeshInstance3D
@onready var _lamps := _car.get_node_or_null("Lamps")
var _wheel_axis := Vector3.BACK
var _dial: ShaderMaterial


func _ready() -> void:
	if _wheel:
		_wheel_axis = _wheel.get_meta("axis", Vector3.BACK)
	if _gauges:
		# A copy per car, so two cars sharing the model show their own speed.
		_dial = _gauges.mesh.surface_get_material(0).duplicate() as ShaderMaterial
		_gauges.set_surface_override_material(0, _dial)


func _process(_delta: float) -> void:
	if _wheel:
		# The axis points at the driver, so a left turn rolls the top of the wheel left.
		_wheel.basis = Basis(_wheel_axis, _car.steering * steering_ratio)
	if _dial:
		_dial.set_shader_parameter("speed_kmh", absf(_car.forward_speed()) * 3.6)
		_dial.set_shader_parameter("rpm", _car.rpm)
		# Only dials that have a live fuel needle take this (see gauges_lc80.gdshader).
		_dial.set_shader_parameter("fuel", _car.fuel_level())
		if _lamps:
			var blink: bool = _lamps.blink_on()
			_dial.set_shader_parameter("signal_left", 1.0 if _lamps.signal_left and blink else 0.0)
			_dial.set_shader_parameter("signal_right", 1.0 if _lamps.signal_right and blink else 0.0)
