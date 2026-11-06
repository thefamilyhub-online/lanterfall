extends RefCounted
## Game data: towers, Snuffers, heroes, combos, waves and the Gumdrop Glade
## map. Numbers are first targets for playtesting.

const START_COINS := 400
const PIP_MAX := 100.0
const FIRST_BUILD_TIME := 40.0
const BUILD_TIME := 25.0
const EARLY_CALL_PER_SECOND := 2
const SELL_REFUND := 0.8
const SPAWN_GAP := 0.8
const LAST_WAVE := 29
const BOSS_WAVE := 30
const MINI_BOSS_WAVES := {5: "big_splitblob", 10: "big_shellback", 15: "big_bubbleguard", 20: "big_shellback", 25: "big_splitblob"}
const GLOW_MIN_RADIUS := 2.0
const GLOW_MAX_RADIUS := 6.0
const GLOW_RATE_BONUS := 1.10
const BUILD_REACH := 4.0
const HERO_SPEED := 4.0
const GIFT_STEP := 25

# ------------------------------------------------------------------ towers
# tiers: index 0 = tier 1. "air" = can hit Flutters.
const TOWERS := {
	# ---- Shooters
	"pebble_popper": {
		name = "Pebble Popper", family = "shooter", cost = 100, upgrade = [75, 125], air = true, kind = "single",
		damage = [6.0, 9.0, 13.0], range = [3.0, 3.3, 3.6], rate = [1.4, 1.6, 1.9],
		blurb = "Fast single shots. Hits flyers.",
	},
	"starseed_sling": {
		name = "Starseed Sling", family = "shooter", cost = 175, upgrade = [120, 200], air = true, kind = "pierce",
		damage = [11.0, 16.0, 23.0], range = [4.5, 5.0, 5.5], rate = [0.7, 0.8, 0.9], pierce = [3, 4, 5],
		blurb = "Long-range seeds that pierce through several Snuffers.",
	},
	"beam_lantern": {
		name = "Beam Lantern", family = "shooter", cost = 300, upgrade = [200, 320], air = true, kind = "beam",
		damage = [3.0, 4.5, 6.5], range = [3.2, 3.5, 3.8], rate = [6.0, 6.0, 6.0], ramp = [0.12, 0.15, 0.18],
		blurb = "A steady beam that gets hotter the longer it holds one target. Great vs. bosses.",
	},
	# ---- Splash
	"jelly_lobber": {
		name = "Jelly Lobber", family = "splash", cost = 150, upgrade = [110, 190], air = false, kind = "splash",
		damage = [8.0, 12.0, 17.0], range = [3.5, 3.7, 4.0], rate = [0.6, 0.7, 0.8], splash = [1.0, 1.1, 1.25],
		blurb = "Splashes groups. Can't hit flyers.",
	},
	"thunder_drum": {
		name = "Thunder Drum", family = "splash", cost = 250, upgrade = [170, 260], air = false, kind = "drum",
		damage = [14.0, 21.0, 30.0], range = [1.8, 2.0, 2.3], rate = [0.55, 0.6, 0.7],
		blurb = "Booms damage all around itself. Can't hit flyers.",
	},
	"firefly_swarm": {
		name = "Firefly Swarm", family = "splash", cost = 275, upgrade = [180, 280], air = true, kind = "swarm",
		damage = [7.0, 10.0, 14.0], range = [3.4, 3.7, 4.0], rate = [1.0, 1.1, 1.25], targets = [3, 4, 5],
		blurb = "Fireflies chase several Snuffers at once, flyers and Shades first.",
	},
	# ---- Slow / support
	"frost_puff": {
		name = "Frost Puff", family = "support", cost = 125, upgrade = [95, 155], air = true, kind = "pulse",
		damage = [1.0, 2.0, 3.0], range = [2.2, 2.5, 2.8], rate = [1.0, 1.0, 1.0],
		slow = [0.30, 0.38, 0.45], slow_time = 1.2,
		blurb = "Chills everything nearby. Hits flyers.",
	},
	"honey_hive": {
		name = "Honey Hive", family = "support", cost = 150, upgrade = [100, 170], air = false, kind = "honey",
		damage = [2.0, 3.0, 5.0], range = [3.0, 3.3, 3.6], rate = [0.7, 0.8, 0.9], splash = [1.0, 1.15, 1.3],
		slow = [0.40, 0.48, 0.55], slow_time = 2.2,
		blurb = "Sticky honey slows groups and stops Menders from healing them.",
	},
	"beacon_post": {
		name = "Beacon Post", family = "support", cost = 200, upgrade = [140, 220], air = false, kind = "beacon",
		range = [2.2, 2.5, 2.8], boost = [0.15, 0.22, 0.30],
		blurb = "Boosts the range of nearby towers and reveals sneaky Shades.",
	},
	# ---- Walls / maze
	"hedge_block": {
		name = "Hedge Block", family = "wall", cost = 20, upgrade = [], air = false, kind = "wall",
		blurb = "Cheap wall to shape the path.",
	},
	"bounce_pad": {
		name = "Bounce Pad", family = "wall", cost = 120, upgrade = [90, 150], air = false, kind = "bounce",
		range = [1.25, 1.35, 1.5], rate = [0.25, 0.3, 0.36], push = [2, 2, 3],
		blurb = "A wall that springs nearby Snuffers back along the path.",
	},
	"mirror_stone": {
		name = "Mirror Stone", family = "wall", cost = 160, upgrade = [110, 180], air = false, kind = "mirror",
		boost = [0.15, 0.22, 0.30], range = [1.5, 1.5, 1.5],
		blurb = "A wall that bends light: touching towers deal more damage.",
	},
}
const FAMILIES := ["shooter", "splash", "support", "wall"]
const FAMILY_NAMES := {"shooter": "Shooters", "splash": "Splash", "support": "Slow & support", "wall": "Walls"}
const TOWER_ORDER := ["pebble_popper", "starseed_sling", "beam_lantern", "jelly_lobber", "thunder_drum", "firefly_swarm",
	"frost_puff", "honey_hive", "beacon_post", "hedge_block", "bounce_pad", "mirror_stone"]
