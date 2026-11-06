extends Node
## Player accounts (autoload "Accounts"), used only on the server.
## Stored as JSON in LANTERNFALL_DATA (the Docker volume), or user://server_data
## when running from the editor. PINs are salted and hashed, never stored as-is.
## A PIN keeps family progress separate; it is not strong security.

const FILE_NAME := "accounts.json"

var data_dir := ""
var accounts: Dictionary = {}  # lowercase name -> record


func _ready() -> void:
	data_dir = OS.get_environment("LANTERNFALL_DATA")
	if data_dir.is_empty():
		data_dir = "user://server_data"
	DirAccess.make_dir_recursive_absolute(data_dir)


func _path() -> String:
	return data_dir.path_join(FILE_NAME)


func load_all() -> void:
	accounts = {}
	if not FileAccess.file_exists(_path()):
		return
	var f := FileAccess.open(_path(), FileAccess.READ)
	if f == null:
		push_error("Could not read %s" % _path())
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		accounts = parsed
	print("[server] loaded %d accounts from %s" % [accounts.size(), _path()])


func save_all() -> void:
	var tmp := _path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("Could not write %s" % tmp)
		return
	f.store_string(JSON.stringify(accounts, "  "))
	f.close()
	DirAccess.rename_absolute(tmp, _path())


func check_or_create(player_name: String, pin: String) -> Dictionary:
	var key := player_name.to_lower()
	var now := Time.get_datetime_string_from_system(true)
	if accounts.has(key):
		var a: Dictionary = accounts[key]
		if _hash(pin, a.salt) != a.pin_hash:
			return {ok = false, message = "Wrong PIN for %s." % a.name}
		a.last_seen = now
		save_all()
		return {ok = true, name = a.name, message = "Welcome back, %s!" % a.name}
	var salt := Crypto.new().generate_random_bytes(16).hex_encode()
	accounts[key] = {
		name = player_name,
		salt = salt,
		pin_hash = _hash(pin, salt),
		created = now,
		last_seen = now,
		level = 1,
		xp = 0,
		towers_placed = 0,
	}
	save_all()
	return {ok = true, name = player_name, message = "Account created. Welcome, %s!" % player_name}


func add_stat(player_name: String, stat: String, amount: int = 1) -> void:
	var key := player_name.to_lower()
	if not accounts.has(key):
		return
	accounts[key][stat] = int(accounts[key].get(stat, 0)) + amount
	save_all()


func get_record(player_name: String) -> Dictionary:
	return accounts.get(player_name.to_lower(), {})


func _hash(pin: String, salt: String) -> String:
	return (salt + ":" + pin).sha256_text()
