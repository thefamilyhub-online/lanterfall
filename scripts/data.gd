extends RefCounted
## Game data for Phase 1: towers, Snuffers, heroes, combos, waves and the
## Gumdrop Glade map. Numbers are first targets for playtesting.

const START_COINS := 400
const PIP_MAX := 100.0
const FIRST_BUILD_TIME := 40.0
const BUILD_TIME := 25.0
const EARLY_CALL_PER_SECOND := 2
const SELL_REFUND := 0.8
const SPAWN_GAP := 0.8
const LAST_WAVE := 15
const BOSS_WAVE := 16
const GLOW_MIN_RADIUS := 2.0
const GLOW_MAX_RADIUS := 6.0
const GLOW_RATE_BONUS := 1.10
const BUILD_REACH := 4.0
const HERO_SPEED := 4.0
const GIFT_STEP := 25

# ------------------------------------------------------------------ towers
# tiers: index 0 = tier 1. "air" = can hit Flutters.
const TOWERS := {
	"pebble_popper": {
		name = "Pebble Popper", cost = 100, upgrade = [75, 125], air = true, kind = "single",
		damage = [6.0, 9.0, 13.0], range = [3.0, 3.3, 3.6], rate = [1.4, 1.6, 1.9],
		blurb = "Fast single shots. Hits flyers.",
	},
	"jelly_lobber": {
		name = "Jelly Lobber", cost = 150, upgrade = [110, 190], air = false, kind = "splash",
		damage = [8.0, 12.0, 17.0], range = [3.5, 3.7, 4.0], rate = [0.6, 0.7, 0.8], splash = [1.0, 1.1, 1.25],
		blurb = "Splashes groups. Can't hit flyers.",
	},
	"frost_puff": {
		name = "Frost Puff", cost = 125, upgrade = [95, 155], air = true, kind = "pulse",
		damage = [1.0, 2.0, 3.0], range = [2.2, 2.5, 2.8], rate = [1.0, 1.0, 1.0],
		slow = [0.30, 0.38, 0.45], slow_time = 1.2,
		blurb = "Chills everything nearby. Hits flyers.",
	},
	"hedge_block": {
		name = "Hedge Block", cost = 20, upgrade = [], air = false, kind = "wall",
		blurb = "Cheap wall to shape the path.",
	},
}
const TOWER_ORDER := ["pebble_popper", "jelly_lobber", "frost_puff", "hedge_block"]
const TOWER_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4]

# ------------------------------------------------------------------ combos
# Two towers owned by DIFFERENT players, side by side (including diagonals).
const COMBOS := [
	{id = "slushy", name = "Slushy", a = "frost_puff", b = "jelly_lobber",
		text = "Jelly freezes what it hits for a moment."},
	{id = "ice_pebbles", name = "Ice Pebbles", a = "frost_puff", b = "pebble_popper",
		text = "Pebbles slow what they hit."},
	{id = "hedge_watch", name = "Hedge Watch", a = "hedge_block", b = "pebble_popper",
		text = "The Popper sees farther from behind the hedge."},
	{id = "hedge_watch", name = "Hedge Watch", a = "hedge_block", b = "jelly_lobber",
		text = "The Lobber sees farther from behind the hedge."},
]
const SLUSHY_FREEZE := 0.8
const ICE_PEBBLE_SLOW := 0.2
const ICE_PEBBLE_TIME := 1.5
const HEDGE_WATCH_RANGE := 0.75

# ------------------------------------------------------------------ snuffers
const SNUFFER_TYPES := ["scamper", "shellback", "flutter", "big_shellback"]
const SNUFFERS := {
	"scamper": {name = "Scamper", hp = 20.0, armor = 0.0, speed = 2.6, reward = 4, damage = 3.0, air = false, size = 0.8},
	"shellback": {name = "Shellback", hp = 60.0, armor = 3.0, speed = 1.4, reward = 9, damage = 6.0, air = false, size = 1.0},
	"flutter": {name = "Flutter", hp = 28.0, armor = 0.0, speed = 2.0, reward = 7, damage = 4.0, air = true, size = 0.9},
	"big_shellback": {name = "Big Shellback", hp = 900.0, armor = 4.0, speed = 0.8, reward = 150, damage = 40.0, air = false, size = 2.2,
		sheds = [0.66, 0.33], shed_count = 3},
}
const HP_GROWTH := 0.22  # +22% health per wave


static func wave_hp_scale(wave: int) -> float:
	return 1.0 + HP_GROWTH * float(wave - 1)


## A surprise mix for this wave. Seeded so a wave is the same for everyone.
static func wave_list(wave: int, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	if wave == BOSS_WAVE:
		out.append("big_shellback")
		for i in 6:
			out.append("scamper")
		return out
	var count := 6 + wave * 2
	for i in count:
		var roll := rng.randf()
		if wave >= 4 and roll < 0.22:
			out.append("flutter")
		elif wave >= 3 and roll < 0.22 + min(0.12 + wave * 0.02, 0.35):
			out.append("shellback")
		else:
			out.append("scamper")
	return out


static func wave_clear_bonus(wave: int) -> int:
	return 40 + 5 * wave


# ------------------------------------------------------------------ heroes
const HEROES := {
	"bramble": {name = "Bramble", role = "Builder",
		passive = "Your towers cost 10% less.",
		ability = "Rush Build", ability_text = "Your next 3 towers are 25% cheaper.", cooldown = 60.0},
	"glint": {name = "Glint", role = "Booster",
		passive = "Towers near Glint fire 10% faster.",
		ability = "Overcharge", ability_text = "The nearest tower fires twice as fast for 8 seconds.", cooldown = 45.0},
}
const HERO_ORDER := ["bramble", "glint"]
const BRAMBLE_DISCOUNT := 0.9
const RUSH_DISCOUNT := 0.75
const RUSH_CHARGES := 3
const GLINT_AURA_RANGE := 3.0
const GLINT_AURA_BONUS := 1.10
const OVERCHARGE_TIME := 8.0

# ------------------------------------------------------------------ Gumdrop Glade
const MAP := {
	name = "Gumdrop Glade",
	w = 24, h = 14,
	entrances = [Vector2i(0, 3), Vector2i(0, 10)],
	gate_entrance = 1,  # the lower entrance has the licorice gate
	pip = Vector2i(23, 7),
	rocks = [Vector2i(6, 0), Vector2i(6, 1), Vector2i(5, 13), Vector2i(12, 12), Vector2i(12, 13),
		Vector2i(17, 2), Vector2i(18, 2), Vector2i(17, 3), Vector2i(20, 12), Vector2i(21, 12)],
	syrup = [Vector2i(10, 5), Vector2i(11, 5), Vector2i(10, 6), Vector2i(11, 6),
		Vector2i(15, 9), Vector2i(16, 9), Vector2i(15, 10), Vector2i(16, 10)],
	trees = [Vector2(-1.4, -1.0), Vector2(-1.3, 14.6), Vector2(8.0, -1.3), Vector2(14.5, 15.0),
		Vector2(25.2, 2.0), Vector2(25.3, 12.0), Vector2(19.0, -1.4), Vector2(3.0, 15.2)],
}
const SYRUP_SLOW := 0.3
const GATE_COST := 75
const GATE_WAVES := 2
const GATE_COOLDOWN_WAVES := 3
