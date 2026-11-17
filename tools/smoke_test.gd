extends SceneTree
## Automated check of the game rules, run without a window:
##
##   godot --headless --path . --script res://tools/smoke_test.gd
##
## It builds towers, drops enemies in front of them, and steps the game forward
## with tick() (much faster than real time), then checks gold, lives, damage,
## slowing, waves, winning and losing. Exit code 0 means every check passed; any
## other number is the count of failed checks.

const Data := preload("res://scripts/data.gd")
const Board := preload("res://scripts/board.gd")
const MainScene := preload("res://scenes/main.tscn")

const DT := 1.0 / 60.0
const SPOT := Vector2i(8, 4)         # a free cell inside the first loop of the path

var _checks := 0
var _failures := 0
var main
var State


func _initialize() -> void:
	_run()


func _run() -> void:
	# A headless window is tiny, and the game's stretch settings would scale the
	# mouse positions sent below (a click at x=380 would land at x=5700). Turning
	# the scaling off for this test keeps the positions exact. How the real
	# window scales clicks is checked in a browser instead (see the README).
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(960, 540)
	main = MainScene.instantiate()
	root.add_child(main)
	main.set_physics_process(false)        # this script steps the game by hand
	await process_frame
	State = main.State

	_check_data()
	_check_map()
	await _check_title_and_start()
	_check_build_rules()
	_check_build_upgrade_sell()
	await _check_controls()
	_check_targeting()
	_check_combat()
	_check_slow()
	await _check_waves()
	await _check_losing()
	_check_winning()

	print("%d checks, %d failed" % [_checks, _failures])
	quit(_failures)


# --- the numbers -----------------------------------------------------------------

func _check_data() -> void:
	_check(Data.final_wave() == 10, "there are 10 waves")
	var known := true
	for wave in Data.WAVES:
		for group in wave:
			known = known and Data.ENEMIES.has(group["type"])
	_check(known, "every wave uses enemy types that exist")

	var one := Data.wave_schedule(1)
	_check(one.size() == 6 and _near(one[5]["at"], 5.0), "wave 1 is 6 grunts, one a second (last at %.1f s)" % one[5]["at"])
	var four := Data.wave_schedule(4)
	_check(four.size() == 16 and four[9]["type"] == "grunt" and four[10]["type"] == "runner",
		"wave 4 is 10 grunts then 6 runners")
	_check(_near(four[10]["at"], 8.3), "wave 4's runners start 2 s after the last grunt (%.2f s)" % four[10]["at"])

	_check(_near(Data.enemy_hp("grunt", 1), 30.0) and _near(Data.enemy_hp("grunt", 6), 90.0),
		"enemy health grows by 40% of its starting value per wave (30 on wave 1, 90 on wave 6)")
	_check(_near(Data.enemy_hp("tank", 0), 140.0), "enemies made before wave 1 (in tests) have their base health")
	_check(Data.upgrade_cost("pellet", 2) == 30 and Data.upgrade_cost("pellet", 3) == 45,
		"a pellet tower upgrades for $30 then $45")
	_check(Data.invested("pellet", 3) == 125, "a level 3 pellet tower cost $125 in total")
	_check(Data.sell_value("pellet", 1) == 35 and Data.sell_value("pellet", 3) == 87,
		"selling returns 70% rounded down ($35 at level 1, $87 at level 3)")
	_check(Data.sell_value("cannon", 3) == 210, "a level 3 cannon sells for $210")
	var l2 := Data.tower_stats("pellet", 2)
	var l3 := Data.tower_stats("pellet", 3)
	_check(_near(l2["damage"], 16.0) and _near(l3["damage"], 22.0), "each level adds 60% damage (10, 16, 22)")
	_check(_near(l2["range"], 143.0) and _near(l3["cooldown"], 0.44), "levels add range and shorten the cooldown")
	_check(_near(Data.tower_stats("frost", 1)["slow"], 0.5) and _near(Data.tower_stats("frost", 3)["slow"], 0.3),
		"frost slows to 50% at level 1 and 30% at level 3")


