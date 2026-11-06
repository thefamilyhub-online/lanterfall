extends Node3D
## Gumdrop Glade match. The server runs the whole simulation (waves, Snuffers,
## tower combat, coins, heroes, combos, the gate) and sends the results to
## logged-in players. Clients only send requests and draw what they're told.

const D := preload("res://scripts/data.gd")
const BoardView := preload("res://scripts/board_view.gd")
const Hud := preload("res://scripts/hud.gd")

const SNAPSHOT_RATE := 0.1
const STATE_RATE := 0.5
const HERO_SEND_RATE := 0.1
const NEIGHBORS := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

var W: int = D.MAP.w
var H: int = D.MAP.h
var astar := AStarGrid2D.new()
var rocks := {}
var syrup := {}

# ---- shared match state (server decides, clients mirror)
var towers: Dictionary = {}       # Vector2i -> {type, owner, tier, spent, cd, oc}
var combos: Dictionary = {}       # Vector2i -> Array of combo ids active on that tower
var combo_links: Array = []       # [Vector2i, Vector2i, combo name]
var glow := D.PIP_MAX
var phase := "build"              # build, wave, victory, defeat
var wave := 0
var phase_timer := _first_build()
var ready_names: Dictionary = {}  # name -> true
var gate_closed_waves := 0
var gate_cooldown := 0
var coins: Dictionary = {}        # name -> int
var hero_choice: Dictionary = {}  # name -> hero id
var hero_pos: Dictionary = {}     # name -> Vector2 (board x/z)
var hero_cd: Dictionary = {}      # name -> seconds left
var rush: Dictionary = {}         # name -> charges
var gift_allow: Dictionary = {}   # name -> coins still giftable this wave

# ---- server only
var _snuffers: Dictionary = {}
var _next_id := 1
var _spawn_queue: Array = []      # [type, entrance index]
var _spawn_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _shots: Array = []
var _pops := PackedVector2Array()
var _snap_t := 0.0
var _state_t := 0.0
var _kills_this_wave := 0
var _leaks_this_wave := 0

# ---- client only
var visual := true
var view: Node3D
var hud: CanvasLayer
var selected_type := "pebble_popper"
var selected_cell = null
var my_pos := Vector2.ZERO
var _hero_send_t := 0.0


func _ready() -> void:
	name = "World"
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for r in D.MAP.rocks:
		rocks[r] = true
		astar.set_point_solid(r, true)
	for s in D.MAP.syrup:
		syrup[s] = true
	_rng.randomize()
	my_pos = _cell_center2(D.MAP.pip) + Vector2(-4, 0)
	visual = not Net.is_dedicated
	if multiplayer.is_server():
		Net.player_logged_in.connect(_on_player_logged_in)
		Net.players_updated.connect(_on_players_updated)
	if visual:
		view = BoardView.new()
		add_child(view)
		view.setup(self)
		hud = Hud.new()
		add_child(hud)
		hud.setup(self)
		if multiplayer.is_server():
			_join_as(Net.my_name, Net.my_hero)
			hero_pos[Net.my_name] = my_pos
			hud.refresh()
		else:
			request_state.rpc_id(1)
			choose_hero.rpc_id(1, Net.my_hero)


# ================================================================ helpers

func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x - W / 2.0 + 0.5, 0.0, c.y - H / 2.0 + 0.5)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x + W / 2.0), floori(p.z + H / 2.0))


func _cell_center2(c: Vector2i) -> Vector2:
	var v := cell_to_world(c)
	return Vector2(v.x, v.z)


func _cell_of2(p: Vector2) -> Vector2i:
	return world_to_cell(Vector3(p.x, 0, p.y))


func in_bounds(c: Vector2i) -> bool:
	return astar.region.has_point(c)


func path_from(c: Vector2i) -> Array[Vector2i]:
	return astar.get_id_path(c, D.MAP.pip)


func glow_radius() -> float:
	return lerpf(D.GLOW_MIN_RADIUS, D.GLOW_MAX_RADIUS, clampf(glow / D.PIP_MAX, 0.0, 1.0))


func in_glow(c: Vector2i) -> bool:
	return _cell_center2(c).distance_to(_cell_center2(D.MAP.pip)) <= glow_radius()


func is_blocked_cell(c: Vector2i) -> bool:
	return c in D.MAP.entrances or c == D.MAP.pip or rocks.has(c) or syrup.has(c)


func tower_range(c: Vector2i) -> float:
	var t: Dictionary = towers[c]
	var d: Dictionary = D.TOWERS[t.type]
	if not d.has("range"):
		return 0.0
	var r: float = d.range[t.tier - 1]
	if d.kind in ["wall", "beacon", "mirror", "bounce"]:
		return r
	var tc: Array = combos.get(c, [])
	if "hedge_watch" in tc:
		r += D.HEDGE_WATCH_RANGE
	if "spotlight" in tc:
		r += D.SPOTLIGHT_RANGE
	r *= 1.0 + beacon_boost(c)
	return r


## Range bonus from the strongest Beacon Post that reaches this tower.
func beacon_boost(c: Vector2i) -> float:
	var best := 0.0
	var cw := _cell_center2(c)
	for b in towers:
		var bt: Dictionary = towers[b]
		if b == c or bt.type != "beacon_post":
			continue
		var bd: Dictionary = D.TOWERS.beacon_post
		if _cell_center2(b).distance_to(cw) <= bd.range[bt.tier - 1] + 0.01:
			best = maxf(best, bd.boost[bt.tier - 1])
	return best


