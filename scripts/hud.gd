extends CanvasLayer
## The on-screen controls: the top bar (gold, lives, wave, buttons), the bottom
## bar (tower palette and the selected tower's panel), a short "toast" message
## and the big centre message. It is built in code, so there is no scene layout
## to hunt through. It only shows things and reports button presses with signals;
## the game manager decides what they mean.

signal tower_chosen(type)
signal start_wave_pressed
signal speed_pressed
signal upgrade_pressed
signal sell_pressed

const Data := preload("res://scripts/data.gd")

const BAR_COLOR := Color(0.07, 0.08, 0.11)
const GOLD_COLOR := Color(0.97, 0.82, 0.35)
const LIVES_COLOR := Color(0.95, 0.5, 0.5)
const TOAST_SECONDS := 2.2

var _gold_label: Label
var _lives_label: Label
var _wave_label: Label
var _start_button: Button
var _speed_button: Button
var _palette := {}             # tower type -> its button
var _info_label: Label
var _hint_label: Label
var _upgrade_button: Button
var _sell_button: Button
var _toast_label: Label
var _backdrop: ColorRect
var _message_label: Label
var _toast_left := 0.0


func _ready() -> void:
	_build_top_bar()
	_build_bottom_bar()
	_build_toast_and_message()


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast_label.visible = false


# --- what the game manager can change ---------------------------------------------

func set_gold(amount: int) -> void:
	_gold_label.text = "Gold: %d" % amount


func set_lives(amount: int) -> void:
	_lives_label.text = "Lives: %d" % amount


func set_wave(current: int, total: int) -> void:
	_wave_label.text = "Wave %d / %d" % [current, total]


func set_speed(multiplier: int) -> void:
	_speed_button.text = "Speed %dx (F)" % multiplier


func set_start_button(text: String, enabled: bool) -> void:
	_start_button.text = text
	_start_button.disabled = not enabled


## Show which tower is picked, and dim the ones that cost more than `gold`.
func set_palette(gold: int, choice: String) -> void:
	for type in _palette:
		var button: Button = _palette[type]
		button.set_pressed_no_signal(type == choice)
		var cost: int = Data.TOWERS[type]["cost"]
		button.modulate = Color.WHITE if gold >= cost else Color(1, 1, 1, 0.45)


func show_tower(info: Dictionary) -> void:
	var lines: Array[String] = [
		"%s  -  level %d" % [info["name"], info["level"]],
		"Damage %.0f     Range %.0f" % [info["damage"], info["range"]],
		"Reload %.2f s" % info["cooldown"],
	]
	var slow: float = info["slow"]
	var splash: float = info["splash"]
	if slow < 1.0:
		lines.append("Slows enemies to %d%% speed" % roundi(slow * 100.0))
	elif splash > 0.0:
		lines.append("Blast radius %.0f" % splash)
	_info_label.text = "\n".join(lines)
	_info_label.visible = true
	_hint_label.visible = false
	var next_cost: int = info["upgrade_cost"]
	_upgrade_button.visible = true
	_upgrade_button.text = "Upgrade (U)  $%d" % next_cost if next_cost >= 0 else "Top level"
	_upgrade_button.disabled = not info["can_upgrade"]
	_sell_button.visible = true
	_sell_button.text = "Sell (X)  +$%d" % info["sell_value"]


func hide_tower() -> void:
	_info_label.visible = false
	_upgrade_button.visible = false
	_sell_button.visible = false
	_hint_label.visible = true


func toast(text: String) -> void:
	_toast_label.text = text
	_toast_label.visible = true
	_toast_left = TOAST_SECONDS


func toast_text() -> String:
	return _toast_label.text if _toast_label.visible else ""


func show_message(text: String) -> void:
	_message_label.text = text
	_message_label.visible = true
	_backdrop.visible = true


func hide_message() -> void:
	_message_label.visible = false
	_backdrop.visible = false


func message_text() -> String:
	return _message_label.text if _message_label.visible else ""


# --- building the controls ----------------------------------------------------------

func _build_top_bar() -> void:
	_add_bar(Rect2(0, 0, 960, 60))
	_gold_label = _add_label(Vector2(20, 12), Vector2(160, 36), 26, GOLD_COLOR)
	_lives_label = _add_label(Vector2(190, 12), Vector2(150, 36), 26, LIVES_COLOR)
	_wave_label = _add_label(Vector2(350, 12), Vector2(190, 36), 26, Color.WHITE)
	_start_button = _add_button(Rect2(556, 10, 250, 40), 18)
	_start_button.pressed.connect(func(): start_wave_pressed.emit())
	_speed_button = _add_button(Rect2(816, 10, 128, 40), 18)
	_speed_button.pressed.connect(func(): speed_pressed.emit())


func _build_bottom_bar() -> void:
	_add_bar(Rect2(0, 460, 960, 80))
	for i in Data.TOWER_ORDER.size():
		var type: String = Data.TOWER_ORDER[i]
		var stats: Dictionary = Data.TOWERS[type]
		var button := _add_button(Rect2(16 + i * 176, 470, 168, 60), 16)
		button.toggle_mode = true
		button.text = "%d  %s   $%d\n%s" % [i + 1, stats["name"], stats["cost"], stats["blurb"]]
		var color: Color = stats["color"]
		button.add_theme_color_override("font_color", color)
		button.add_theme_color_override("font_hover_color", color.lightened(0.3))
		button.add_theme_color_override("font_pressed_color", color.lightened(0.3))
		button.pressed.connect(func(): tower_chosen.emit(type))
		_palette[type] = button

	_info_label = _add_label(Vector2(560, 466), Vector2(230, 72), 15, Color(0.85, 0.88, 0.95))
	_hint_label = _add_label(Vector2(560, 478), Vector2(380, 50), 15, Color(0.6, 0.65, 0.75))
	_hint_label.text = "Click a tower to upgrade or sell it.\nPress F to change the game speed."
	_upgrade_button = _add_button(Rect2(796, 466, 148, 32), 15)
	_upgrade_button.pressed.connect(func(): upgrade_pressed.emit())
	_sell_button = _add_button(Rect2(796, 502, 148, 32), 15)
	_sell_button.pressed.connect(func(): sell_pressed.emit())
	hide_tower()


func _build_toast_and_message() -> void:
	_toast_label = _add_label(Vector2(0, 68), Vector2(960, 32), 20, Color(1, 0.9, 0.6))
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_toast_label.add_theme_constant_override("outline_size", 6)
	_toast_label.visible = false

	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0.8)
	_backdrop.position = Vector2.ZERO
	_backdrop.size = Vector2(960, 540)
	add_child(_backdrop)

	_message_label = _add_label(Vector2.ZERO, Vector2(960, 540), 28, Color.WHITE)
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_message_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_message_label.add_theme_constant_override("outline_size", 8)
	hide_message()


func _add_bar(rect: Rect2) -> void:
	var bar := ColorRect.new()
	bar.color = BAR_COLOR
	bar.position = rect.position
	bar.size = rect.size
	add_child(bar)


func _add_label(at: Vector2, label_size: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = label_size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label


func _add_button(rect: Rect2, font_size: int) -> Button:
	var button := Button.new()
	button.position = rect.position
	button.size = rect.size
	button.focus_mode = Control.FOCUS_NONE    # so Space and Enter keep starting waves
	button.add_theme_font_size_override("font_size", font_size)
	add_child(button)
	return button
