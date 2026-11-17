extends Node2D
## One enemy. It walks along the path, can be hurt and slowed, and says "died"
## or "leaked" when its story ends. It does not know about gold or lives: the
## game manager listens for the signals and decides what they mean.

signal died(enemy)
signal leaked(enemy)

const Data := preload("res://scripts/data.gd")

var type := "grunt"
var max_hp := 30.0
var hp := 30.0
var speed := 70.0
var reward := 5
var leak_damage := 1
var radius := 11.0
var color := Color.WHITE
var distance := 0.0            # how far along the path it has walked, in pixels
var alive := true

var _board
var _slow_factor := 1.0
var _slow_left := 0.0


func setup(enemy_type: String, board, wave: int) -> void:
	type = enemy_type
	_board = board
	var stats: Dictionary = Data.ENEMIES[enemy_type]
	max_hp = Data.enemy_hp(enemy_type, wave)
	hp = max_hp
	speed = stats["speed"]
	reward = stats["reward"]
	leak_damage = stats["leak"]
	radius = stats["radius"]
	color = stats["color"]
	position = board.point_at(0.0)
	add_to_group("enemies")


## Move `delta` seconds forward.
func advance(delta: float) -> void:
	if not alive:
		return
	if _slow_left > 0.0:
		_slow_left -= delta
		if _slow_left <= 0.0:
			_slow_factor = 1.0
			queue_redraw()
	distance += speed * _slow_factor * delta
	if distance >= _board.length:
		alive = false
		leaked.emit(self)
		return
	position = _board.point_at(distance)


func take_damage(amount: float) -> void:
	if not alive:
		return
	hp -= amount
	queue_redraw()
	if hp <= 0.0:
		alive = false
		died.emit(self)


## Slow the enemy to `factor` of its speed for `seconds`. A weaker slow never
## replaces a stronger one that is still running, and no slow shortens another.
func apply_slow(factor: float, seconds: float) -> void:
	if not alive:
		return
	var current := _slow_factor if _slow_left > 0.0 else 1.0
	_slow_factor = minf(current, factor)
	_slow_left = maxf(_slow_left, seconds)
	queue_redraw()


func is_slowed() -> bool:
	return _slow_left > 0.0


func speed_now() -> float:
	return speed * _slow_factor


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius, color)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, color.darkened(0.45), 2.0)
	if is_slowed():
		draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 24, Color(0.55, 0.85, 1.0), 2.0)
	if hp < max_hp:
		var width := radius * 2.0
		var top_left := Vector2(-radius, -radius - 8.0)
		draw_rect(Rect2(top_left, Vector2(width, 4.0)), Color(0, 0, 0, 0.6))
		var share := clampf(hp / max_hp, 0.0, 1.0)
		draw_rect(Rect2(top_left, Vector2(width * share, 4.0)), Color(0.45, 0.9, 0.45))
