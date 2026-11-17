extends Node2D
## A short ring that grows and fades, used to show where a cannon shell landed.
## It is only decoration: it has no effect on the game rules.

var radius := 50.0
var color := Color(1.0, 0.75, 0.3)
var life := 0.25

var _age := 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t := clampf(_age / life, 0.0, 1.0)
	var r := radius * (0.3 + 0.7 * t)
	draw_circle(Vector2.ZERO, r, Color(color, 0.25 * (1.0 - t)))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(color, 1.0 - t), 3.0)
