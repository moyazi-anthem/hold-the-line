extends Node2D
## One tower. Every tick it looks for a target and, when it has cooled down,
## says "fired". The game manager turns that into a projectile.

signal fired(tower, target)

const Data := preload("res://scripts/data.gd")

var type := "pellet"
var level := 1
var cell := Vector2i.ZERO
var stats: Dictionary = {}
var cooldown_left := 0.0
var aim_angle := -PI / 2.0

var _flash := 0.0


func setup(tower_type: String, at_cell: Vector2i) -> void:
	type = tower_type
	cell = at_cell
	level = 1
	stats = Data.tower_stats(type, level)
	add_to_group("towers")


func upgrade() -> void:
	level += 1
	stats = Data.tower_stats(type, level)
	queue_redraw()


## Pick the enemy this tower would shoot: of those in range, the one that has
## walked furthest along the path ("first"), because it is closest to leaking.
func find_target(enemies: Array):
	var best = null
	var reach: float = stats["range"]
	for enemy in enemies:
		if not enemy.alive:
			continue
		if position.distance_to(enemy.position) > reach:
			continue
		if best == null or enemy.distance > best.distance:
			best = enemy
	return best


## Move `delta` seconds forward.
func advance(delta: float, enemies: Array) -> void:
	cooldown_left = maxf(0.0, cooldown_left - delta)
	_flash = maxf(0.0, _flash - delta)
	var target = find_target(enemies)
	if target != null:
		aim_angle = (target.position - position).angle()
		if cooldown_left <= 0.0:
			cooldown_left = stats["cooldown"]
			_flash = 0.1
			fired.emit(self, target)
		queue_redraw()


func _draw() -> void:
	var color: Color = Data.TOWERS[type]["color"]
	var lit := color.lightened(0.5) if _flash > 0.0 else color
	draw_rect(Rect2(-17, -17, 34, 34), Color(0.16, 0.18, 0.24))
	match type:
		"pellet":
			draw_circle(Vector2.ZERO, 11.0, lit)
		"frost":
			draw_colored_polygon(
				PackedVector2Array([Vector2(0, -13), Vector2(13, 0), Vector2(0, 13), Vector2(-13, 0)]), lit)
		"cannon":
			draw_circle(Vector2.ZERO, 13.0, lit.darkened(0.25))
			draw_circle(Vector2.ZERO, 8.0, lit)
	# the barrel points at whatever the tower last aimed at
	var tip := Vector2.from_angle(aim_angle) * 17.0
	draw_line(Vector2.ZERO, tip, lit.darkened(0.4), 5.0)
	# one dot per level above the first
	for i in range(1, level):
		draw_circle(Vector2(-12.0 + i * 8.0, 14.0), 2.5, Color(1, 1, 1, 0.95))
