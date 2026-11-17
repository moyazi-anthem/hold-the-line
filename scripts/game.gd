extends Node2D
## The game manager. It owns the rules: gold, lives, waves, building, upgrading,
## selling, and what happens when an enemy dies or a shot lands. Enemies, towers
## and projectiles only report what happened (with signals); this script decides
## what it means.
##
## Everything that moves is driven by tick(delta), called from _physics_process.
## That keeps the rules separate from the drawing, and lets tools/smoke_test.gd
## run a whole wave in a blink by calling tick() in a loop.

const Data := preload("res://scripts/data.gd")
const Board := preload("res://scripts/board.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const TowerScript := preload("res://scripts/tower.gd")
const ProjectileScript := preload("res://scripts/projectile.gd")
const EffectScript := preload("res://scripts/effect.gd")

enum State { TITLE, BUILD, WAVE, WON, LOST }

const GROUND_A := Color(0.13, 0.15, 0.20)
const GROUND_B := Color(0.12, 0.14, 0.19)
const PATH_COLOR := Color(0.36, 0.30, 0.23)

var state: State = State.TITLE
var gold := Data.START_GOLD
var lives := Data.START_LIVES
var wave := 0                  # the wave that was started last; 0 before the first
var speed_multiplier := 1
var build_choice := ""         # the tower type picked in the palette, or "" for none
var selected = null            # the tower whose upgrade/sell panel is open, or null
var hover_cell := Vector2i(-99, -99)

var board
var enemies: Array = []
var towers: Array = []
var projectiles: Array = []

var _tower_at := {}            # Vector2i -> tower
var _schedule: Array = []      # spawns still to come: [{"at": seconds, "type": id}]
var _wave_clock := 0.0

@onready var hud = $HUD
@onready var overlay = $Overlay
@onready var _towers_node: Node2D = $Towers
@onready var _enemies_node: Node2D = $Enemies
@onready var _projectiles_node: Node2D = $Projectiles
@onready var _effects_node: Node2D = $Effects


func _ready() -> void:
	board = Board.new()
	_register_input_actions()
	hud.tower_chosen.connect(choose_tower)
	hud.start_wave_pressed.connect(start_wave)
	hud.speed_pressed.connect(cycle_speed)
	hud.upgrade_pressed.connect(upgrade_selected)
	hud.sell_pressed.connect(sell_selected)
	_show_title()


func _process(_delta: float) -> void:
	var cell: Vector2i = board.cell_at(get_global_mouse_position())
	if cell != hover_cell:
		hover_cell = cell
		overlay.queue_redraw()


func _physics_process(delta: float) -> void:
	for i in speed_multiplier:
		tick(delta)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("start"):
		match state:
			State.TITLE, State.WON, State.LOST:
				start_game()
			State.BUILD:
				start_wave()
	elif event.is_action_pressed("speed"):
		cycle_speed()
	elif event.is_action_pressed("cancel"):
		cancel()
	elif event.is_action_pressed("upgrade"):
		upgrade_selected()
	elif event.is_action_pressed("sell"):
		sell_selected()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			click_cell(board.cell_at(make_input_local(event).position))
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel()
	else:
		for i in Data.TOWER_ORDER.size():
			if event.is_action_pressed("tower_%d" % (i + 1)):
				choose_tower(Data.TOWER_ORDER[i])


# --- the game's life cycle -------------------------------------------------------

func start_game() -> void:
	_clear_world()
	gold = Data.START_GOLD
	lives = Data.START_LIVES
	wave = 0
	speed_multiplier = 1
	state = State.BUILD
	hud.hide_message()
	_refresh_hud()


## Begin the next wave. Returns false if a wave can't start right now.
func start_wave() -> bool:
	if state != State.BUILD or wave >= Data.final_wave():
		return false
	wave += 1
	_schedule = Data.wave_schedule(wave)
	_wave_clock = 0.0
	state = State.WAVE
	_refresh_hud()
	return true


func cycle_speed() -> void:
	speed_multiplier = speed_multiplier % 3 + 1
	_refresh_hud()


## Move the whole game `delta` seconds forward.
func tick(delta: float) -> void:
	if state != State.WAVE and state != State.BUILD:
		return
	if state == State.WAVE:
		_wave_clock += delta
		_spawn_due()
	for enemy in enemies.duplicate():
		enemy.advance(delta)
	for tower in towers:
		tower.advance(delta, enemies)
	for projectile in projectiles.duplicate():
		projectile.advance(delta)
	if state == State.WAVE:
		_check_wave_end()


func _show_title() -> void:
	state = State.TITLE
	hud.show_message(
		"HOLD THE LINE\n\n"
		+ "Stop the enemies reaching the exit on the right.\n"
		+ "Build towers on the open ground beside the path.\n\n"
		+ "Press 1, 2 or 3 to pick a tower, then click to build it.\n"
		+ "Press Space to send the next wave.\n\n"
		+ "Press Enter to start"
	)
	_refresh_hud()


func _win() -> void:
	state = State.WON
	selected = null
	build_choice = ""
	hud.show_message(
		"YOU HELD THE LINE!\n\nAll %d waves defeated with %d lives left.\n\nPress Enter to play again"
		% [Data.final_wave(), lives])
	_refresh_hud()


func _lose() -> void:
	state = State.LOST
	selected = null
	build_choice = ""
	hud.show_message("THE LINE BROKE\n\nYou made it to wave %d.\n\nPress Enter to try again" % wave)
	_refresh_hud()


func _clear_world() -> void:
	for node in enemies + towers + projectiles:
		node.queue_free()
	for effect in _effects_node.get_children():
		effect.queue_free()
	enemies.clear()
	towers.clear()
	projectiles.clear()
	_tower_at.clear()
	_schedule.clear()
	selected = null
	build_choice = ""


# --- waves, enemies, shots ---------------------------------------------------------

func _spawn_due() -> void:
	while not _schedule.is_empty() and _schedule[0]["at"] <= _wave_clock:
		var entry: Dictionary = _schedule.pop_front()
		spawn_enemy(entry["type"])


func spawn_enemy(type: String):
	var enemy = EnemyScript.new()
	_enemies_node.add_child(enemy)
	enemy.setup(type, board, wave)
	enemy.died.connect(_on_enemy_died)
	enemy.leaked.connect(_on_enemy_leaked)
	enemies.append(enemy)
	return enemy


func _on_enemy_died(enemy) -> void:
	gold += enemy.reward
	_remove_enemy(enemy)
	_refresh_hud()


func _on_enemy_leaked(enemy) -> void:
	lives = maxi(0, lives - enemy.leak_damage)
	_remove_enemy(enemy)
	_refresh_hud()
	if lives <= 0 and state == State.WAVE:
		_lose()


func _remove_enemy(enemy) -> void:
	enemies.erase(enemy)
	enemy.queue_free()


func _on_tower_fired(tower, target) -> void:
	var projectile = ProjectileScript.new()
	_projectiles_node.add_child(projectile)
	projectile.setup(tower.position, tower.type, tower.stats, target)
	projectile.hit.connect(_on_projectile_hit)
	projectiles.append(projectile)


func _on_projectile_hit(projectile, at_position: Vector2, target) -> void:
	projectiles.erase(projectile)
	projectile.queue_free()
	var victims: Array = []
	if projectile.splash > 0.0:
		_spawn_effect(at_position, projectile.splash)
		for enemy in enemies:
			if enemy.alive and enemy.position.distance_to(at_position) <= projectile.splash:
				victims.append(enemy)
	elif target != null:
		victims.append(target)
	for enemy in victims:
		if projectile.slow < 1.0:
			enemy.apply_slow(projectile.slow, projectile.slow_time)
		enemy.take_damage(projectile.damage)


func _spawn_effect(at_position: Vector2, radius: float) -> void:
	var effect = EffectScript.new()
	effect.radius = radius
	effect.position = at_position
	_effects_node.add_child(effect)


func _check_wave_end() -> void:
	if not _schedule.is_empty() or not enemies.is_empty():
		return
	gold += Data.WAVE_BONUS
	if wave >= Data.final_wave():
		_win()
	else:
		state = State.BUILD
		hud.toast("Wave %d cleared! +%d gold" % [wave, Data.WAVE_BONUS])
		_refresh_hud()


# --- building, upgrading, selling ----------------------------------------------------

## Why a tower of this type can't be built on this cell right now, or "" if it can.
func build_problem(cell: Vector2i, type: String) -> String:
	if state != State.BUILD and state != State.WAVE:
		return "Start the game first"
	if not Data.TOWERS.has(type):
		return "Pick a tower first (keys 1 to 3)"
	if not Board.in_bounds(cell):
		return "That is outside the board"
	if board.is_path(cell):
		return "You can't build on the path"
	if _tower_at.has(cell):
		return "There is already a tower there"
	var cost: int = Data.TOWERS[type]["cost"]
	if gold < cost:
		return "Not enough gold (need %d)" % cost
	return ""


## Build a tower. Returns the tower, or null (and shows why) if it can't be built.
func build(cell: Vector2i, type: String):
	var problem := build_problem(cell, type)
	if problem != "":
		hud.toast(problem)
		return null
	var cost: int = Data.TOWERS[type]["cost"]
	gold -= cost
	var tower = TowerScript.new()
	tower.position = Board.cell_center(cell)
	_towers_node.add_child(tower)
	tower.setup(type, cell)
	tower.fired.connect(_on_tower_fired)
	towers.append(tower)
	_tower_at[cell] = tower
	_refresh_hud()
	return tower


## Why the selected tower can't be upgraded right now, or "" if it can.
func upgrade_problem(tower) -> String:
	if state != State.BUILD and state != State.WAVE:
		return "The game is not running"
	if tower == null:
		return "Click a tower first"
	if tower.level >= Data.MAX_LEVEL:
		return "That tower is already at the top level"
	var cost := Data.upgrade_cost(tower.type, tower.level + 1)
	if gold < cost:
		return "Not enough gold (need %d)" % cost
	return ""


func upgrade(tower) -> bool:
	var problem := upgrade_problem(tower)
	if problem != "":
		hud.toast(problem)
		return false
	gold -= Data.upgrade_cost(tower.type, tower.level + 1)
	tower.upgrade()
	_refresh_hud()
	return true


func upgrade_selected() -> bool:
	return upgrade(selected)


## Sell a tower for 70% of everything spent on it. Returns the gold gained.
func sell(tower) -> int:
	if (state != State.BUILD and state != State.WAVE) or tower == null or not towers.has(tower):
		return 0
	var refund := Data.sell_value(tower.type, tower.level)
	gold += refund
	towers.erase(tower)
	_tower_at.erase(tower.cell)
	if selected == tower:
		selected = null
	tower.queue_free()
	_refresh_hud()
	return refund


func sell_selected() -> int:
	return sell(selected)


func tower_at(cell: Vector2i):
	return _tower_at.get(cell, null)


## Pick a tower type in the palette (picking the same one again puts it away).
func choose_tower(type: String) -> void:
	if state == State.BUILD or state == State.WAVE:
		build_choice = "" if build_choice == type else type
		selected = null
	_refresh_hud()      # also puts the palette buttons back in step with the choice


func select_tower(tower) -> void:
	selected = tower
	_refresh_hud()


func cancel() -> void:
	build_choice = ""
	selected = null
	_refresh_hud()


## What a click on this grid cell does.
func click_cell(cell: Vector2i) -> void:
	if state != State.BUILD and state != State.WAVE:
		return
	if build_choice != "":
		build(cell, build_choice)
	else:
		select_tower(tower_at(cell))


# --- the screen --------------------------------------------------------------------

func tower_info(tower) -> Dictionary:
	var next_cost := -1
	if tower.level < Data.MAX_LEVEL:
		next_cost = Data.upgrade_cost(tower.type, tower.level + 1)
	return {
		"name": Data.TOWERS[tower.type]["name"],
		"level": tower.level,
		"damage": tower.stats["damage"],
		"range": tower.stats["range"],
		"cooldown": tower.stats["cooldown"],
		"slow": tower.stats["slow"],
		"splash": tower.stats["splash"],
		"upgrade_cost": next_cost,
		"sell_value": Data.sell_value(tower.type, tower.level),
		"can_upgrade": next_cost >= 0 and gold >= next_cost,
	}


func _refresh_hud() -> void:
	hud.set_gold(gold)
	hud.set_lives(lives)
	hud.set_wave(wave, Data.final_wave())
	hud.set_speed(speed_multiplier)
	hud.set_palette(gold, build_choice)
	var can_start := state == State.BUILD and wave < Data.final_wave()
	var label := "Start wave %d (Space)" % (wave + 1)
	if state == State.WAVE:
		label = "Wave %d in progress" % wave
	elif not can_start:
		label = "Start wave"
	hud.set_start_button(label, can_start)
	if selected != null and is_instance_valid(selected):
		hud.show_tower(tower_info(selected))
	else:
		hud.hide_tower()
	overlay.queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(960, 540)), GROUND_A)
	for col in Data.GRID_COLS:
		for row in Data.GRID_ROWS:
			var cell := Vector2i(col, row)
			var rect := Rect2(Data.GRID_ORIGIN + Vector2(col, row) * Data.CELL, Vector2(Data.CELL, Data.CELL))
			if board.is_path(cell):
				draw_rect(rect, PATH_COLOR)
			elif (col + row) % 2 == 1:
				draw_rect(rect, GROUND_B)
			draw_rect(rect, Color(1, 1, 1, 0.04), false, 1.0)
	# a green arrow where enemies come in, a red one where they must not get out
	_draw_arrow(Board.cell_center(Vector2i(0, 1)), Color(0.45, 0.9, 0.5, 0.8))
	_draw_arrow(Board.cell_center(Vector2i(Data.GRID_COLS - 1, 8)), Color(0.95, 0.4, 0.4, 0.9))


func _draw_arrow(center: Vector2, color: Color) -> void:
	draw_colored_polygon(
		PackedVector2Array([center + Vector2(-8, -12), center + Vector2(10, 0), center + Vector2(-8, 12)]), color)


## The keyboard controls are registered here in code, so the whole project is
## readable as plain text.
func _register_input_actions() -> void:
	var keys := {
		"start": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
		"speed": [KEY_F],
		"cancel": [KEY_ESCAPE],
		"upgrade": [KEY_U],
		"sell": [KEY_X, KEY_DELETE],
		"tower_1": [KEY_1, KEY_KP_1],
		"tower_2": [KEY_2, KEY_KP_2],
		"tower_3": [KEY_3, KEY_KP_3],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for keycode in keys[action]:
			var event := InputEventKey.new()
			event.physical_keycode = keycode
			InputMap.action_add_event(action, event)