func _check_map() -> void:
	var board = main.board
	_check(board.path_cell_count() == 43, "the path covers 43 cells (%d)" % board.path_cell_count())
	_check(_near(board.length, 1680.0), "the path is 1680 px long (%.0f)" % board.length)
	_check(board.point_at(0.0).is_equal_approx(Vector2(-20, 120)), "the path starts just left of the board")
	_check(board.point_at(240.0).is_equal_approx(Vector2(220, 120)), "240 px along is the first corner")
	_check(board.point_at(board.length + 500.0).is_equal_approx(Vector2(980, 400)), "past the end is the exit")
	_check(board.is_path(Vector2i(5, 3)) and not board.is_path(SPOT), "(5,3) is on the path and the build spot is not")
	_check(Board.cell_at(Board.cell_center(Vector2i(7, 3))) == Vector2i(7, 3), "a cell's centre maps back to the cell")


# --- title and start ---------------------------------------------------------------

func _check_title_and_start() -> void:
	_check(main.state == State.TITLE, "the game starts on the title screen")
	_check(main.hud.message_text().contains("HOLD THE LINE"), "the title message is shown")
	_press("start")
	await process_frame
	_check(main.state == State.BUILD, "pressing start begins the game")
	_check(main.gold == 150 and main.lives == 20 and main.wave == 0, "a game starts with $150, 20 lives, wave 0")
	_check(main.hud.message_text() == "", "the message is hidden while playing")
	_check(main.hud._gold_label.text == "Gold: 150" and main.hud._lives_label.text == "Lives: 20",
		"the top bar shows gold and lives")
	_check(main.hud._start_button.text == "Start wave 1 (Space)" and not main.hud._start_button.disabled,
		"the start button offers wave 1")


# --- building ---------------------------------------------------------------------

func _check_build_rules() -> void:
	_check(main.build_problem(Vector2i(5, 3), "pellet").contains("path"), "you can't build on the path")
	_check(main.build_problem(Vector2i(30, 3), "pellet").contains("outside"), "you can't build outside the board")
	_check(main.build_problem(Vector2i(-1, 1), "pellet").contains("outside"), "the off-board start of the path is outside")
	_check(main.build_problem(SPOT, "laser").contains("Pick a tower"), "an unknown tower type is refused")
	main.gold = 10
	_check(main.build_problem(SPOT, "pellet").contains("Not enough gold"), "a tower you can't afford is refused")
	main.gold = 150
	_check(main.build_problem(SPOT, "pellet") == "", "a free cell with enough gold is fine")


func _check_build_upgrade_sell() -> void:
	var tower = main.build(SPOT, "pellet")
	_check(tower != null and main.gold == 100, "building a pellet tower costs $50 (gold is %d)" % main.gold)
	_check(main.tower_at(SPOT) == tower and main.towers.size() == 1, "the tower is registered on its cell")
	_check(tower.position.is_equal_approx(Board.cell_center(SPOT)), "the tower stands in the middle of its cell")
	_check(main.build(SPOT, "pellet") == null and main.gold == 100, "a second tower on the same cell is refused, free of charge")
	_check(main.hud.toast_text().contains("already a tower"), "the player is told why")
	_check(main.hud._gold_label.text == "Gold: 100", "the top bar shows the new gold")

	main.select_tower(tower)
	_check(main.hud._info_label.visible and main.hud._info_label.text.contains("Pellet  -  level 1"),
		"selecting a tower shows its panel")
	_check(main.hud._upgrade_button.text == "Upgrade (U)  $30" and not main.hud._upgrade_button.disabled,
		"the upgrade button shows the price")
	_check(main.hud._sell_button.text == "Sell (X)  +$35", "the sell button shows the refund")

	_check(main.upgrade_selected() and tower.level == 2 and main.gold == 70, "upgrading to level 2 costs $30")
	_check(_near(tower.stats["damage"], 16.0), "an upgraded tower hits harder")
	_check(main.upgrade_selected() and tower.level == 3 and main.gold == 25, "upgrading to level 3 costs $45")
	_check(main.upgrade_problem(tower).contains("top level"), "level 3 is the top")
	_check(main.hud._upgrade_button.text == "Top level" and main.hud._upgrade_button.disabled,
		"the upgrade button says so and is disabled")
	_check(main.sell_selected() == 87 and main.gold == 112, "selling a level 3 pellet returns $87")
	_check(main.towers.is_empty() and main.tower_at(SPOT) == null and main.selected == null,
		"a sold tower is gone and its cell is free again")
	_check(main.build_problem(SPOT, "pellet") == "", "the cell can be built on again")

	var second = main.build(SPOT, "pellet")
	main.gold = 5
	_check(main.upgrade_problem(second).contains("Not enough gold"), "an upgrade you can't afford is refused")
	main.select_tower(second)
	_check(main.hud._upgrade_button.disabled, "its button is disabled")
	main.sell(second)


