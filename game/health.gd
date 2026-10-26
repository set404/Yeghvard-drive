class_name Health
extends Node
## How much someone can take: the player has one (player/combat.gd puts it on
## him as "Health"). Hurt by punches and bullets; after regen_delay seconds
## without a hit it slowly comes back.

signal damaged(amount: float, from: Vector3)
signal died

@export var max_health := 100.0
## Health back a second once regen_delay seconds have gone by since the last hit.
@export var regen := 3.0
@export var regen_delay := 6.0

var health := 100.0
var _since_hit := 0.0


func _ready() -> void:
	health = max_health


func _process(delta: float) -> void:
	if regen <= 0.0 or is_dead() or health >= max_health:
		return
	_since_hit += delta
	if _since_hit >= regen_delay:
		health = minf(health + regen * delta, max_health)


## Takes `amount` off, hit from `from` (world); at 0 they are down.
func hurt(amount: float, from := Vector3.ZERO) -> void:
	if is_dead() or amount <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	_since_hit = 0.0
	damaged.emit(amount, from)
	if health <= 0.0:
		died.emit()


func is_dead() -> bool:
	return health <= 0.0


func share() -> float:
	return health / max_health


func reset() -> void:
	health = max_health
	_since_hit = 0.0
