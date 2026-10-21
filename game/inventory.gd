class_name Inventory
extends Node
## What you carry: slots of items, each a stack of one kind, and which slot is
## in your hand. Kept between games in user://inventory.cfg, saved whenever it
## changes, like game/wallet.gd. main.gd puts the selected item in the player's
## hand and hud/inventory_bar.gd shows the slots.
##
## With cigarettes and a drink, there is one more slot after them, not a stack
## of its own: the two together ("cigarette+<drink>", see COMBOS), for a smoke
## break with the drink. And while you carry anything, the first slot is your
## empty hand (EMPTY_HAND): choosing it puts away what is in your hand.

signal changed

const SAVE_PATH := "user://inventory.cfg"
const MAX_SLOTS := 8
const MAX_STACK := 99

## Every kind of item there is: its name, the model held in the hand (and
## shown in its slot), how big that model is shown, and what E does with it:
## "drink" a sip, "smoke" a smoke break.
const ITEMS := {
	"duet": {"name": "Duet ice coffee", "scene": "res://props/duet.glb", "scale": 0.75, "use": "drink"},
	"cigarette": {"name": "Cigarette", "scene": "res://props/cigarettes.tscn", "scale": 1.0, "use": "smoke"},
}
## Two items used together, shown as one more slot when you have both: the
## smoke and the drink it goes with, what it is called and shows. E uses it:
## "smoke_drink", a smoke break with the drink in your other hand.
const COMBOS := {
	"cigarette+duet": {"name": "Cigarette + Duet ice coffee", "scene": "res://props/cigarette_coffee.tscn",
		"smoke": "cigarette", "drink": "duet", "use": "smoke_drink"},
}

## The empty-hand slot's id: nothing in your hand.
const EMPTY_HAND := "hand"
const EMPTY_HAND_NAME := "Empty hand"

## [{"id": String, "count": int}], in the order they were picked up.
var slots: Array[Dictionary] = []
## Index into entries() of the item in your hand; -1 with nothing to hold.
var selected := -1


func _ready() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) == OK:
		for slot: Dictionary in file.get_value("inventory", "slots", []):
			if ITEMS.has(slot.get("id")) and int(slot.get("count", 0)) > 0:
				slots.append({"id": slot["id"], "count": mini(int(slot["count"]), MAX_STACK)})
		selected = clampi(int(file.get_value("inventory", "selected", 0)), 0, entries().size() - 1) if slots else -1
	changed.emit()


func save() -> void:
	var file := ConfigFile.new()
	file.set_value("inventory", "slots", slots)
	file.set_value("inventory", "selected", selected)
	file.save(SAVE_PATH)


## What the slots show, in order: your empty hand (while you carry anything),
## each stack ({"id", "count"}), then the combinations you have both parts of
## ({"id", "count", "combo": true}, count how many of the smoke).
func entries() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not slots.is_empty():
		out.append({"id": EMPTY_HAND, "count": 0, "hand": true})
	out.append_array(slots)
	for combo_id: String in COMBOS:
		var combo: Dictionary = COMBOS[combo_id]
		if count_of(combo["smoke"]) > 0 and count_of(combo["drink"]) > 0:
			out.append({"id": combo_id, "count": count_of(combo["smoke"]), "combo": true})
	return out


func count_of(id: String) -> int:
	var n := 0
	for slot in slots:
		if slot["id"] == id:
			n += slot["count"]
	return n


func is_full_for(id: String) -> bool:
	for slot in slots:
		if slot["id"] == id and slot["count"] < MAX_STACK:
			return false
	return slots.size() >= MAX_SLOTS


## Puts `amount` of `id` on its stack (or in a new slot) and returns true;
## false when there is no room. With nothing in your hand, it goes there.
func add(id: String, amount := 1) -> bool:
	if is_full_for(id):
		return false
	var selected_id_before := selected_id()
	for n in amount:
		var at := -1
		for k in slots.size():
			if slots[k]["id"] == id and slots[k]["count"] < MAX_STACK:
				at = k
				break
		if at < 0:
			if slots.size() >= MAX_SLOTS:
				break
			slots.append({"id": id, "count": 0})
			at = slots.size() - 1
		slots[at]["count"] += 1
	# Into your hand if it was empty; otherwise what you held stays there.
	_reselect(selected_id_before if selected_id_before not in ["", EMPTY_HAND] else id)
	_changed()
	return true


## The id of what is in your hand ("cigarette+duet" for a combination), or "".
func selected_id() -> String:
	var all := entries()
	return all[selected]["id"] if selected >= 0 and selected < all.size() else ""


## What E does with what is in your hand ("drink", "smoke", "smoke_drink"), or "".
func selected_use() -> String:
	var id := selected_id()
	if COMBOS.has(id):
		return COMBOS[id]["use"]
	return ITEMS[id]["use"] if ITEMS.has(id) else ""


## The item to show in your hand: the selected one, or a combination's drink
## (the cigarette comes out on the smoke break); "" for nothing to hold (your
## empty hand too).
func held_id() -> String:
	var id := selected_id()
	if COMBOS.has(id):
		return COMBOS[id]["drink"]
	if not ITEMS.has(id) or ITEMS[id]["use"] == "smoke":
		return ""
	return id


static func item_name(id: String) -> String:
	if id == EMPTY_HAND:
		return EMPTY_HAND_NAME
	if COMBOS.has(id):
		return COMBOS[id]["name"]
	return ITEMS[id]["name"] if ITEMS.has(id) else id


## Uses up one of the item in your hand (for a combination, its drink).
func remove_selected() -> void:
	var id := selected_id()
	if COMBOS.has(id):
		id = COMBOS[id]["drink"]
	use_one(id)


## Uses up one `id`, keeping what is in your hand where it can.
func use_one(id: String) -> void:
	var before := selected_id()
	for k in range(slots.size() - 1, -1, -1):
		if slots[k]["id"] == id:
			slots[k]["count"] -= 1
			if slots[k]["count"] <= 0:
				slots.remove_at(k)
			break
	_reselect(before)
	_changed()


## The next slot (`step` 1) or the one before (-1), round and round.
func select_step(step: int) -> void:
	var n := entries().size()
	if n < 2:
		return
	selected = posmod(selected + step, n)
	_changed()


## Points `selected` at `id` again after the slots changed, or at the nearest
## one left.
func _reselect(id: String) -> void:
	var all := entries()
	if all.is_empty():
		selected = -1
		return
	if id == EMPTY_HAND:
		selected = 0
		return
	for k in all.size():
		if all[k]["id"] == id:
			selected = k
			return
	# A combination used up: its drink, or its smoke, if left.
	if COMBOS.has(id):
		for part: String in [COMBOS[id]["drink"], COMBOS[id]["smoke"]]:
			for k in all.size():
				if all[k]["id"] == part:
					selected = k
					return
	selected = clampi(selected, 0, all.size() - 1)


func _changed() -> void:
	changed.emit()
	save()
