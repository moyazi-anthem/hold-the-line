extends SceneTree
## Saves screenshots of the game as PNG files. This needs a real window, so do
## NOT use --headless:
##
##   godot --path . --script res://tools/screenshot.gd -- docs
##
## The folder name after "--" is optional (default "docs", inside the project).
## It builds a defence, plays part of wave 7 by stepping the game by hand, and
## saves the title screen, the game in action and the win screen.

const Data := preload("res://scripts/data.gd")
const MainScene := preload("res://scenes/main.tscn")

const DT := 1.0 / 60.0

# the towers to place: [column, row, type, upgrades]
const LAYOUT := [
	[7, 5, "pellet", 2], [9, 5, "pellet", 2], [13, 5, "pellet", 1], [15, 5, "pellet", 1],
	[9, 3, "cannon", 1], [14, 6, "cannon", 1], [7, 3, "frost", 1], [14, 4, "frost", 0],
	[19, 7, "pellet", 1],
]


func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var folder := ProjectSettings.globalize_path("res://docs") if args.is_empty() else args[0]
	DirAccess.make_dir_recursive_absolute(folder)

	var main = MainScene.instantiate()
	root.add_child(main)
	main.set_physics_process(false)
	await create_timer(0.3).timeout
	await _save(folder.path_join("title.png"))

	main.start_game()
	main.gold = 5000
	for entry in LAYOUT:
		var tower = main.build(Vector2i(entry[0], entry[1]), entry[2])
		for i in int(entry[3]):
			main.upgrade(tower)
	main.gold = 85
	main.wave = 6
	main.start_wave()
	for i in int(16.0 / DT):
		main.tick(DT)
	main.select_tower(main.tower_at(Vector2i(9, 5)))
	main.hover_cell = Vector2i(-99, -99)
	await create_timer(0.3).timeout
	await _save(folder.path_join("gameplay.png"))

	main.wave = Data.final_wave() - 1
	main.state = main.State.BUILD
	main.start_wave()
	var guard := 0
	while main.state == main.State.WAVE and guard < 6000:
		main.tick(DT)
		for enemy in main.enemies.duplicate():
			enemy.take_damage(99999.0)
		guard += 1
	await create_timer(0.3).timeout
	await _save(folder.path_join("win.png"))
	quit()


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	print("saved %s (error code %d)" % [path, error])
