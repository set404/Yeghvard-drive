extends Control
## Subtitles for the story's scenes, along the bottom of the screen: who says
## what, one line after another, each up long enough to read (Enter skips to the
## next). A mission hands play() a script, a list of:
##
##   say("Davitik", "Hey gyada")   a line (shown for `seconds`, or long enough to read),
##                                 spoken in the speaker's mumble voice (game/mumble.gd)
##                                 as it types out; `anim` names what the speaker does
##                                 meanwhile (line_started tells the mission), `phone`
##                                 that it is heard over the phone
##   wait(1.5)                     nothing for a while
##   run(func(): ...)              something done at that point (start the car...)
##   until(func(): return ..., 8)  waits till it says true (or `timeout` seconds)
##   ring("Davitik")               the phone rings, "Davitik calling..."
##
## A line with a recording (audio/voices/, made by tools/make_voices.py: named
## after who says it and what) is played; one without is mumbled.
##
## Besides: bark() puts up a quick shout over everything else (Davitik when a
## car hits him), show_counter() a line in the top right corner, fade() a
## quick fade to black and back with something done in the dark.

signal finished
## A line starts: who says it, what, for how long, and what they do meanwhile ("" for just talking).
signal line_started(who: String, text: String, seconds: float, anim: String)

const Sfx := preload("res://game/sfx.gd")
const Mumble := preload("res://game/mumble.gd")
## Each speaker's name in their own colour.
const COLORS := {
	"Davitik": Color(0.5, 0.83, 1.0),
	"Vzgo": Color(1.0, 0.83, 0.42),
	"Uncle": Color(0.72, 0.95, 0.6),
	"Papa": Color(1.0, 0.6, 0.55),
}
## The speakers' names as the subtitles show them; the keys stay as they are
## for COLORS, the voices (voice_path()) and the missions' speaker checks.
const NAMES := {
	"Davitik": "Դավիթիկ",
	"Vzgo": "Վզգո",
	"Uncle": "Քեռի",
	"Papa": "Պապա",
}
## Seconds a line stays up: this, and so much for each letter.
const LINE_BASE := 1.3
const LINE_PER_CHAR := 0.055
## Where the lines' recordings are (see voice_path()).
const VOICE_DIR := "res://audio/voices/"

var _queue: Array[Dictionary] = []
var _current: Dictionary = {}
var _left := 0.0
var _box: PanelContainer
var _who: Label
var _text: Label
var _call: Label
var _bark: Label
var _bark_left := 0.0
var _counter: Label
var _fade: ColorRect
## The line typing out: how far (seconds), how long it takes, the voice speaking
## it, its syllables (Mumble.syllables_of()) and the next one to say, whether it
## asks something and whether it is laughter.
var _typed := 0.0
var _type_time := 0.0
var _voice := ""
var _voice_phone := false
var _syllables := []
var _syllable := 0
var _question := false
var _laughing := false
var _shouting := false
var _speech: AudioStreamPlayer
## Plays a line's recording, and a shout's.
var _voice_player: AudioStreamPlayer
var _bark_player: AudioStreamPlayer


static func say(who: String, text: String, seconds := 0.0, anim := "", phone := false) -> Dictionary:
	return {"who": who, "text": text, "seconds": seconds, "anim": anim, "phone": phone}


static func wait(seconds: float) -> Dictionary:
	return {"wait": seconds}


static func run(action: Callable) -> Dictionary:
	return {"do": action}


static func until(test: Callable, timeout := 0.0) -> Dictionary:
	return {"until": test, "timeout": timeout}


static func ring(caller: String, seconds := 3.5) -> Dictionary:
	return {"ring": caller, "seconds": seconds}


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = PanelContainer.new()
	_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_box.offset_left = -560.0
	_box.offset_right = 560.0
	_box.offset_top = -190.0
	_box.offset_bottom = -110.0
	_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.62)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(12.0)
	_box.add_theme_stylebox_override("panel", style)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(rows)
	_who = Label.new()
	_who.add_theme_font_size_override("font_size", 20)
	rows.add_child(_who)
	_text = Label.new()
	_text.add_theme_font_size_override("font_size", 27)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(1090.0, 0.0)
	rows.add_child(_text)
	_box.visible = false
	add_child(_box)

	_call = _label(34, Color(0.6, 1.0, 0.6))
	_call.set_anchors_preset(Control.PRESET_CENTER)
	_call.offset_left = -400.0
	_call.offset_right = 400.0
	_call.offset_top = 40.0
	_call.offset_bottom = 90.0
	_call.visible = false

	_bark = _label(40, Color(1.0, 0.95, 0.4))
	_bark.set_anchors_preset(Control.PRESET_CENTER)
	_bark.offset_left = -500.0
	_bark.offset_right = 500.0
	_bark.offset_top = -160.0
	_bark.offset_bottom = -100.0
	_bark.visible = false

	_counter = _label(22, Color(1.0, 0.95, 0.85))
	_counter.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_counter.offset_left = -520.0
	_counter.offset_right = -24.0
	_counter.offset_top = 150.0
	_counter.offset_bottom = 260.0
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.visible = false

	_speech = AudioStreamPlayer.new()
	var poly := AudioStreamPolyphonic.new()
	poly.polyphony = 6
	_speech.stream = poly
	add_child(_speech)
	_voice_player = AudioStreamPlayer.new()
	add_child(_voice_player)
	_bark_player = AudioStreamPlayer.new()
	add_child(_bark_player)

	_fade = ColorRect.new()
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0.0, 0.0, 0.0, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 10)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


