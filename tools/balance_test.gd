extends SceneTree
## Plays whole games with a simple scripted "player" to check the difficulty,
## without a window:
##
##   godot --headless --path . --script res://tools/balance_test.gd
##
## Each plan is a list of steps (build this tower here, upgrade the tower there).
## The player does the next step whenever it has the gold, before each wave and
## once a second during a wave. The checks at the end say what the plans must do:
## doing nothing must lose early, a careful plan must win, a hasty plan (same
## towers, worse order) must do no better, and a lazy plan (cheap towers, never
## upgraded) must not win. That is the point of the numbers in data.gd: the
## order you spend your gold in matters.

const Data := preload("res://scripts/data.gd")
const MainScene := preload("res://scenes/main.tscn")

const DT := 1.0 / 60.0

var main
var State
var _checks := 0
var _failures := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	main = MainScene.instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	await process_frame
	State = main.State

	var idle := _play("no towers at all", [])
	var lazy := _play("pellet towers only, never upgraded", _lazy_plan())
	var hasty := _play("a hasty mix: upgrades first, fewer towers early", _hasty_plan())
	var careful := _play("a careful mix: more towers first, then upgrades", _careful_plan())

	print("")
	_check(idle["state"] == State.LOST and idle["wave"] <= 4, "doing nothing loses by wave 4 (lost on wave %d)" % idle["wave"])
	_check(careful["state"] == State.WON, "a careful plan wins")
	_check(careful["lives"] >= 8, "and wins comfortably (%d lives left)" % careful["lives"])
	_check(careful["lives"] <= 19, "but not without a scratch (%d lives left)" % careful["lives"])
	_check(hasty["state"] == State.LOST or hasty["lives"] < careful["lives"],
		"the hasty order does worse than the careful one (%s)" % _summary(hasty))
	_check(lazy["state"] == State.LOST, "a lazy plan of cheap, never-upgraded towers does not win (wave %d)" % lazy["wave"])

	print("%d checks, %d failed" % [_checks, _failures])
	quit(_failures)


# --- the plans -------------------------------------------------------------------

func _build(col: int, row: int, type: String) -> Array:
	return ["build", Vector2i(col, row), type]


func _up(col: int, row: int) -> Array:
	return ["upgrade", Vector2i(col, row)]


func _lazy_plan() -> Array:
	var plan: Array = []
	for cell in [Vector2i(7, 5), Vector2i(9, 5), Vector2i(7, 3), Vector2i(9, 3), Vector2i(8, 4),
			Vector2i(13, 4), Vector2i(15, 4), Vector2i(13, 6), Vector2i(15, 6), Vector2i(14, 5),
			Vector2i(19, 7), Vector2i(19, 9), Vector2i(21, 7), Vector2i(21, 9), Vector2i(6, 3),
			Vector2i(10, 5), Vector2i(6, 6), Vector2i(10, 3), Vector2i(12, 4), Vector2i(16, 4)]:
		plan.append(["build", cell, "pellet"])
	return plan


func _careful_plan() -> Array:
	return [
		_build(7, 5, "pellet"), _build(9, 5, "pellet"), _build(13, 5, "pellet"),
		_up(7, 5), _up(9, 5),
		_build(9, 3, "cannon"), _build(7, 3, "frost"),
		_up(13, 5), _build(15, 5, "pellet"), _build(14, 6, "cannon"),
		_up(9, 3), _up(14, 6), _up(7, 5), _up(9, 5),
		_build(14, 4, "frost"), _up(15, 5),
		_build(19, 7, "pellet"), _build(19, 9, "cannon"), _up(19, 7), _up(19, 9),
		_up(13, 5), _up(7, 3), _up(14, 4), _up(15, 5),
	]


## The same towers as the careful plan, but upgrading the first two before
## building a third, and the specialist towers before the next pellet towers.
func _hasty_plan() -> Array:
	return [
		_build(7, 5, "pellet"), _build(9, 5, "pellet"),
		_up(7, 5), _up(9, 5),
		_build(7, 3, "frost"), _build(9, 3, "cannon"),
		_build(13, 5, "pellet"), _up(13, 5), _build(15, 5, "pellet"), _up(15, 5),
		_build(14, 4, "frost"), _build(14, 6, "cannon"),
		_up(7, 5), _up(9, 5), _up(9, 3), _up(14, 6),
		_build(19, 7, "pellet"), _build(19, 9, "cannon"), _up(19, 7), _up(19, 9),
		_up(13, 5), _up(15, 5), _up(7, 3), _up(14, 4),
	]


func _summary(result: Dictionary) -> String:
	if result["state"] == State.LOST:
		return "lost on wave %d" % result["wave"]
	return "won with %d lives" % result["lives"]


# --- playing ---------------------------------------------------------------------

func _play(name: String, plan: Array) -> Dictionary:
	main.start_game()
	var step := 0
	var ticks := 0
	var last_wave_lives: int = main.lives
	print("== %s" % name)
	while main.state == State.BUILD or main.state == State.WAVE:
		if main.state == State.BUILD:
			step = _spend(plan, step)
			main.start_wave()
		main.tick(DT)
		ticks += 1
		if ticks % 60 == 0:
			step = _spend(plan, step)
		if main.state == State.BUILD or main.state == State.WON:
			# a wave has just ended
			print("   wave %2d cleared: lives %2d (lost %d), gold %4d, %2d towers"
				% [main.wave, main.lives, last_wave_lives - main.lives, main.gold, main.towers.size()])
			last_wave_lives = main.lives
		if ticks > 400000:
			break
	var result := {"state": main.state, "wave": main.wave, "lives": main.lives}
	if main.state == State.LOST:
		print("   LOST on wave %d" % main.wave)
	else:
		print("   WON with %d lives left (%d plan steps done of %d)" % [main.lives, step, plan.size()])
	return result


## Do plan steps in order for as long as the gold lasts. Returns the next step.
func _spend(plan: Array, step: int) -> int:
	while step < plan.size():
		var item: Array = plan[step]
		var cell: Vector2i = item[1]
		if item[0] == "build":
			var problem: String = main.build_problem(cell, item[2])
			if problem.begins_with("Not enough gold"):
				break
			if problem == "":
				main.build(cell, item[2])
			else:
				print("   (skipping %s at %s: %s)" % [item[2], cell, problem])
		else:
			var tower = main.tower_at(cell)
			if tower != null:
				var problem: String = main.upgrade_problem(tower)
				if problem.begins_with("Not enough gold"):
					break
				if problem == "":
					main.upgrade(tower)
		step += 1
	return step


func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
	print(("PASS  " if condition else "FAIL  ") + description)