## Damage bonus from touching Mirror Stones (and the Prism Path combo).
func damage_mult(c: Vector2i) -> float:
	var m := 1.0
	var best := 0.0
	for n in NEIGHBORS:
		var nc: Vector2i = c + n
		if towers.has(nc) and towers[nc].type == "mirror_stone":
			best = maxf(best, D.TOWERS.mirror_stone.boost[towers[nc].tier - 1])
	m *= 1.0 + best
	if "prism_path" in combos.get(c, []):
		m *= D.PRISM_BONUS
	return m


func build_cost(player_name: String, type: String) -> int:
	var c := float(D.TOWERS[type].cost)
	if hero_choice.get(player_name, "") == "bramble":
		c *= D.BRAMBLE_DISCOUNT
	if int(rush.get(player_name, 0)) > 0:
		c *= D.RUSH_DISCOUNT
	return int(round(c))


func upgrade_cost(player_name: String, c: Vector2i) -> int:
	var t: Dictionary = towers[c]
	var ups: Array = D.TOWERS[t.type].upgrade
	if t.tier > ups.size():
		return -1
	var cost := float(ups[t.tier - 1])
	if hero_choice.get(player_name, "") == "bramble":
		cost *= D.BRAMBLE_DISCOUNT
	return int(round(cost))


func sell_value(c: Vector2i) -> int:
	return int(floor(towers[c].spent * D.SELL_REFUND))


func in_reach(player_name: String, c: Vector2i) -> bool:
	var p: Vector2 = hero_pos.get(player_name, Vector2(INF, INF))
	return p.distance_to(_cell_center2(c)) <= D.BUILD_REACH + 0.5


## Rules every placement follows. The path can be shaped, never sealed:
## both entrances (even a closed gate reopens) and every Snuffer keep a way to Pip.
func can_place(c: Vector2i, player_name: String, type: String, check_snuffers := true) -> Dictionary:
	if not in_bounds(c):
		return {ok = false, why = "That's off the board."}
	if is_blocked_cell(c):
		return {ok = false, why = "You can't build there."}
	if towers.has(c):
		return {ok = false, why = "There's already a tower there."}
	if not in_reach(player_name, c):
		return {ok = false, why = "Too far away. Walk your hero closer (WASD)."}
	if int(coins.get(player_name, 0)) < build_cost(player_name, type):
		return {ok = false, why = "Not enough coins."}
	if check_snuffers:
		for s in _snuffers.values():
			if not s.air and _cell_of2(s.pos) == c:
				return {ok = false, why = "A Snuffer is standing there."}
	astar.set_point_solid(c, true)
	var ok := true
	for e in D.MAP.entrances:
		if path_from(e).is_empty():
			ok = false
	if ok and check_snuffers:
		for s in _snuffers.values():
			if not s.air and path_from(_cell_of2(s.pos)).is_empty():
				ok = false
				break
	astar.set_point_solid(c, false)
	if not ok:
		return {ok = false, why = "That would block the path. Snuffers must always have a way through."}
	return {ok = true, why = ""}


func recompute_combos() -> void:
	combos.clear()
	combo_links.clear()
	for c in towers:
		var a: Dictionary = towers[c]
		for n in NEIGHBORS:
			var nc: Vector2i = c + n
			if not towers.has(nc) or towers[nc].owner == a.owner:
				continue
			var b: Dictionary = towers[nc]
			for combo in D.COMBOS:
				if (a.type == combo.a and b.type == combo.b) or (a.type == combo.b and b.type == combo.a):
					if not combos.has(c):
						combos[c] = []
					if not combo.id in combos[c]:
						combos[c].append(combo.id)
					if c < nc:
						combo_links.append([c, nc, combo.name])


func _game_state() -> Dictionary:
	var oc := []
	var jam := []
	for c in towers:
		if towers[c].oc > 0.0:
			oc.append(c)
		if towers[c].get("jam", 0.0) > 0.0:
			jam.append(c)
	return {
		phase = phase, wave = wave, timer = phase_timer, glow = glow,
		ready = ready_names.keys(), gate_closed = gate_closed_waves, gate_cd = gate_cooldown,
		coins = coins, heroes = hero_choice, hero_cd = hero_cd, rush = rush, gift = gift_allow,
		overcharged = oc, jammed = jam,
	}


# ================================================================ server: players

## First build phase length; tests can pass --first-build=SECONDS.
static func _first_build() -> float:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--first-build="):
			return float(a.substr(14))
	return D.FIRST_BUILD_TIME


## Starting coins; tests can pass --coins=N to the server.
func _start_coins() -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--coins="):
			return int(a.substr(8))
	return D.START_COINS


func _join_as(player_name: String, hero: String) -> void:
	if player_name == "":
		return
	if not coins.has(player_name):
		coins[player_name] = _start_coins()
		rush[player_name] = 0
		hero_cd[player_name] = 0.0
		gift_allow[player_name] = D.START_COINS >> 1
	hero_choice[player_name] = hero if D.HEROES.has(hero) else "bramble"
	if not hero_pos.has(player_name):
		hero_pos[player_name] = _cell_center2(D.MAP.pip) + Vector2(-4, randf_range(-2, 2))


func _on_player_logged_in(peer_id: int) -> void:
	var n: String = Net.players[peer_id]
	_join_as(n, hero_choice.get(n, "bramble"))


func _on_players_updated() -> void:
	if not multiplayer.is_server():
		return
	if Net.players.is_empty() and (wave > 0 or not towers.is_empty()):
		_reset_match("Everyone left. Starting fresh.")
	var online := {}
	for n in Net.players.values():
		online[n] = true
	for n in ready_names.keys():
		if not online.has(n):
			ready_names.erase(n)


func _name_of_sender() -> String:
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	return Net.players.get(id, "")


