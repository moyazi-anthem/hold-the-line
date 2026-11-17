extends Node2D
## A shot flying towards its target. It homes in on the target while it lives.
## If the target dies first, the shot carries on to where the target was last
## seen and lands there (a cannon shell still explodes; the others fizzle out).

signal hit(projectile, at_position, target)

var kind := "pellet"
var damage := 10.0
var splash := 0.0
var slow := 1.0
var slow_time := 0.0
var speed := 450.0
var target                     # an enemy node, or null once it has died
var done := false

var _aim_at := Vector2.ZERO    # the target's last known position


func setup(from: Vector2, tower_type: String, stats: Dictionary, aimed_at) -> void:
	kind = tower_type
	damage = stats["damage"]
	splash = stats["splash"]
	slow = stats["slow"]
	slow_time = stats["slow_time"]
	speed = stats["projectile_speed"]
	target = aimed_at
	position = from
	_aim_at = aimed_at.position
	add_to_group("projectiles")


func target_is_alive() -> bool:
	return target != null and is_instance_valid(target) and target.alive


## Move `delta` seconds forward.
func advance(delta: float) -> void:
	if done:
		return
	if target_is_alive():
		_aim_at = target.position
	var step := speed * delta
	var to_go := _aim_at - position
	if to_go.length() <= step:
		position = _aim_at
		done = true
		hit.emit(self, position, target if target_is_alive() else null)
	else:
		position += to_go.normalized() * step
		queue_redraw()


func _draw() -> void:
	match kind:
		"pellet":
			draw_circle(Vector2.ZERO, 4.0, Color(0.75, 1.0, 0.75))
		"frost":
			draw_colored_polygon(
				PackedVector2Array([Vector2(0, -5), Vector2(5, 0), Vector2(0, 5), Vector2(-5, 0)]),
				Color(0.75, 0.95, 1.0))
		"cannon":
			draw_circle(Vector2.ZERO, 6.0, Color(0.25, 0.2, 0.15))
			draw_circle(Vector2.ZERO, 4.0, Color(1.0, 0.75, 0.3))
