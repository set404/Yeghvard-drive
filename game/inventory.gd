class_name Inventory
extends Node
## What you carry: slots of items, each a stack of one kind, and which slot is
## in your hand. Kept between games in user://inventory.cfg, saved whenever it
## changes, like game/wallet.gd. main.gd puts the selected item in the player's
## hand and hud/inventory_bar.gd shows the slots.

signal changed

const SAVE_PATH := "user://inventory.cfg"
const MAX_SLOTS := 8
const MAX_STACK := 99

## Every kind of item there is: its name, the model held in the hand (and
## shown in its slot), how big that model is shown, and what E does with it.
const ITEMS := {
	"duet": {"name": "Duet ice coffee", "scene": "res://props/duet.glb", "scale": 0.75, "use": "drink"},
}

## [{"id": String, "count": int}], in the order they were picked up.
var slots: Array[Dictionary] = []
## Index into slots of the item in your hand; -1 with nothing to hold.
var selected := -1


func _ready() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) == OK:
		for slot: Dictionary in file.get_value("inventory", "slots", []):
			if ITEMS.has(slot.get("id")) and int(slot.get("count", 0)) > 0:
				slots.append({"id": slot["id"], "count": mini(int(slot["count"]), MAX_STACK)})
		selected = clampi(int(file.get_value("inventory", "selected", 0)), 0, slots.size() - 1) if slots else -1
	changed.emit()


func save() -> void:
	var file := ConfigFile.new()
	file.set_value("inventory", "slots", slots)
	file.set_value("inventory", "selected", selected)
	file.save(SAVE_PATH)


func is_full_for(id: String) -> bool:
	for slot in slots:
		if slot["id"] == id and slot["count"] < MAX_STACK:
			return false
	return slots.size() >= MAX_SLOTS


## Puts one `id` on its stack (or in a new slot) and returns true; false when
## there is no room. With nothing in your hand, it goes there.
func add(id: String) -> bool:
	if is_full_for(id):
		return false
	var at := -1
	for k in slots.size():
		if slots[k]["id"] == id and slots[k]["count"] < MAX_STACK:
			at = k
			break
	if at < 0:
		slots.append({"id": id, "count": 0})
		at = slots.size() - 1
	slots[at]["count"] += 1
	if selected < 0:
		selected = at
	_changed()
	return true


## The id of the item in your hand, or "".
func selected_id() -> String:
	return slots[selected]["id"] if selected >= 0 else ""


static func item_name(id: String) -> String:
	return ITEMS[id]["name"] if ITEMS.has(id) else id


## Uses up one of the item in your hand.
func remove_selected() -> void:
	if selected < 0:
		return
	slots[selected]["count"] -= 1
	if slots[selected]["count"] <= 0:
		slots.remove_at(selected)
		selected = mini(selected, slots.size() - 1)
	_changed()


## The next slot (`step` 1) or the one before (-1), round and round.
func select_step(step: int) -> void:
	if slots.size() < 2:
		return
	selected = posmod(selected + step, slots.size())
	_changed()


func _changed() -> void:
	changed.emit()
	save()