func _peer_of(player_name: String) -> int:
	for id in Net.players:
		if Net.players[id] == player_name:
			return id
	return 0


## Send to logged-in players only. The host, if playing, gets a direct call.
func _broadcast(method: StringName, args: Array) -> void:
	for id in Net.players.keys():
		if Net.is_local(id):
			callv(method, args)
		else:
			callv("rpc_id", [id, method] + args)


func _tell(player_name: String, text: String) -> void:
	var id := _peer_of(player_name)
	if id == 0:
		return
	if Net.is_local(id):
		_show_message(text)
	else:
		notice.rpc_id(id, text)


func _announce(text: String) -> void:
	if not visual:
		print("[server] %s" % text)
	_broadcast(&"announce", [text])


# ================================================================ server: loop

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if Net.players.is_empty():
		return
	for n in hero_cd:
		hero_cd[n] = maxf(0.0, hero_cd[n] - delta)
	for c in towers:
		if towers[c].oc > 0.0:
			towers[c].oc = maxf(0.0, towers[c].oc - delta)
	match phase:
		"build":
			phase_timer -= delta
			if phase_timer <= 0.0:
				_start_wave(false)
			elif _all_ready():
				_start_wave(true)
		"wave":
			_spawn(delta)
			_move_snuffers(delta)
			if phase == "wave":
				_towers_fire(delta)
				if _spawn_queue.is_empty() and _snuffers.is_empty():
					_end_wave()
		"victory", "defeat":
			phase_timer -= delta
			if phase_timer <= 0.0:
				_reset_match("")
	_snap_t -= delta
	if _snap_t <= 0.0:
		_snap_t = SNAPSHOT_RATE
		_send_snapshot()
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = STATE_RATE
		_broadcast(&"game_state", [_game_state()])


func _all_ready() -> bool:
	if Net.players.is_empty():
		return false
	for n in Net.players.values():
		if not ready_names.has(n):
			return false
	return true


func _start_wave(early: bool) -> void:
	var bonus := 0
	if early:
		bonus = int(phase_timer) * D.EARLY_CALL_PER_SECOND
		for n in coins:
			coins[n] += bonus
	if wave == 0:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--start-wave="):
				wave = int(a.substr(13)) - 1   # test helper
	wave += 1
	phase = "wave"
	ready_names.clear()
	_kills_this_wave = 0
	_leaks_this_wave = 0
	for n in coins:
		gift_allow[n] = int(coins[n]) >> 1
	var wave_rng := RandomNumberGenerator.new()
	wave_rng.seed = _rng.randi()
	var list := D.wave_list(wave, wave_rng)
	_spawn_queue.clear()
	var entrances: Array = [0, 1]
	if gate_closed_waves > 0:
		entrances = [1 - D.MAP.gate_entrance]
	for i in list.size():
		_spawn_queue.append([list[i], entrances[i % entrances.size()]])
	_spawn_timer = 0.5
	var label := "The Sugar Snuffer is coming!" if wave == D.BOSS_WAVE else "Wave %d of %d!" % [wave, D.BOSS_WAVE]
	if bonus > 0:
		label += "  Early call: +%d coins each" % bonus
	_announce(label)
	print("[server] wave %d started (%d Snuffers, gate %s)" % [wave, list.size(), "closed" if gate_closed_waves > 0 else "open"])


func _end_wave() -> void:
	var bonus := D.wave_clear_bonus(wave)
	for n in coins:
		coins[n] += bonus
	if gate_closed_waves > 0:
		gate_closed_waves -= 1
		if gate_closed_waves == 0:
			gate_cooldown = D.GATE_COOLDOWN_WAVES
	elif gate_cooldown > 0:
		gate_cooldown -= 1
	print("[server] wave %d cleared: %d popped, %d leaked, Pip glow %d" % [wave, _kills_this_wave, _leaks_this_wave, int(glow)])
	if wave >= D.BOSS_WAVE:
		phase = "victory"
		phase_timer = 12.0
		_announce("Victory! Pip is safe and glowing bright!")
		print("[server] VICTORY")
		return
	phase = "build"
	phase_timer = D.BUILD_TIME
	_announce("Wave cleared! +%d coins each" % bonus)


func _reset_match(text: String) -> void:
	for c in towers.keys():
		astar.set_point_solid(c, false)
	towers.clear()
	recompute_combos()
	_snuffers.clear()
	_spawn_queue.clear()
	glow = D.PIP_MAX
	wave = 0
	phase = "build"
	phase_timer = _first_build()
	ready_names.clear()
	gate_closed_waves = 0
	gate_cooldown = 0
	for n in coins.keys():
		coins[n] = _start_coins()
		rush[n] = 0
		hero_cd[n] = 0.0
		gift_allow[n] = D.START_COINS >> 1
	_broadcast(&"full_state", [_full_state()])
	_announce(text if text != "" else "A new match begins. Build your defenses!")


func _spawn(delta: float) -> void:
	if _spawn_queue.is_empty():
		return
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	_spawn_timer = D.SPAWN_GAP
	var item: Array = _spawn_queue.pop_front()
	var e: Vector2i = D.MAP.entrances[item[1]]
	_add_snuffer(item[0], _cell_center2(e), e)
	var sd: Dictionary = D.SNUFFERS[item[0]]
	if sd.get("boss", false) and not sd.get("final", false):
		_announce("A %s is coming!" % sd.name)