# --- the controls ------------------------------------------------------------------

func _check_controls() -> void:
	main.gold = 150
	_press("tower_2")
	await process_frame
	_check(main.build_choice == "frost" and main.hud._palette["frost"].button_pressed, "key 2 picks the frost tower")
	_press("tower_2")
	await process_frame
	_check(main.build_choice == "" and not main.hud._palette["frost"].button_pressed, "pressing 2 again puts it away")
	_press("tower_1")
	await process_frame
	_press("cancel")
	await process_frame
	_check(main.build_choice == "", "Escape cancels the pick")

	main.gold = 60
	main._refresh_hud()
	_check(main.hud._palette["cannon"].modulate.a < 1.0 and is_equal_approx(main.hud._palette["pellet"].modulate.a, 1.0),
		"towers you can't afford are dimmed in the palette")

	# a real mouse click on the board
	main.gold = 150
	main.choose_tower("pellet")
	var cell := Vector2i(9, 3)
	await _click(Board.cell_center(cell), MOUSE_BUTTON_LEFT)
	_check(main.hover_cell == cell, "the game reads a click at a cell's centre as that cell (read %s)" % main.hover_cell)
	_check(main.tower_at(cell) != null and main.gold == 100, "a left click builds the picked tower")
	_check(main.build_choice == "pellet", "the pick stays active for the next tower")
	await _click(Board.cell_center(Vector2i(9, 3)), MOUSE_BUTTON_RIGHT)
	_check(main.build_choice == "", "a right click cancels the pick")
	await _click(Board.cell_center(cell), MOUSE_BUTTON_LEFT)
	_check(main.selected != null and main.selected == main.tower_at(cell), "clicking a tower selects it")
	await _click(Board.cell_center(Vector2i(14, 5)), MOUSE_BUTTON_LEFT)
	_check(main.selected == null, "clicking empty ground deselects")

	main.cycle_speed()
	_check(main.speed_multiplier == 2 and main.hud._speed_button.text == "Speed 2x (F)", "the speed button goes to 2x")
	main.cycle_speed()
	main.cycle_speed()
	_check(main.speed_multiplier == 1, "and back round to 1x after 3x")


# --- combat ------------------------------------------------------------------------

func _check_targeting() -> void:
	_fresh_game()
	var tower = main.build(SPOT, "pellet")
	_place_enemy("grunt", 330.0)
	var middle = _place_enemy("grunt", 360.0)
	var front = _place_enemy("grunt", 390.0)
	_check(tower.find_target(main.enemies) == front, "a tower shoots the enemy furthest along the path")
	main.enemies.erase(front)
	_check(tower.find_target(main.enemies) == middle, "and the next one once that has gone")
	_fresh_game()
	tower = main.build(SPOT, "pellet")
	_place_enemy("grunt", 100.0)
	_check(tower.find_target(main.enemies) == null, "an enemy out of range is ignored")