## Plays `script` (see the top), after whatever is already playing.
func play(script: Array) -> void:
	for entry: Dictionary in script:
		_queue.append(entry)
	if _current.is_empty():
		_next()


## Whether a script is still playing.
func busy() -> bool:
	return not _current.is_empty() or not _queue.is_empty()


## Drops whatever is playing.
func stop() -> void:
	_voice_player.stop()
	_queue.clear()
	_current = {}
	_box.visible = false
	_call.visible = false


## A quick shout in the middle of the screen, over everything (for `seconds`).
## The recording of `who` saying `text` (over the phone: `phone`), as
## tools/make_voices.py names it (.ogg), or a recording by people of an
## Armenian line under the same name (.wav or .mp3); "" if there is none.
static func voice_path(who: String, text: String, phone := false) -> String:
	var base := voice_base(who, text, phone)
	for ext in [".ogg", ".wav", ".mp3"]:
		if ResourceLoader.exists(base + ext) or FileAccess.file_exists(base + ext):
			return base + ext
	return ""


## Where the recording of `who` saying `text` goes, without its extension.
static func voice_base(who: String, text: String, phone := false) -> String:
	return "%s%s_%s%s" % [VOICE_DIR, who.to_lower(), ("%s|%s" % [who, text]).md5_text().substr(0, 10), "_phone" if phone else ""]


## The recording at `path` (imported by the editor, or read straight from the file).
static func load_voice(path: String) -> AudioStream:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		return load(path) as AudioStream
	if path.ends_with(".wav"):
		return AudioStreamWAV.load_from_file(path)
	if path.ends_with(".mp3"):
		return AudioStreamMP3.load_from_file(path)
	return AudioStreamOggVorbis.load_from_file(path)


func bark(who: String, text: String, seconds := 2.2) -> void:
	var recording := load_voice(voice_path(who, text)) if who != "" else null
	if recording:
		_bark_player.stream = recording
		_bark_player.play()
		seconds = maxf(seconds, recording.get_length() + 0.3)
	_bark.text = ("%s՝ «%s»" % [NAMES.get(who, who), text]) if who != "" else text
	_bark.add_theme_color_override("font_color", COLORS.get(who, Color(1.0, 0.95, 0.4)))
	_bark_left = seconds
	_bark.visible = true


## A line of text in the top right corner ("" hides it).
func show_counter(text: String) -> void:
	_counter.text = text
	_counter.visible = text != ""


## Fades to black, does `in_the_dark`, and fades back.
func fade(in_the_dark: Callable, seconds := 0.35) -> void:
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, seconds)
	t.tween_callback(in_the_dark)
	t.tween_interval(0.2)
	t.tween_property(_fade, "color:a", 0.0, seconds)


func _process(delta: float) -> void:
	if _bark_left > 0.0:
		_bark_left -= delta
		_bark.visible = _bark_left > 0.0
		_bark.modulate.a = clampf(_bark_left * 3.0, 0.0, 1.0)
	if _current.is_empty():
		return
	if _current.has("text"):
		_type(delta)
	_left -= delta
	if _current.has("until"):
		var timeout := float(_current["timeout"])
		if (_current["until"] as Callable).call() or (timeout > 0.0 and _left <= 0.0):
			_next()
		return
	if _left <= 0.0:
		_next()


## Enter (or the keypad's) skips the line up now.
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if (key.physical_keycode == KEY_ENTER or key.physical_keycode == KEY_KP_ENTER) and _current.has("text"):
		# Still typing: all of it at once; already out: the next line.
		if _typed < _type_time:
			_typed = _type_time
			_text.visible_ratio = 1.0
		else:
			_left = 0.0
			_voice_player.stop()
		get_viewport().set_input_as_handled()