func _add_snuffer(type: String, pos: Vector2, from_cell: Vector2i) -> void:
	var d: Dictionary = D.SNUFFERS[type]
	var hp: float = d.hp * D.wave_hp_scale(wave)
	var path: Array[Vector2i] = []
	if not d.air:
		path = path_from(from_cell)
	_snuffers[_next_id] = {
		id = _next_id, type = type, hp = hp, max_hp = hp, armor = d.armor, speed = d.speed, air = d.air,
		pos = pos, path = path, idx = 0,
		slow = 0.0, slow_t = 0.0, freeze_t = 0.0, dist = 0.0, last_owner = "",
		sheds_done = 0, dead = false,
		sneaky = d.get("sneaky", false), revealed = false, reveal_t = 0.0,
		shield = false, shield_cd = randf_range(0.5, 1.5), honey_t = 0.0, spring_t = 0.0,
	}
	_next_id += 1


func _move_snuffers(delta: float) -> void:
	var pip := _cell_center2(D.MAP.pip)
	var leaked: Array = []
	_snuffer_powers(delta)
	for id in _snuffers:
		var s: Dictionary = _snuffers[id]
		s.slow_t = maxf(0.0, s.slow_t - delta)
		s.freeze_t = maxf(0.0, s.freeze_t - delta)
		s.honey_t = maxf(0.0, s.honey_t - delta)
		s.spring_t = maxf(0.0, s.spring_t - delta)
		s.reveal_t = maxf(0.0, s.reveal_t - delta)
		if s.slow_t <= 0.0:
			s.slow = 0.0
		var spd: float = s.speed * (1.0 - s.slow)
		if s.freeze_t > 0.0:
			spd = 0.0
		if not s.air and syrup.has(_cell_of2(s.pos)):
			spd *= 1.0 - D.SYRUP_SLOW
		var step := spd * delta
		if s.air:
			var d: float = s.pos.distance_to(pip)
			if d <= step:
				s.pos = pip
				leaked.append(id)
			else:
				s.pos += (pip - s.pos) / d * step
			s.dist += step
			continue
		while step > 0.0 and s.idx < s.path.size():
			var target := _cell_center2(s.path[s.idx])
			var dd: float = s.pos.distance_to(target)
			if dd <= step:
				s.pos = target
				s.idx += 1
				step -= dd
				s.dist += dd
			else:
				s.pos += (target - s.pos) / dd * step
				s.dist += step
				step = 0.0
		if s.idx >= s.path.size():
			leaked.append(id)
	for id in leaked:
		var s: Dictionary = _snuffers[id]
		glow -= D.SNUFFERS[s.type].damage
		_leaks_this_wave += 1
		_snuffers.erase(id)
	if glow <= 0.0:
		glow = 0.0
		phase = "defeat"
		phase_timer = 10.0
		_snuffers.clear()
		_spawn_queue.clear()
		_announce("Pip's light went out on wave %d. Try a new plan!" % wave)
		print("[server] DEFEAT on wave %d" % wave)


## Menders heal, Bubbleguards hand out shields, Jammers jam towers.
func _snuffer_powers(delta: float) -> void:
	var list: Array = _snuffers.values()
	for s in list:
		var d: Dictionary = D.SNUFFERS[s.type]
		if d.get("heal", 0.0) > 0.0:
			for o in list:
				if o != s and o.honey_t <= 0.0 and o.hp < o.max_hp and o.pos.distance_to(s.pos) <= d.heal_range:
					o.hp = minf(o.max_hp, o.hp + o.max_hp * d.heal * delta)
		if d.has("shield_every"):
			s.shield_cd -= delta
			if s.shield_cd <= 0.0:
				s.shield_cd = d.shield_every
				var gave := false
				for o in list:
					if o != s and not o.shield and o.pos.distance_to(s.pos) <= d.shield_range:
						o.shield = true
						gave = true
				if gave:
					_shots.append([Vector2i(-1, -1), s.pos, 11])
		if d.has("jam_range"):
			for c in towers:
				if towers[c].type == "hedge_block":
					continue
				if _cell_center2(c).distance_to(s.pos) <= d.jam_range:
					if towers[c].get("jam", 0.0) <= 0.0:
						_shots.append([c, s.pos, 12])
					towers[c].jam = d.jam_time
	# who can be seen: Pip's glow and Beacon Posts reveal Shades
	var gr := glow_radius()
	var pip := _cell_center2(D.MAP.pip)
	for s in list:
		if not s.sneaky:
			continue
		var seen: bool = s.reveal_t > 0.0 or s.pos.distance_to(pip) <= gr
		if not seen:
			for c in towers:
				if towers[c].type == "beacon_post" and _cell_center2(c).distance_to(s.pos) <= D.TOWERS.beacon_post.range[towers[c].tier - 1]:
					seen = true
					break
		s.revealed = seen


func _rate_mult(c: Vector2i) -> float:
	var m := 1.0
	if in_glow(c):
		m *= D.GLOW_RATE_BONUS
	var cw := _cell_center2(c)
	for n in hero_choice:
		if hero_choice[n] == "glint" and hero_pos.has(n) and _peer_of(n) != 0 and hero_pos[n].distance_to(cw) <= D.GLINT_AURA_RANGE:
			m *= D.GLINT_AURA_BONUS
			break
	if towers[c].oc > 0.0:
		m *= 2.0
	return m