func _check_combat() -> void:
	# fire rate
	_fresh_game()
	var tower = main.build(SPOT, "pellet")
	var tank = _place_enemy("tank", 360.0)
	tank.hp = 1000.0
	tank.max_hp = 1000.0
	var shots := [0]
	tower.fired.connect(func(_t, _e): shots[0] += 1)
	_tick(120)
	_check(shots[0] == 4, "a pellet tower fires 4 times in 2 seconds (fired %d)" % shots[0])
	_check(tank.hp < 1000.0 and is_equal_approx(fmod(1000.0 - tank.hp, 10.0), 0.0),
		"each pellet that lands does 10 damage (took %.0f)" % (1000.0 - tank.hp))

	# a kill pays the reward
	_fresh_game()
	main.build(SPOT, "pellet")
	var gold_before: int = main.gold
	var grunt = _place_enemy("grunt", 360.0)
	_tick(200)
	_check(not grunt.alive and main.enemies.is_empty(), "three pellets kill a grunt and it is removed")
	_check(main.gold == gold_before + 5, "a grunt pays $5 (gold went %d -> %d)" % [gold_before, main.gold])

	# splash damage
	_fresh_game()
	main.build(SPOT, "cannon")
	var near_a = _place_enemy("tank", 360.0)
	var near_b = _place_enemy("tank", 380.0)
	var far = _place_enemy("tank", 250.0)
	_tick(40)
	_check(_near(near_a.hp, 110.0) and _near(near_b.hp, 110.0),
		"a cannon shell hurts every enemy near the impact (140 -> %.0f and %.0f)" % [near_a.hp, near_b.hp])
	_check(_near(far.hp, 140.0), "but not one 110 px away")

	# a shell goes on to where its target was
	_fresh_game()
	main.build(SPOT, "cannon")
	var survivor = _place_enemy("tank", 360.0)
	var doomed = _place_enemy("tank", 380.0)
	_tick(1)
	_check(main.projectiles.size() == 1, "the cannon fired at the front enemy")
	doomed.take_damage(9999.0)
	_tick(40)
	_check(main.projectiles.is_empty() and _near(survivor.hp, 110.0),
		"a shell whose target died still lands there and hurts its neighbour (%.0f)" % survivor.hp)

	# a pellet whose target died just fizzles
	_fresh_game()
	main.build(SPOT, "pellet")
	var victim = _place_enemy("grunt", 360.0)
	var bystander = _place_enemy("grunt", 359.0)
	_tick(1)
	victim.take_damage(9999.0)
	_tick(20)
	_check(main.projectiles.is_empty() and _near(bystander.hp, 30.0),
		"a pellet whose target died is removed and hurts nobody else")


func _check_slow() -> void:
	_fresh_game()
	var grunt = _place_enemy("grunt", 100.0)
	grunt.speed = 70.0
	grunt.apply_slow(0.5, 2.0)
	_check(grunt.is_slowed() and _near(grunt.speed_now(), 35.0), "a slowed grunt walks at half speed")
	grunt.apply_slow(0.8, 1.0)
	_check(_near(grunt.speed_now(), 35.0), "a weaker slow does not replace a stronger one")
	var before: float = grunt.distance
	grunt.advance(1.0)
	_check(_near(grunt.distance - before, 35.0), "it covers 35 px in a second")
	grunt.advance(1.1)
	_check(not grunt.is_slowed() and _near(grunt.speed_now(), 70.0), "the slow wears off after its 2 seconds")

	_fresh_game()
	main.build(Vector2i(7, 4), "frost")      # 80 px from the path: frost reaches only 110
	var runner = main.spawn_enemy("runner")
	runner.distance = 300.0
	runner.position = main.board.point_at(300.0)
	var slowed := false
	for i in 120:
		_tick(1)
		if runner.is_slowed():
			slowed = true
			break
	_check(slowed and _near(runner.speed_now(), 62.5), "a frost tower's shot slows an enemy to half speed")


# --- waves -------------------------------------------------------------------------

func _check_waves() -> void:
	_fresh_game()
	main.gold = 150
	_check(main.start_wave() and main.state == State.WAVE and main.wave == 1, "a wave can be started")
	_check(not main.start_wave(), "but not twice")
	_check(main.hud._start_button.disabled and main.hud._start_button.text == "Wave 1 in progress",
		"the start button is disabled during a wave")
	_tick(1)
	_check(main.enemies.size() == 1, "the first enemy appears at once")
	_tick(61)
	_check(main.enemies.size() == 2, "and the next one a second later")
	_tick(250)
	_check(main.enemies.size() == 6, "all 6 grunts of wave 1 are out after 5 seconds")

	# with no towers they all walk through: 6 lives, and the wave ends
	var guard := 0
	while main.state == State.WAVE and guard < 4000:
		_tick(1)
		guard += 1
	_check(main.state == State.BUILD and main.enemies.is_empty(), "the wave ends once nothing is left")
	_check(main.lives == 14, "six grunts that got through cost 6 lives (lives %d)" % main.lives)
	_check(main.gold == 175, "clearing the wave pays $25 (gold %d)" % main.gold)
	_check(main.hud.toast_text().contains("Wave 1 cleared"), "the player is told the wave is cleared")
	_check(main.hud._start_button.text == "Start wave 2 (Space)", "the start button offers wave 2")
	_press("start")
	await process_frame
	_check(main.state == State.WAVE and main.wave == 2, "Space starts the next wave")

	# a tank that gets through costs 3 lives
	_fresh_game()
	var tank = main.spawn_enemy("tank")
	tank.distance = main.board.length - 1.0
	_tick(60)
	_check(main.lives == 17, "a tank that leaks costs 3 lives (lives %d)" % main.lives)


