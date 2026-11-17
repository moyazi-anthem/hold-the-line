extends RefCounted
## Every number that shapes how the game plays, in one place: the board size,
## the path, the towers, the enemies and the waves. Change a number here and the
## whole game follows. Nothing in this file needs a scene.
##
## Other scripts use it like this:
##   const Data := preload("res://scripts/data.gd")
##   Data.TOWERS["pellet"]["cost"]

# --- the board ---------------------------------------------------------------
const CELL := 40                          # one grid square is 40 x 40 pixels
const GRID_COLS := 24
const GRID_ROWS := 10
const GRID_ORIGIN := Vector2(0, 60)       # the top bar is above the grid

## The corners of the enemy path, as grid cells (column, row). Enemies walk in a
## straight line from one corner to the next. The first corner is one cell left
## of the board and the last is one cell right of it, so enemies walk in from
## the left edge and leave through the right edge.
const PATH_CORNERS: Array[Vector2i] = [
	Vector2i(-1, 1), Vector2i(5, 1), Vector2i(5, 7), Vector2i(11, 7),
	Vector2i(11, 2), Vector2i(17, 2), Vector2i(17, 8), Vector2i(24, 8),
]

# --- the player's side ---------------------------------------------------------
const START_GOLD := 150
const START_LIVES := 20
const WAVE_BONUS := 25                    # gold for clearing a wave
const SELL_RATIO := 0.7                   # selling returns 70% of what was spent
const MAX_LEVEL := 3
## What an upgrade costs, as a share of the tower's base cost, by target level.
const UPGRADE_COST_RATIO := {2: 0.6, 3: 0.9}

# --- towers --------------------------------------------------------------------
## "damage" is per shot. "cooldown" is seconds between shots. "slow" is the
## speed an enemy keeps while slowed (1.0 = no slow, 0.5 = half speed) and
## "slow_time" is how long that lasts. "splash" is the blast radius in pixels
## (0 = the shot hits only its target). "projectile_speed" is pixels per second.
const TOWER_ORDER := ["pellet", "frost", "cannon"]
const TOWERS := {
	"pellet": {
		"name": "Pellet", "cost": 50, "range": 130.0, "damage": 10.0, "cooldown": 0.55,
		"slow": 1.0, "slow_time": 0.0, "splash": 0.0, "projectile_speed": 450.0,
		"color": Color(0.45, 0.85, 0.50),
		"blurb": "Fast and cheap",
	},
	"frost": {
		"name": "Frost", "cost": 70, "range": 110.0, "damage": 3.0, "cooldown": 0.8,
		"slow": 0.5, "slow_time": 2.0, "splash": 0.0, "projectile_speed": 380.0,
		"color": Color(0.45, 0.80, 0.95),
		"blurb": "Slows enemies",
	},
	"cannon": {
		"name": "Cannon", "cost": 120, "range": 150.0, "damage": 30.0, "cooldown": 1.5,
		"slow": 1.0, "slow_time": 0.0, "splash": 52.0, "projectile_speed": 300.0,
		"color": Color(0.95, 0.80, 0.40),
		"blurb": "Area damage",
	},
}

# --- enemies -------------------------------------------------------------------
## "leak" is how many lives it costs you when the enemy reaches the exit.
const ENEMIES := {
	"grunt": {
		"name": "Grunt", "hp": 30.0, "speed": 70.0, "reward": 5, "leak": 1,
		"radius": 11.0, "color": Color(0.88, 0.33, 0.33),
	},
	"runner": {
		"name": "Runner", "hp": 18.0, "speed": 125.0, "reward": 4, "leak": 1,
		"radius": 9.0, "color": Color(0.95, 0.45, 0.75),
	},
	"tank": {
		"name": "Tank", "hp": 140.0, "speed": 42.0, "reward": 18, "leak": 3,
		"radius": 15.0, "color": Color(0.62, 0.40, 0.85),
	},
}

