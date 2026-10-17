class_name Wallet
extends Node
## Your money, in Armenian drams (AMD). It is kept between games in
## user://wallet.cfg: saved when you finish paying for something and when the
## game closes. Delete that file (or call reset()) to start again with start_balance.

signal changed(balance: float)

const SAVE_PATH := "user://wallet.cfg"

## What you have the first time you play.
@export var start_balance := 20000.0

## Drams you have now. Payments can be in fractions (fuel by the litre), so it
## is kept as a float and shown rounded down.
var balance := 0.0


func _ready() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) == OK:
		balance = maxf(float(file.get_value("wallet", "balance", start_balance)), 0.0)
	else:
		balance = start_balance
	changed.emit(balance)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		save()


func can_afford(amount: float) -> bool:
	return amount <= balance + 0.001


## Takes `amount` if you have it and returns true; otherwise takes nothing.
func spend(amount: float) -> bool:
	if amount < 0.0 or not can_afford(amount):
		return false
	balance = maxf(balance - amount, 0.0)
	changed.emit(balance)
	return true


func earn(amount: float) -> void:
	if amount <= 0.0:
		return
	balance += amount
	changed.emit(balance)


func save() -> void:
	var file := ConfigFile.new()
	file.set_value("wallet", "balance", balance)
	file.save(SAVE_PATH)


## Back to start_balance, as on the first game.
func reset() -> void:
	balance = start_balance
	changed.emit(balance)
	save()


## "12 345 AMD": whole drams, thousands apart.
static func format(amount: float) -> String:
	var whole := str(floori(absf(amount)))
	var grouped := ""
	while whole.length() > 3:
		grouped = " " + whole.right(3) + grouped
		whole = whole.left(whole.length() - 3)
	return "%s%s%s AMD" % ["-" if amount < 0.0 else "", whole, grouped]
