extends RefCounted
## The map: where the path is, which grid cells are free to build on, and how to
## turn a distance walked along the path into a spot on the screen. It knows
## nothing about enemies or towers.

const Data := preload("res://scripts/data.gd")

## The path as pixel points (the centre of each corner cell) and the distance
## from the start to each one.
var points: Array[Vector2] = []
var distances: Array[float] = []
var length := 0.0

var _path_cells := {}       # Vector2i -> true, every cell the path passes through


func _init() -> void:
	for corner in Data.PATH_CORNERS:
		points.append(cell_center(corner))
	distances.append(0.0)
	for i in range(1, points.size()):
		length += points[i].distance_to(points[i - 1])
		distances.append(length)

	for i in range(1, Data.PATH_CORNERS.size()):
		var from: Vector2i = Data.PATH_CORNERS[i - 1]
		var to: Vector2i = Data.PATH_CORNERS[i]
		var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
		var cell := from
		while true:
			_path_cells[cell] = true
			if cell == to:
				break
			cell += step


static func cell_center(cell: Vector2i) -> Vector2:
	return Data.GRID_ORIGIN + (Vector2(cell) + Vector2(0.5, 0.5)) * Data.CELL


static func cell_at(position: Vector2) -> Vector2i:
	var relative := (position - Data.GRID_ORIGIN) / float(Data.CELL)
	return Vector2i(floori(relative.x), floori(relative.y))


static func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < Data.GRID_COLS and cell.y >= 0 and cell.y < Data.GRID_ROWS


func is_path(cell: Vector2i) -> bool:
	return _path_cells.has(cell)


func path_cell_count() -> int:
	return _path_cells.size()


## The spot on the screen `distance` pixels along the path. Distances below 0
## give the start and distances beyond the end give the end.
func point_at(distance: float) -> Vector2:
	if distance <= 0.0:
		return points[0]
	if distance >= length:
		return points[points.size() - 1]
	for i in range(1, points.size()):
		if distance <= distances[i]:
			var segment := distances[i] - distances[i - 1]
			var t := (distance - distances[i - 1]) / segment
			return points[i - 1].lerp(points[i], t)
	return points[points.size() - 1]
