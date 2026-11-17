extends Node2D
## Drawn on top of the towers and enemies: the preview of the tower you are about
## to build (green where it can go, red where it can't), and the range circle of
## the selected tower. It only draws; it changes nothing.

const Data := preload("res://scripts/data.gd")
const Board := preload("res://scripts/board.gd")


func _draw() -> void:
	var game = get_parent()
	if game.state != game.State.BUILD and game.state != game.State.WAVE:
		return
	var cell: Vector2i = game.hover_cell

	if game.build_choice != "":
		if Board.in_bounds(cell):
			var type: String = game.build_choice
			var ok: bool = game.build_problem(cell, type) == ""
			var tint := Color(0.4, 1.0, 0.5) if ok else Color(1.0, 0.4, 0.4)
			var center := Board.cell_center(cell)
			var reach: float = Data.tower_stats(type, 1)["range"]
			draw_circle(center, reach, Color(tint, 0.10))
			draw_arc(center, reach, 0.0, TAU, 64, Color(tint, 0.6), 2.0)
			draw_rect(Rect2(center - Vector2(18, 18), Vector2(36, 36)), Color(tint, 0.35))
			var color: Color = Data.TOWERS[type]["color"]
			draw_circle(center, 9.0, Color(color, 0.8))
		return

	var tower = game.selected
	if tower == null or not is_instance_valid(tower):
		tower = game.tower_at(cell)       # hovering a tower shows its reach too
	if tower != null:
		var reach: float = tower.stats["range"]
		draw_circle(tower.position, reach, Color(1, 1, 1, 0.07))
		draw_arc(tower.position, reach, 0.0, TAU, 64, Color(1, 1, 1, 0.55), 2.0)
	if game.selected != null and is_instance_valid(game.selected):
		var box := Rect2(game.selected.position - Vector2(20, 20), Vector2(40, 40))
		draw_rect(box, Color(1, 1, 1, 0.9), false, 2.0)