func _check_losing() -> void:
	_fresh_game()
	main.lives = 2
	var harmless = main.build(Vector2i(22, 0), "pellet")     # nowhere near the path
	main.select_tower(harmless)
	_check(main.selected == harmless and main.hud._sell_button.visible, "(a tower is selected before the loss)")
	main.start_wave()
	var guard := 0
	while main.state == State.WAVE and guard < 4000:
		_tick(1)
		guard += 1
	_check(main.state == State.LOST and main.lives == 0, "running out of lives loses the game")
	_check(main.hud.message_text().contains("THE LINE BROKE"), "the game over message is shown")
	var frozen: int = main.enemies.size()
	var where: Vector2 = main.enemies[0].position if frozen > 0 else Vector2.ZERO
	_tick(30)
	_check(main.enemies.size() == frozen and (frozen == 0 or main.enemies[0].position == where),
		"the game stands still after losing")
	main.choose_tower("pellet")
	_check(main.build_choice == "", "no towers can be picked after losing")
	_check(main.selected == null and not main.hud._sell_button.visible, "the tower panel is closed after losing")
	_press("start")
	await process_frame
	_check(main.state == State.BUILD and main.gold == 150 and main.lives == 20 and main.wave == 0,
		"Enter starts a fresh game after losing")
	_check(main.enemies.is_empty() and main.towers.is_empty() and main.projectiles.is_empty(),
		"and the board is cleared")


func _check_winning() -> void:
	_fresh_game()
	main.wave = Data.final_wave() - 1
	main.start_wave()
	_check(main.wave == 10, "the last wave is wave 10")
	var guard := 0
	while main.state == State.WAVE and guard < 6000:
		_tick(1)
		for enemy in main.enemies.duplicate():
			enemy.take_damage(9999.0)      # stand-in for a perfect defence
		guard += 1
	_check(main.state == State.WON, "clearing the last wave wins the game")
	_check(main.hud.message_text().contains("YOU HELD THE LINE"), "the win message is shown")
	_check(main.lives == 20, "no lives were lost in the stand-in defence")
	_check(not main.start_wave(), "there is no wave 11")
	var gold_at_win: int = main.gold
	var spare = main.build(SPOT, "pellet")
	_check(spare == null and main.gold == gold_at_win, "nothing can be built after winning")
	_check(main.sell(null) == 0 and main.upgrade_problem(null).contains("not running"),
		"and nothing can be sold or upgraded")


# --- helpers -----------------------------------------------------------------------

## A fresh game with plenty of gold, so a check isn't spoiled by running short.
func _fresh_game() -> void:
	main.start_game()
	main.gold = 1000


## An enemy standing `distance` px along the path and not walking away.
func _place_enemy(type: String, distance: float):
	var enemy = main.spawn_enemy(type)
	enemy.distance = distance
	enemy.position = main.board.point_at(distance)
	enemy.speed = 0.0
	return enemy


func _tick(count: int) -> void:
	for i in count:
		main.tick(DT)


## Send a key press (as a named action). It reaches the game on the next frame,
## so callers `await process_frame` afterwards.
func _press(action: String) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)


func _click(at: Vector2, button: int) -> void:
	var press := InputEventMouseButton.new()
	press.position = at
	press.global_position = at
	press.button_index = button
	press.pressed = true
	Input.parse_input_event(press)
	await process_frame
	var release := InputEventMouseButton.new()
	release.position = at
	release.global_position = at
	release.button_index = button
	release.pressed = false
	Input.parse_input_event(release)
	await process_frame


func _near(a: float, b: float, tolerance := 0.01) -> bool:
	return absf(a - b) <= tolerance


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
	print(("PASS  " if condition else "FAIL  ") + description)