## Types the line out, saying each syllable in the speaker's voice as the
## typing reaches its vowel (so the gaps between words are quiet).
func _type(delta: float) -> void:
	if _typed >= _type_time:
		return
	_typed += delta
	_text.visible_ratio = clampf(_typed / _type_time, 0.0, 1.0) if _type_time > 0.0 else 1.0
	if _voice == "":
		return
	var shown := int(_text.visible_ratio * _text.text.length())
	# After a slow frame, only the latest of the syllables passed meanwhile.
	var due := -1
	while _syllable < _syllables.size() and int(_syllables[_syllable]["at"]) <= shown:
		due = _syllable
		_syllable += 1
	if due >= 0:
		_say(due)


## Says syllable `index` of the line: the pitch falling a little over the line
## as speech does, up on a word's last syllable (where Armenian stresses it)
## and at the end of a question; laughter in high bursts.
func _say(index: int) -> void:
	var s: Dictionary = _syllables[index]
	var through := float(index) / maxf(_syllables.size() - 1, 1.0)
	var pitch := 1.06 - 0.12 * through + randf_range(-0.025, 0.025)
	var louder := 0.0
	if s["stress"]:
		pitch += 0.045
		louder = 1.0
	if _question and index >= _syllables.size() - 2:
		pitch += 0.12
	if _laughing:
		pitch = 1.3 if index % 2 == 0 else 1.45
	elif _shouting:
		pitch *= 1.12
	var playback := _speech.get_stream_playback() as AudioStreamPlaybackPolyphonic if _speech.playing else null
	if playback == null:
		_speech.play()
		playback = _speech.get_stream_playback() as AudioStreamPlaybackPolyphonic
	if playback:
		var sound := Mumble.sound(_voice, s["cons"], s["vowel"], _voice_phone)
		playback.play_stream(sound, 0.0, (2.0 if _shouting or _laughing else -2.0) + louder, pitch)


func _next() -> void:
	_box.visible = false
	_call.visible = false
	while not _queue.is_empty():
		var entry: Dictionary = _queue.pop_front()
		if entry.has("do"):
			(entry["do"] as Callable).call()
			continue
		_current = entry
		if entry.has("text"):
			var who: String = entry["who"]
			_who.text = NAMES.get(who, who)
			_who.visible = who != ""
			_who.add_theme_color_override("font_color", COLORS.get(who, Color(0.85, 0.85, 0.85)))
			var text: String = entry["text"]
			_text.text = text if who == "" or (text.begins_with("*") and text.ends_with("*")) else "«%s»" % text
			_box.visible = true
			var seconds := float(entry["seconds"])
			_left = seconds if seconds > 0.0 else LINE_BASE + LINE_PER_CHAR * text.length()
			# Typed out (and spoken) over most of the time it is up; an action
			# ("*...*") or a line with no speaker appears at once, unspoken.
			var spoken := who != "" and not (text.begins_with("*") and text.ends_with("*"))
			_voice = who if spoken else ""
			_voice_phone = bool(entry.get("phone", false))
			# Recorded: played, the line up as long as it lasts, typed out as it is said.
			var recording := load_voice(voice_path(who, text, _voice_phone)) if spoken else null
			if recording:
				_voice_player.stream = recording
				_voice_player.play()
				var length := recording.get_length()
				_left = maxf(_left if seconds > 0.0 else 0.0, length + 0.45)
			_laughing = text.to_upper().contains("HA HA") or text.contains("ՀԱ ՀԱ")
			_shouting = text.contains("!") or (text.to_upper() == text and text.length() > 4)
			_question = text.contains("?") or text.contains("՞")
			# About six syllables a second, at the speaker's pace.
			var per_char := 0.06 / float(Mumble.voice(who)["pace"])
			_type_time = minf(_left * 0.8, text.length() * per_char) if spoken else 0.0
			if recording:
				_type_time = recording.get_length() * 0.9
				_voice = ""
			_syllables = Mumble.syllables_of(_text.text) if _voice != "" else []
			_syllable = 0
			_typed = 0.0
			_text.visible_ratio = 0.0 if _type_time > 0.0 else 1.0
			line_started.emit(who, text, _left, String(entry.get("anim", "")))
		elif entry.has("wait"):
			_left = float(entry["wait"])
		elif entry.has("ring"):
			_call.text = "Զանգում է՝ %s...  (հեռախոսը զնգում է)" % NAMES.get(entry["ring"], entry["ring"])
			_call.visible = true
			Sfx.play_flat(self, Sfx.ring(), -8.0)
			_left = float(entry["seconds"])
		elif entry.has("until"):
			_left = float(entry["timeout"])
		return
	_current = {}
	finished.emit()