const FAMILY_KEYS := [KEY_1, KEY_2, KEY_3, KEY_4]


static func family_of(type: String) -> String:
	return TOWERS[type].family


static func towers_in(family: String) -> Array:
	return TOWER_ORDER.filter(func(t): return TOWERS[t].family == family)

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
	{id = "prism_path", name = "Prism Path", a = "beam_lantern", b = "mirror_stone",
		text = "The beam bends through the mirror for +30% damage."},
	{id = "honey_bomb", name = "Honey Bomb", a = "honey_hive", b = "thunder_drum",
		text = "Drum booms spread sticky honey."},
	{id = "spring_shot", name = "Spring Shot", a = "bounce_pad", b = "pebble_popper",
		text = "Bounced Snuffers take +20% damage for 3 s."},
	{id = "spotlight", name = "Spotlight", a = "beacon_post", b = "starseed_sling",
		text = "The Sling sees 2 tiles farther."},
	{id = "glowbug_trail", name = "Glowbug Trail", a = "firefly_swarm", b = "hedge_block",
		text = "The Swarm reveals Shades and its fireflies hit harder."},
]
const SLUSHY_FREEZE := 0.8
const ICE_PEBBLE_SLOW := 0.2
const ICE_PEBBLE_TIME := 1.5
const HEDGE_WATCH_RANGE := 0.75
const PRISM_BONUS := 1.3
const SPRING_SHOT_BONUS := 1.2
const SPRING_SHOT_TIME := 3.0
const SPOTLIGHT_RANGE := 2.0
const GLOWBUG_BONUS := 1.25

# ------------------------------------------------------------------ snuffers
const SNUFFER_TYPES := ["scamper", "shellback", "flutter", "big_shellback", "splitblob", "blobling", "shade", "mender",
	"bubbleguard", "jammer", "big_splitblob", "big_bubbleguard", "sugar_snuffer"]
