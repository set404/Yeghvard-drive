class_name Mission
extends RefCounted
## One mission: who gives it, what it pays, and its steps in order.
## game/mission_manager.gd runs it; each file in res://missions/ extends this
## and fills in `steps` in build().
##
## A step is a Dictionary:
##   "text":    what the objective panel says ("Buy a pack of Ararat at the till").
##   "target":  Callable -> Vector3, or null: where the marker (the minimap and the
##              beam of light in the world) points. Called every frame, so it can follow
##              something that moves. Optional.
##   "done":    Callable -> bool: true once the step is done; the next one starts.
##   "start":   Callable, optional: called as the step starts (to note how many of
##              something you have, say).
##   "back_to": Callable -> int, optional: checked every frame before "done"; a step
##              index sends you back to that step (you smoked Dad's cigarettes),
##              -1 carries on.
##   "back_message": Callable -> String, optional: what to say when sent back.

## Saved in user://missions.cfg, so it must not change once players have it.
var id := ""
var title := ""
## Drams paid when the last step is done.
var reward := 0.0
## Shown when it starts and when it is done.
var briefing := ""
var success := ""
var steps: Array[Dictionary] = []
## What to do to start it ("Go inside the house"), shown with start_target()
## marked until can_start() says it has been done. Empty: it starts at once.
var start_text := ""
## The game (main.gd): its player, car, wallet, inventory.
var main: Node3D


## Fills in `steps`. `main` is set by then.
func build() -> void:
	pass


## Where to go to start it (for the marker), or null.
func start_target() -> Variant:
	return null


## Whether what starts it has been done (with start_text set).
func can_start() -> bool:
	return true


## Called every frame while it runs, before its step is checked (for
## anything that is not a step: help when you are stuck, say).
func tick(_delta: float) -> void:
	pass


## Called once the last step is done, before the reward is paid.
func finish() -> void:
	pass


# --- helpers for the steps ---------------------------------------------------

## Where you are: your feet on foot, the car while you drive.
func you() -> Vector3:
	return main.player.global_position if main.on_foot else main.car.global_position


## How far you are from `at` across the ground (height left out).
func distance_to(at: Vector3) -> float:
	var me := you()
	return Vector2(at.x - me.x, at.z - me.z).length()


## The first shop stand (world/duet_stand.gd, world/cashier.gd) selling `item_id`,
## nearest to you when there are several.
func stand_selling(item_id: String) -> Node3D:
	var best: Node3D = null
	var best_d := INF
	for stand: Node3D in main.get_tree().get_nodes_in_group("shop_stands"):
		if stand.get("item_id") != item_id:
			continue
		var d := distance_to(stand.global_position)
		if d < best_d:
			best = stand
			best_d = d
	return best