## Every enemy gets this much more health per wave after the first (40% each).
const WAVE_HP_GROWTH := 0.40
## Seconds of calm between two groups in the same wave.
const GROUP_PAUSE := 2.0

## Each wave is a list of groups. A group is "count" enemies of one "type",
## one every "gap" seconds. The next group starts GROUP_PAUSE after the last.
const WAVES := [
	[{"type": "grunt", "count": 6, "gap": 1.0}],
	[{"type": "grunt", "count": 10, "gap": 0.8}],
	[{"type": "runner", "count": 8, "gap": 0.6}],
	[{"type": "grunt", "count": 10, "gap": 0.7}, {"type": "runner", "count": 6, "gap": 0.5}],
	[{"type": "tank", "count": 2, "gap": 3.0}, {"type": "grunt", "count": 12, "gap": 0.6}],
	[{"type": "runner", "count": 14, "gap": 0.4}],
	[{"type": "tank", "count": 4, "gap": 2.5}, {"type": "grunt", "count": 14, "gap": 0.5}],
	[{"type": "grunt", "count": 20, "gap": 0.45}, {"type": "runner", "count": 16, "gap": 0.3}],
	[{"type": "tank", "count": 8, "gap": 1.8}, {"type": "runner", "count": 16, "gap": 0.35}],
	[
		{"type": "tank", "count": 10, "gap": 1.3},
		{"type": "grunt", "count": 24, "gap": 0.35},
		{"type": "runner", "count": 20, "gap": 0.25},
	],
]


static func final_wave() -> int:
	return WAVES.size()


## The spawn schedule of a wave (1 = the first): a list of
## {"at": seconds since the wave started, "type": enemy id}, in time order.
static func wave_schedule(wave: int) -> Array:
	var schedule: Array = []
	var clock := 0.0
	for group in WAVES[wave - 1]:
		var count: int = group["count"]
		var gap: float = group["gap"]
		for i in count:
			schedule.append({"at": clock, "type": group["type"]})
			clock += gap
		clock += GROUP_PAUSE - gap       # `clock` is now one gap after the last spawn
	return schedule


static func enemy_hp(type: String, wave: int) -> float:
	var base: float = ENEMIES[type]["hp"]
	return base * (1.0 + WAVE_HP_GROWTH * (maxi(wave, 1) - 1))


## The numbers a tower of this type has at this level (1 to MAX_LEVEL). Each
## level adds 60% of the base damage, 10% range, and shortens the cooldown by
## 10% of its base; frost towers also slow harder.
static func tower_stats(type: String, level: int) -> Dictionary:
	var base: Dictionary = TOWERS[type]
	var steps := level - 1
	var base_slow: float = base["slow"]
	var slow: float = maxf(0.2, 1.0 - (1.0 - base_slow) * (1.0 + 0.2 * steps))
	var damage: float = base["damage"]
	var tower_range: float = base["range"]
	var cooldown: float = base["cooldown"]
	return {
		"damage": damage * (1.0 + 0.6 * steps),
		"range": tower_range * (1.0 + 0.1 * steps),
		"cooldown": cooldown * (1.0 - 0.1 * steps),
		"slow": slow,
		"slow_time": base["slow_time"],
		"splash": base["splash"],
		"projectile_speed": base["projectile_speed"],
	}


## Gold needed to bring a tower of this type up to `to_level`.
static func upgrade_cost(type: String, to_level: int) -> int:
	var cost: int = TOWERS[type]["cost"]
	var ratio: float = UPGRADE_COST_RATIO[to_level]
	return int(round(cost * ratio))


## Everything spent on a tower of this type at this level.
static func invested(type: String, level: int) -> int:
	var total: int = TOWERS[type]["cost"]
	for to_level in range(2, level + 1):
		total += upgrade_cost(type, to_level)
	return total


static func sell_value(type: String, level: int) -> int:
	return int(floor(invested(type, level) * SELL_RATIO))