const SNUFFERS := {
	"scamper": {name = "Scamper", hp = 20.0, armor = 0.0, speed = 2.6, reward = 4, damage = 3.0, air = false, size = 0.8},
	"shellback": {name = "Shellback", hp = 60.0, armor = 3.0, speed = 1.4, reward = 9, damage = 6.0, air = false, size = 1.0},
	"flutter": {name = "Flutter", hp = 28.0, armor = 0.0, speed = 2.0, reward = 7, damage = 4.0, air = true, size = 0.9},
	"splitblob": {name = "Splitblob", hp = 40.0, armor = 0.0, speed = 1.7, reward = 6, damage = 5.0, air = false, size = 1.0,
		splits = "blobling", split_count = 3},
	"blobling": {name = "Blobling", hp = 12.0, armor = 0.0, speed = 2.4, reward = 2, damage = 2.0, air = false, size = 0.55},
	"shade": {name = "Shade", hp = 34.0, armor = 0.0, speed = 2.1, reward = 9, damage = 5.0, air = false, size = 0.9,
		sneaky = true},
	"mender": {name = "Mender", hp = 50.0, armor = 1.0, speed = 1.5, reward = 10, damage = 5.0, air = false, size = 1.0,
		heal = 0.05, heal_range = 1.6},
	"bubbleguard": {name = "Bubbleguard", hp = 55.0, armor = 1.0, speed = 1.5, reward = 10, damage = 5.0, air = false, size = 1.0,
		shield_every = 4.0, shield_range = 1.6},
	"jammer": {name = "Jammer", hp = 45.0, armor = 2.0, speed = 1.8, reward = 11, damage = 5.0, air = false, size = 0.95,
		jam_range = 1.2, jam_time = 3.0},
	# ---- bosses
	"big_shellback": {name = "Big Shellback", hp = 900.0, armor = 4.0, speed = 0.8, reward = 150, damage = 40.0, air = false, size = 2.2,
		sheds = [0.66, 0.33], shed_count = 3, shed_type = "shellback", boss = true},
	"big_splitblob": {name = "Big Splitblob", hp = 700.0, armor = 1.0, speed = 0.9, reward = 120, damage = 35.0, air = false, size = 2.1,
		splits = "splitblob", split_count = 4, boss = true},
	"big_bubbleguard": {name = "Big Bubbleguard", hp = 1100.0, armor = 3.0, speed = 0.8, reward = 160, damage = 40.0, air = false, size = 2.2,
		shield_every = 2.5, shield_range = 2.4, boss = true},
	"sugar_snuffer": {name = "Sugar Snuffer", hp = 3200.0, armor = 5.0, speed = 0.7, reward = 400, damage = 100.0, air = false, size = 2.8,
		sheds = [0.66, 0.33], shed_count = 6, shed_type = "scamper", heal = 0.0, boss = true, final = true},
}
## When each Snuffer starts showing up in surprise waves, and how common it is.
const SNUFFER_POOL := [
	{type = "scamper", from = 1, weight = 1.0},
	{type = "shellback", from = 3, weight = 0.45},
	{type = "flutter", from = 4, weight = 0.35},
	{type = "splitblob", from = 6, weight = 0.35},
	{type = "mender", from = 8, weight = 0.18},
	{type = "shade", from = 11, weight = 0.3},
	{type = "bubbleguard", from = 13, weight = 0.18},
	{type = "jammer", from = 16, weight = 0.2},
]
const HP_GROWTH := 0.14  # +14% health per wave


static func wave_hp_scale(wave: int) -> float:
	return 1.0 + HP_GROWTH * float(wave - 1)


## A surprise mix for this wave. Seeded so a wave is the same for everyone.
static func wave_list(wave: int, rng: RandomNumberGenerator) -> Array[String]:
	var out: Array[String] = []
	if wave == BOSS_WAVE:
		out.append("sugar_snuffer")
		for i in 10:
			out.append(["scamper", "shellback", "mender"][i % 3])
		return out
	var pool: Array = SNUFFER_POOL.filter(func(p): return wave >= p.from)
	var total := 0.0
	for p in pool:
		# newer Snuffers ramp in over a few waves
		total += p.weight * clampf(1.0 + (wave - p.from) * 0.25, 0.0, 1.0) if p.type != "scamper" else maxf(0.35, 1.0 - wave * 0.025)
	var count := 6 + wave * 2 if wave <= 15 else 36 + (wave - 15)
	for i in count:
		var roll := rng.randf() * total
		var pick := "scamper"
		for p in pool:
			var w: float = p.weight * clampf(1.0 + (wave - p.from) * 0.25, 0.0, 1.0) if p.type != "scamper" else maxf(0.35, 1.0 - wave * 0.025)
			roll -= w
			if roll <= 0.0:
				pick = p.type
				break
		out.append(pick)
	if MINI_BOSS_WAVES.has(wave):
		out.insert(count / 2, MINI_BOSS_WAVES[wave])
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