func _towers_fire(delta: float) -> void:
	for c in towers:
		var t: Dictionary = towers[c]
		var d: Dictionary = D.TOWERS[t.type]
		if d.kind in ["wall", "beacon", "mirror"]:
			continue
		if t.get("jam", 0.0) > 0.0:
			t.jam = maxf(0.0, t.jam - delta)
			continue
		var i: int = t.tier - 1
		t.cd -= delta * d.rate[i] * _rate_mult(c)
		if t.cd > 0.0:
			continue
		var origin := _cell_center2(c)
		var rng := tower_range(c)
		var sees_sneaky: bool = d.kind == "swarm"
		var target = null
		var best := -1.0
		for id in _snuffers:
			var s: Dictionary = _snuffers[id]
			if s.dead or (s.air and not d.air) or (s.sneaky and not s.revealed and not sees_sneaky):
				continue
			if s.pos.distance_to(origin) <= rng and s.dist > best:
				best = s.dist
				target = s
		if target == null:
			t.cd = 0.0
			if d.kind == "beam":
				t.heat = 0.0
			continue
		t.cd += 1.0
		var tc: Array = combos.get(c, [])
		var dmg: float = d.damage[i] * damage_mult(c) if d.has("damage") else 0.0
		match d.kind:
			"single":
				_shots.append([c, target.pos, 0])
				_hit(target, dmg, t.owner)
				if "ice_pebbles" in tc:
					_chill(target, D.ICE_PEBBLE_SLOW, D.ICE_PEBBLE_TIME)
			"splash":
				var center: Vector2 = target.pos
				_shots.append([c, center, 1])
				for s in _snuffers.values():
					if not s.dead and not s.air and s.pos.distance_to(center) <= d.splash[i]:
						_hit(s, dmg, t.owner)
						if "slushy" in tc:
							s.freeze_t = maxf(s.freeze_t, D.SLUSHY_FREEZE)
			"pulse":
				_shots.append([c, origin, 2])
				for s in _snuffers.values():
					if not s.dead and s.pos.distance_to(origin) <= rng:
						_hit(s, dmg, t.owner)
						_chill(s, d.slow[i], d.slow_time)
			"pierce":
				var dir: Vector2 = (target.pos - origin).normalized()
				var end_pt: Vector2 = origin + dir * rng
				var hits: Array = []
				for s in _snuffers.values():
					if s.dead or (s.sneaky and not s.revealed):
						continue
					var along: float = (s.pos - origin).dot(dir)
					if along < 0.0 or along > rng:
						continue
					if (origin + dir * along).distance_to(s.pos) <= 0.42:
						hits.append([along, s])
				hits.sort_custom(func(a, b): return a[0] < b[0])
				for k in mini(hits.size(), int(d.pierce[i])):
					_hit(hits[k][1], dmg, t.owner)
				_shots.append([c, end_pt, 3])
			"beam":
				if t.get("beam_id", -1) == target.id:
					t.heat = minf(float(t.get("heat", 0.0)) + d.ramp[i], 2.0)
				else:
					t.beam_id = target.id
					t.heat = 0.0
				_hit(target, dmg * (1.0 + t.heat), t.owner, 0.5)
				_shots.append([c, target.pos, 4])
			"drum":
				_shots.append([c, origin, 5])
				for s in _snuffers.values():
					if not s.dead and not s.air and s.pos.distance_to(origin) <= rng and (s.revealed or not s.sneaky):
						_hit(s, dmg, t.owner)
						if "honey_bomb" in tc:
							_chill(s, 0.3, 2.0)
							s.honey_t = maxf(s.honey_t, 2.0)
			"swarm":
				var pool: Array = []
				for s in _snuffers.values():
					if not s.dead and s.pos.distance_to(origin) <= rng:
						var prio: float = s.dist + (100.0 if s.air or s.sneaky else 0.0)
						pool.append([prio, s])
				pool.sort_custom(func(a, b): return a[0] > b[0])
				var mult := D.GLOWBUG_BONUS if "glowbug_trail" in tc else 1.0
				for k in mini(pool.size(), int(d.targets[i])):
					var s: Dictionary = pool[k][1]
					_hit(s, dmg * mult, t.owner)
					if "glowbug_trail" in tc:
						s.reveal_t = 3.0
					_shots.append([c, s.pos, 6])
			"honey":
				var center2: Vector2 = target.pos
				_shots.append([c, center2, 7])
				for s in _snuffers.values():
					if not s.dead and not s.air and s.pos.distance_to(center2) <= d.splash[i]:
						_hit(s, dmg, t.owner)
						_chill(s, d.slow[i], d.slow_time)
						s.honey_t = maxf(s.honey_t, d.slow_time)
			"bounce":
				var bounced := false
				for s in _snuffers.values():
					if s.dead or s.air or s.pos.distance_to(origin) > rng or D.SNUFFERS[s.type].get("boss", false):
						continue
					var back: int = mini(int(d.push[i]), s.idx)
					if back <= 0:
						continue
					s.idx -= back
					s.pos = _cell_center2(s.path[maxi(s.idx - 1, 0)]) if s.idx > 0 else s.pos
					s.dist = maxf(0.0, s.dist - back)
					bounced = true
					if "spring_shot" in tc:
						s.spring_t = D.SPRING_SHOT_TIME
				if bounced:
					_shots.append([c, origin, 8])
				else:
					t.cd = 0.0
	var dead: Array = []
	for id in _snuffers:
		if _snuffers[id].dead:
			dead.append(id)
	for id in dead:
		_snuffers.erase(id)


func _chill(s: Dictionary, amount: float, time: float) -> void:
	if amount >= s.slow:
		s.slow = amount
	s.slow_t = maxf(s.slow_t, time)


