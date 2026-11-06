extends Node
## Music and sound effects (autoload `Sfx`). Sounds live in assets/audio/ and
## are made by art/tools/make_audio.py. Volumes are saved per computer.
##
##   Sfx.play("coin")            one-shot sound (throttled, slight pitch wobble)
##   Sfx.music("music_battle")   cross-fades to a looping track
##   Sfx.set_volume("Music", 0.6)

const SETTINGS_PATH := "user://settings.cfg"
const AUDIO := "res://assets/audio/%s.ogg"
const VOICES := 14

## Per-sound loudness trims (dB) so nothing shouts over the rest.
const TRIM := {
	"boss": -5.0, "build": -3.0, "ui_click": -9.0, "ui_hover": -14.0, "gate": -3.0,
	"shot_pebble": -7.0, "shot_jelly": -7.0, "splat": -6.0, "shot_frost": -9.0,
	"snuffer_pop": -5.0, "leak": -2.0, "defeat": -2.0,
}
## Shortest gap between repeats of the same sound (seconds).
const GAP := {
	"shot_pebble": 0.07, "shot_jelly": 0.1, "splat": 0.1, "shot_frost": 0.5,
	"snuffer_pop": 0.06, "leak": 0.3, "ui_hover": 0.05, "coin": 0.08,
}

var enabled := true
var _streams := {}
var _voices: Array[AudioStreamPlayer] = []
var _next := 0
var _last := {}
var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_name := ""
var volumes := {"Music": 0.6, "SFX": 0.8}
var _log := OS.has_environment("LANTERNFALL_SFX_LOG")  # testing aid


func _ready() -> void:
	enabled = not ("--server" in OS.get_cmdline_user_args()) and DisplayServer.get_name() != "headless"
	if not enabled:
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_voices.append(p)
	_music_a = _music_player()
	_music_b = _music_player()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	for bus in volumes:
		set_volume(bus, cfg.get_value("audio", bus, volumes[bus]), false)
	get_tree().node_added.connect(_on_node_added)


func _music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -80.0
	add_child(p)
	return p


func _stream(sound: String) -> AudioStream:
	if not _streams.has(sound):
		var path := AUDIO % sound
		_streams[sound] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sound]


func play(sound: String, volume_db := 0.0, pitch_wobble := 0.06) -> void:
	if not enabled:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(sound, -10.0)) < float(GAP.get(sound, 0.03)):
		return
	_last[sound] = now
	if _log:
		print("[sfx] ", sound)
	var s := _stream(sound)
	if s == null:
		return
	var p := _voices[_next]
	_next = (_next + 1) % _voices.size()
	p.stream = s
	p.volume_db = volume_db + float(TRIM.get(sound, 0.0))
	p.pitch_scale = 1.0 + randf_range(-pitch_wobble, pitch_wobble)
	p.play()


## Plays a sound after a short delay (e.g. a jelly landing).
func play_later(sound: String, delay: float, volume_db := 0.0) -> void:
	if enabled:
		get_tree().create_timer(delay).timeout.connect(play.bind(sound, volume_db))


func music(track: String, fade := 1.2) -> void:
	if not enabled or track == _music_name:
		return
	_music_name = track
	if _log:
		print("[music] ", track)
	var s := _stream(track)
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	var incoming := _music_b if _music_a.playing else _music_a
	var outgoing := _music_a if incoming == _music_b else _music_b
	incoming.stream = s
	incoming.volume_db = -40.0
	incoming.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(incoming, "volume_db", -6.0, fade)
	if outgoing.playing:
		tw.tween_property(outgoing, "volume_db", -60.0, fade)
		tw.chain().tween_callback(outgoing.stop)


## Briefly lowers the music (for big fanfares).
func duck(seconds := 2.5) -> void:
	if not enabled:
		return
	var idx := AudioServer.get_bus_index("Music")
	var base := linear_to_db(maxf(float(volumes.Music), 0.0001))
	var tw := create_tween()
	tw.tween_method(func(v): AudioServer.set_bus_volume_db(idx, v), base, base - 12.0, 0.2)
	tw.tween_interval(seconds)
	tw.tween_method(func(v): AudioServer.set_bus_volume_db(idx, v), base - 12.0, base, 0.8)


func set_volume(bus: String, value: float, save := true) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	if not enabled:
		return
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volumes[bus], 0.0001)))
		AudioServer.set_bus_mute(idx, volumes[bus] <= 0.001)
	if save:
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("audio", bus, volumes[bus])
		cfg.save(SETTINGS_PATH)


## Every button in the game clicks.
func _on_node_added(n: Node) -> void:
	if n is BaseButton and not n.has_meta("silent"):
		(n as BaseButton).pressed.connect(play.bind("ui_click"))
		(n as BaseButton).mouse_entered.connect(play.bind("ui_hover"))


## A Music + Sound slider pair, styled for the Lanternfall theme.
func make_sliders(parent: Node) -> void:
	for bus in ["Music", "SFX"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		parent.add_child(row)
		var l := Label.new()
		l.text = "Music" if bus == "Music" else "Sounds"
		l.custom_minimum_size.x = 70
		row.add_child(l)
		var s := HSlider.new()
		s.name = "Vol_" + bus
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = volumes[bus]
		s.custom_minimum_size = Vector2(200, 28)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		s.value_changed.connect(func(v): set_volume(bus, v))
		if bus == "SFX":
			s.drag_ended.connect(func(_c): play("coin"))
		row.add_child(s)
