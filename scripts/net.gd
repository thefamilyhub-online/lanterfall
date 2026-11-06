extends Node
## Networking hub (autoload "Net").
## The server is authoritative: clients only send requests, the server decides
## and broadcasts the result. Works as a dedicated server (`-- --server`) or as a
## "host & play" listen server where the host is also player 1.

const GAME_VERSION := "0.2.0"
const D := preload("res://scripts/data.gd")
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8

signal login_finished(ok: bool, message: String)
signal connection_lost(message: String)
signal players_updated
signal player_logged_in(peer_id: int)

var is_dedicated := false
var map_id := "gumdrop_glade"   # which map this server plays
var my_name := ""
var my_hero := "bramble"
var players: Dictionary = {}  # peer_id (int) -> display name (String)

var _pending := {}


func _ready() -> void:
	is_dedicated = "--server" in OS.get_cmdline_user_args()
	if OS.get_environment("LANTERNFALL_MAP") != "":
		map_id = OS.get_environment("LANTERNFALL_MAP")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map_id = a.substr(6)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


# ---------------------------------------------------------------- server side

func start_server(port: int = DEFAULT_PORT) -> Error:
	D.select_map(map_id)
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	Accounts.load_all()
	print("[server] Lanternfall %s listening on UDP %d" % [GAME_VERSION, port])
	return OK


## Host & play: start a server and log the host in as player 1.
func host_and_play(port: int, player_name: String, pin: String) -> void:
	var err := start_server(port)
	if err != OK:
		login_finished.emit(false, "Could not start a server on port %d (error %d)." % [port, err])
		return
	my_name = player_name.strip_edges()
	var res := _server_login(1, player_name, pin, GAME_VERSION)
	if not res.ok:
		leave()
	login_finished.emit(res.ok, res.message)


func _server_login(peer_id: int, player_name: String, pin: String, version: String) -> Dictionary:
	if version != GAME_VERSION:
		return {ok = false, message = "Please update: the server runs %s, you have %s." % [GAME_VERSION, version]}
	player_name = player_name.strip_edges()
	if not _valid_name(player_name):
		return {ok = false, message = "Names are 2–16 letters, numbers, spaces, - or _."}
	if not _valid_pin(pin):
		return {ok = false, message = "PINs are 4–6 digits."}
	for n in players.values():
		if String(n).to_lower() == player_name.to_lower():
			return {ok = false, message = "%s is already playing." % player_name}
	var res := Accounts.check_or_create(player_name, pin)
	if not res.ok:
		return res
	players[peer_id] = res.name
	_broadcast_players()
	player_logged_in.emit(peer_id)
	print("[server] %s logged in (peer %d)" % [res.name, peer_id])
	return res


@rpc("any_peer", "reliable")
func request_login(player_name: String, pin: String, version: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	var res := _server_login(id, player_name, pin, version)
	login_result.rpc_id(id, res.ok, res.message, map_id)
	if not res.ok:
		await get_tree().create_timer(0.5).timeout
		if multiplayer.multiplayer_peer is ENetMultiplayerPeer:
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)


func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server() and players.has(id):
		print("[server] %s left" % players[id])
		players.erase(id)
		_broadcast_players()


func _broadcast_players() -> void:
	set_players.rpc(players)


func _valid_name(n: String) -> bool:
	if n.length() < 2 or n.length() > 16:
		return false
	var re := RegEx.create_from_string("^[A-Za-z0-9 _-]+$")
	return re.search(n) != null


func _valid_pin(p: String) -> bool:
	return p.length() >= 4 and p.length() <= 6 and p.is_valid_int()


# ---------------------------------------------------------------- client side

func join(address: String, port: int, player_name: String, pin: String) -> void:
	my_name = player_name.strip_edges()
	_pending = {name = player_name, pin = pin}
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		login_finished.emit(false, "Could not start a connection (error %d)." % err)
		return
	multiplayer.multiplayer_peer = peer


func leave() -> void:
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()


func _on_connected_to_server() -> void:
	request_login.rpc_id(1, _pending.name, _pending.pin, GAME_VERSION)


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	login_finished.emit(false, "Could not reach the server. Check the address and that it is running.")


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	connection_lost.emit("Disconnected from the server.")


@rpc("authority", "reliable")
func login_result(ok: bool, message: String, server_map := "gumdrop_glade") -> void:
	map_id = server_map
	D.select_map(map_id)
	login_finished.emit(ok, message)


@rpc("authority", "reliable", "call_local")
func set_players(p: Dictionary) -> void:
	players = p
	players_updated.emit()


## Send a message to one peer, working for the host (peer 1) too.
func is_local(peer_id: int) -> bool:
	return multiplayer.multiplayer_peer != null and peer_id == multiplayer.get_unique_id()