func _hit(s: Dictionary, dmg: float, owner_name: String, armor_mult := 1.0) -> void:
	if s.dead:
		return
	if s.shield:
		s.shield = false
		_shots.append([Vector2i(-1, -1), s.pos, 9])
		return
	if s.spring_t > 0.0:
		dmg *= D.SPRING_SHOT_BONUS
	s.hp -= maxf(1.0, dmg - s.armor * armor_mult)
	s.last_owner = owner_name
	var d: Dictionary = D.SNUFFERS[s.type]
	if d.has("sheds") and s.sheds_done < d.sheds.size() and s.hp / s.max_hp <= d.sheds[s.sheds_done]:
		s.sheds_done += 1
		for k in d.shed_count:
			var offset := Vector2(randf_range(-0.35, 0.35), randf_range(-0.35, 0.35))
			_add_snuffer(d.shed_type, s.pos + offset, _cell_of2(s.pos))
		if d.get("final", false):
			s.speed *= 1.15
			s.shield = true
			_announce("The Sugar Snuffer calls for help!" if s.sheds_done == 1 else "The Sugar Snuffer is getting angry!")
		else:
			_announce("The %s's shell cracked!" % d.name)
	if s.hp <= 0.0:
		s.dead = true
		_kills_this_wave += 1
		_pops.append(s.pos)
		if coins.has(owner_name):
			coins[owner_name] += d.reward
		if d.has("splits"):
			for k in d.split_count:
				var offset := Vector2(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3))
				_add_snuffer(d.splits, s.pos + offset, _cell_of2(s.pos))
			_shots.append([Vector2i(-1, -1), s.pos, 10])


func _send_snapshot() -> void:
	var ids := PackedInt32Array()
	var pos := PackedVector2Array()
	var types := PackedByteArray()
	var hp := PackedByteArray()
	var status := PackedByteArray()
	for id in _snuffers:
		var s: Dictionary = _snuffers[id]
		ids.append(id)
		pos.append(s.pos)
		types.append(D.SNUFFER_TYPES.find(s.type))
		hp.append(clampi(int(255.0 * s.hp / s.max_hp), 0, 255))
		status.append((1 if s.slow_t > 0.0 else 0) | (2 if s.freeze_t > 0.0 else 0) | (4 if s.shield else 0)
			| (8 if s.sneaky and not s.revealed else 0) | (16 if s.honey_t > 0.0 else 0))
	var hn := PackedStringArray()
	var hp2 := PackedVector2Array()
	var hk := PackedByteArray()
	for n in hero_pos:
		if _peer_of(n) == 0:
			continue
		hn.append(n)
		hp2.append(hero_pos[n])
		hk.append(D.HERO_ORDER.find(hero_choice.get(n, "bramble")))
	_broadcast(&"snapshot", [ids, pos, types, hp, status, glow, _shots, _pops, hn, hp2, hk])
	_shots = []
	_pops = PackedVector2Array()


func _full_state() -> Dictionary:
	var list := []
	for c in towers:
		list.append([c, towers[c].type, towers[c].owner, towers[c].tier, towers[c].spent])
	return {towers = list, state = _game_state()}


# ================================================================ requests (client -> server)

@rpc("any_peer", "reliable")
func request_state() -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not Net.players.has(id):
		return
	full_state.rpc_id(id, _full_state())


@rpc("any_peer", "reliable")
func choose_hero(hero: String) -> void:
	if not multiplayer.is_server():
		return
	var n := _name_of_sender()
	if n != "":
		_join_as(n, hero)


@rpc("any_peer", "unreliable_ordered")
func hero_moved(p: Vector2) -> void:
	if not multiplayer.is_server():
		return
	var n := _name_of_sender()
	if n == "":
		return
	hero_pos[n] = Vector2(clampf(p.x, -W / 2.0, W / 2.0), clampf(p.y, -H / 2.0, H / 2.0))


@rpc("any_peer", "reliable")
func request_place(c: Vector2i, type: String) -> void:
	if not multiplayer.is_server():
		return
	var n := _name_of_sender()
	if n == "" or not D.TOWERS.has(type) or phase in ["victory", "defeat"]:
		return
	var check := can_place(c, n, type)
	if not check.ok:
		_tell(n, check.why)
		return
	var cost := build_cost(n, type)
	coins[n] -= cost
	if int(rush.get(n, 0)) > 0:
		rush[n] -= 1
	towers[c] = {type = type, owner = n, tier = 1, spent = cost, cd = 0.0, oc = 0.0}
	astar.set_point_solid(c, true)
	_repath_all()
	recompute_combos()
	Accounts.add_stat(n, "towers_placed")
	_broadcast(&"tower_placed", [c, type, n, 1, cost])
	_broadcast(&"game_state", [_game_state()])


@rpc("any_peer", "reliable")
func request_upgrade(c: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var n := _name_of_sender()
	if n == "" or not towers.has(c):
		return
	if towers[c].owner != n:
		_tell(n, "You can only upgrade your own towers.")
		return
	var cost := upgrade_cost(n, c)
	if cost < 0:
		_tell(n, "That tower is fully upgraded.")
		return
	if not in_reach(n, c):
		_tell(n, "Too far away. Walk your hero closer (WASD).")
		return
	if coins[n] < cost:
		_tell(n, "Not enough coins.")
		return
	coins[n] -= cost
	towers[c].tier += 1
	towers[c].spent += cost
	_broadcast(&"tower_changed", [c, towers[c].tier, towers[c].spent])
	_broadcast(&"game_state", [_game_state()])


@rpc("any_peer", "reliable")
func request_sell(c: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var n := _name_of_sender()
	if n == "" or not towers.has(c):
		return
	if towers[c].owner != n:
		_tell(n, "You can only sell your own towers.")
		return
	coins[n] += sell_value(c)
	towers.erase(c)
	astar.set_point_solid(c, false)
	_repath_all()
	recompute_combos()
	_broadcast(&"tower_removed", [c])
	_broadcast(&"game_state", [_game_state()])


@rpc("any_peer", "reliable")
func request_ready_up(on: bool) -> void:
	if not multiplayer.is_server():
		return
	var n := _name_of_sender()
	if n == "" or phase != "build":
		return
	if on:
		ready_names[n] = true
	else:
		ready_names.erase(n)
	_broadcast(&"game_state", [_game_state()])


@rpc("any_peer", "reliable")
func request_ability() -> void:
	if not multiplayer.is_server():
		return
	var n := _name_of_sender()
	if n == "" or hero_cd.get(n, 0.0) > 0.0:
		return
	var hero: String = hero_choice.get(n, "bramble")
	if hero == "bramble":
		rush[n] = D.RUSH_CHARGES
		_tell(n, "Rush Build! Your next 3 towers are 25% cheaper.")
	else:
		var best = null
		var best_d := INF
		for c in towers:
			if D.TOWERS[towers[c].type].kind == "wall" or not in_reach(n, c):
				continue
			var dist: float = hero_pos[n].distance_to(_cell_center2(c))
			if dist < best_d:
				best_d = dist
				best = c
		if best == null:
			_tell(n, "No tower in reach to Overcharge.")
			return
		towers[best].oc = D.OVERCHARGE_TIME
		_tell(n, "Overcharge! That tower fires twice as fast.")
	hero_cd[n] = D.HEROES[hero].cooldown
	_broadcast(&"game_state", [_game_state()])


@rpc("any_peer", "reliable")
func request_gate() -> void:
	if not multiplayer.is_server():
		return
	var n := _name_of_sender()
	if n == "":
		return
	if phase != "build":
		_tell(n, "The gate can only be closed between waves.")
		return
	if gate_closed_waves > 0 or gate_cooldown > 0:
		_tell(n, "The gate isn't ready yet.")
		return
	if coins[n] < D.GATE_COST:
		_tell(n, "Closing the gate costs %d coins." % D.GATE_COST)
		return
	coins[n] -= D.GATE_COST
	gate_closed_waves = D.GATE_WAVES
	_announce("%s closed the licorice gate for %d waves!" % [n, D.GATE_WAVES])
	_broadcast(&"game_state", [_game_state()])


@rpc("any_peer", "reliable")
func request_gift(to_name: String) -> void:
	if not multiplayer.is_server():
		return
	var n := _name_of_sender()
	if n == "" or n == to_name or not coins.has(to_name):
		return
	var amount := D.GIFT_STEP
	if coins[n] < amount:
		_tell(n, "Not enough coins to gift.")
		return
	if gift_allow.get(n, 0) < amount:
		_tell(n, "You've gifted all you can this wave (half your coins).")
		return
	coins[n] -= amount
	coins[to_name] += amount
	gift_allow[n] -= amount
	_tell(n, "You sent %d coins to %s." % [amount, to_name])
	_tell(to_name, "%s sent you %d coins!" % [n, amount])
	_broadcast(&"game_state", [_game_state()])


func _repath_all() -> void:
	for s in _snuffers.values():
		if s.air:
			continue
		s.path = path_from(_cell_of2(s.pos))
		s.idx = 0


# ================================================================ server -> clients

@rpc("authority", "reliable")
func full_state(st: Dictionary) -> void:
	if not multiplayer.is_server():
		for c in towers.keys():
			astar.set_point_solid(c, false)
		towers.clear()
		for entry in st.towers:
			towers[entry[0]] = {type = entry[1], owner = entry[2], tier = entry[3], spent = entry[4], cd = 0.0, oc = 0.0}
			astar.set_point_solid(entry[0], true)
		recompute_combos()
		_apply_state(st.state)
	if visual:
		selected_cell = null
		view.rebuild_towers()
		view.clear_snuffers()
		hud.refresh()


@rpc("authority", "reliable")
func tower_placed(c: Vector2i, type: String, owner_name: String, tier: int, spent: int) -> void:
	if not multiplayer.is_server():
		towers[c] = {type = type, owner = owner_name, tier = tier, spent = spent, cd = 0.0, oc = 0.0}
		astar.set_point_solid(c, true)
		recompute_combos()
	if visual:
		view.add_tower(c)
		Sfx.play("build")
		view.refresh_links()
		view.refresh_paths()
	print("[%s] sees %s's %s at %s" % [Net.my_name, owner_name, type, c])


@rpc("authority", "reliable")
func tower_changed(c: Vector2i, tier: int, spent: int) -> void:
	if not multiplayer.is_server() and towers.has(c):
		towers[c].tier = tier
		towers[c].spent = spent
	if visual:
		view.update_tower(c)
		hud.refresh()
		Sfx.play("upgrade")
	print("[%s] sees tower at %s upgraded to tier %d" % [Net.my_name, c, tier])


@rpc("authority", "reliable")
func tower_removed(c: Vector2i) -> void:
	if visual:
		Sfx.play("sell")
	if not multiplayer.is_server():
		towers.erase(c)
		astar.set_point_solid(c, false)
		recompute_combos()
	if selected_cell == c:
		selected_cell = null
	if visual:
		view.remove_tower(c)
		view.refresh_links()
		view.refresh_paths()
		hud.refresh()


@rpc("authority", "reliable")
func game_state(st: Dictionary) -> void:
	_apply_state(st)


func _apply_state(st: Dictionary) -> void:
	if not multiplayer.is_server():
		phase = st.phase
		wave = st.wave
		phase_timer = st.timer
		glow = st.glow
		ready_names.clear()
		for n in st.ready:
			ready_names[n] = true
		gate_closed_waves = st.gate_closed
		gate_cooldown = st.gate_cd
		coins = st.coins
		hero_choice = st.heroes
		hero_cd = st.hero_cd
		rush = st.rush
		gift_allow = st.gift
		for c in towers:
			towers[c].oc = 1.0 if c in st.overcharged else 0.0
			towers[c].jam = 1.0 if c in st.get("jammed", []) else 0.0
	if visual:
		hud.refresh()
		view.refresh_gate()
		view.refresh_overcharge()


@rpc("authority", "unreliable_ordered")
func snapshot(ids: PackedInt32Array, pos: PackedVector2Array, types: PackedByteArray, hp: PackedByteArray,
		status: PackedByteArray, g: float, shots: Array, pops: PackedVector2Array,
		hero_names: PackedStringArray, hero_positions: PackedVector2Array, hero_kinds: PackedByteArray) -> void:
	glow = g
	if not visual:
		return
	view.apply_snapshot(ids, pos, types, hp, status, shots, pops)
	view.apply_heroes(hero_names, hero_positions, hero_kinds)


@rpc("authority", "reliable")
func announce(text: String) -> void:
	_show_message(text)


@rpc("authority", "reliable")
func notice(text: String) -> void:
	_show_message(text)
	if visual:
		if "sent" in text:
			Sfx.play("gift")
		elif not ("!" in text):
			Sfx.play("denied")


func _show_message(text: String) -> void:
	if OS.get_cmdline_user_args().size() > 0:
		print("[%s] message: %s" % [Net.my_name, text])
	if hud:
		hud.show_message(text)


# ================================================================ client actions

func _send(method: StringName, args: Array = []) -> void:
	if multiplayer.is_server():
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)


func my_coins() -> int:
	return int(coins.get(Net.my_name, 0))


func place_tower(c: Vector2i, type: String) -> void:
	hero_pos[Net.my_name] = my_pos
	var check := can_place(c, Net.my_name, type, false)
	if not check.ok:
		_show_message(check.why)
		return
	_send(&"request_place", [c, type])


func upgrade_selected() -> void:
	if selected_cell != null:
		_send(&"request_upgrade", [selected_cell])


func sell_selected() -> void:
	if selected_cell != null:
		_send(&"request_sell", [selected_cell])


func toggle_ready() -> void:
	_send(&"request_ready_up", [not ready_names.has(Net.my_name)])


func use_ability() -> void:
	_send(&"request_ability")


func close_gate() -> void:
	_send(&"request_gate")


func gift_to(player_name: String) -> void:
	_send(&"request_gift", [player_name])


func select_type(t: String) -> void:
	selected_type = t
	selected_cell = null
	if hud:
		hud.refresh()


## Test helper: move this player's hero next to a cell instantly.
func debug_move_hero(c: Vector2i) -> void:
	my_pos = _cell_center2(c) + Vector2(0.0, 0.8)
	hero_pos[Net.my_name] = my_pos
	if not multiplayer.is_server():
		hero_moved.rpc_id(1, my_pos)


# ================================================================ client input & per-frame

func _process(delta: float) -> void:
	if not visual:
		return
	var move := Vector2.ZERO
	if not hud.typing():
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			move.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			move.y += 1
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			move.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			move.x += 1
	if move != Vector2.ZERO:
		my_pos += move.normalized() * D.HERO_SPEED * delta
		my_pos = Vector2(clampf(my_pos.x, -W / 2.0, W / 2.0), clampf(my_pos.y, -H / 2.0, H / 2.0))
	hero_pos[Net.my_name] = my_pos
	_hero_send_t -= delta
	if _hero_send_t <= 0.0:
		_hero_send_t = HERO_SEND_RATE
		if not multiplayer.is_server():
			hero_moved.rpc_id(1, my_pos)
	view.update_frame(delta)
	_sound_watch()


## Turns changes in the match into sounds and music (host and clients alike).
var _snd := {}
func _sound_watch() -> void:
	var me: String = Net.my_name
	var now := {phase = phase, wave = wave, glow = glow, cd = float(hero_cd.get(me, 0.0)),
		gate = gate_closed_waves, ready = ready_names.has(me)}
	if _snd.is_empty():
		_snd = now
		Sfx.music("music_battle")
		return
	if now.phase != _snd.phase:
		match now.phase:
			"wave":
				Sfx.play("wave_start")
				if wave == D.BOSS_WAVE:
					Sfx.play_later("boss", 0.6)
			"build":
				if _snd.phase == "wave":
					Sfx.play("wave_clear")
			"victory":
				Sfx.duck(3.0)
				Sfx.play("victory")
				view.celebrate()
			"defeat":
				Sfx.duck(3.0)
				Sfx.play("defeat")
	if now.glow < _snd.glow - 0.01 and now.phase == "wave":
		Sfx.play("leak")
	if now.cd > _snd.cd + 1.0:
		Sfx.play("ability")
	if now.gate > _snd.gate:
		Sfx.play("gate")
	if now.ready and not _snd.ready:
		Sfx.play("ready")
	_snd = now


func _unhandled_input(event: InputEvent) -> void:
	if not visual:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = D.FAMILY_KEYS.find(event.keycode)
		if k >= 0:
			var fam: Array = D.towers_in(D.FAMILIES[k])
			var at := fam.find(selected_type)
			select_type(fam[(at + 1) % fam.size()] if at >= 0 else fam[0])
		match event.keycode:
			KEY_Q:
				use_ability()
			KEY_R:
				toggle_ready()
			KEY_U:
				upgrade_selected()
			KEY_X:
				sell_selected()
			KEY_ESCAPE:
				selected_cell = null
				hud.refresh()
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			selected_cell = null
			hud.refresh()
			return
		if event.button_index != MOUSE_BUTTON_LEFT:
			return
		var c = view.mouse_cell()
		if c == null:
			return
		if towers.has(c):
			selected_cell = c
		else:
			selected_cell = null
			place_tower(c, selected_type)
		hud.refresh()
