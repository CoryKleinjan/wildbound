class_name Options
## The OPTIONS menu (text speed, battle scene, battle style, sound) and the real-time clock.
## Settings belong to this computer, not to a save, so they live in user://settings.json.

const PATH := "user://settings.json"
const SPEEDS := {"SLOW": 45.0, "MID": 90.0, "FAST": 240.0}

static var _s: Dictionary = {}

static func _opt(key: String, default: Variant) -> Variant:
	if _s.is_empty():
		_s = {"text": "MID", "scene": true, "style": "SHIFT", "sound": true}
		if FileAccess.file_exists(PATH):
			var f := FileAccess.open(PATH, FileAccess.READ)
			var v: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
			if v is Dictionary:
				_s.merge(v, true)
	return _s.get(key, default)

static func _put(key: String, value: Variant) -> void:
	_opt(key, null)
	_s[key] = value
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_s))

## Characters per second for dialog text.
static func text_speed() -> float:
	return SPEEDS.get(_opt("text", "MID"), 90.0)

## Whether battle animations play.
static func battle_scene() -> bool:
	return _opt("scene", true)

## SHIFT: offered a switch when a trainer sends out their next creature. SET: no offer.
static func shift_style() -> bool:
	return _opt("style", "SHIFT") == "SHIFT"

static func sound_on() -> bool:
	return _opt("sound", true)

## Applies the settings that live outside this class (the sound switch).
static func apply() -> void:
	AudioServer.set_bus_mute(0, not sound_on())

static func open_menu(player: int, on_close: Callable) -> void:
	var ref := {}
	var rows := func() -> Array:
		return [
			{"label": "TEXT SPEED", "right": _opt("text", "MID")},
			{"label": "BATTLE SCENE", "right": "ON" if battle_scene() else "OFF"},
			{"label": "BATTLE STYLE", "right": _opt("style", "SHIFT")},
			{"label": "SOUND", "right": "ON" if sound_on() else "OFF"},
			{"label": "CLOCK", "right": clock_text()},
			{"label": "DONE"},
		]
	var open := func(self_ref: Callable, start: int) -> void:
		var menu := ListMenu.new({
			"x": 40, "y": 20, "w": 160, "player": player, "title": "OPTIONS", "items": rows.call(), "start": start,
			"footer": func(i: int) -> String:
				return ["How fast text appears.", "Show move animations in battle.",
					"SHIFT lets you switch after a trainer's creature faints.", "Music and sound effects.",
					"The real-time clock. Berries grow and daily events change with it.", ""][i],
			"on_cancel": func() -> void:
				Game.pop(ref.menu)
				on_close.call(),
			"on_select": func(i: int) -> void:
				Game.pop(ref.menu)
				match i:
					0:
						var order := SPEEDS.keys()
						_put("text", order[(order.find(_opt("text", "MID")) + 1) % order.size()])
					1:
						_put("scene", not battle_scene())
					2:
						_put("style", "SET" if shift_style() else "SHIFT")
					3:
						_put("sound", not sound_on())
						apply()
					5:
						on_close.call()
						return
				self_ref.call(self_ref, i),
		})
		ref.menu = menu
		Game.push(menu)
	open.call(open, 0)

# ---------- clock ----------
## Seconds since 1970 from the system clock.
static func now() -> int:
	return int(Time.get_unix_time_from_system())

## Day number (local time), for once-a-day events.
static func today() -> int:
	return int((now() + Time.get_time_zone_from_system().bias * 60) / 86400)

static func clock_text() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%02d:%02d" % [t.hour, t.minute]

## "morning" (4-10), "day" (10-18), "evening" (18-20) or "night".
static func time_of_day() -> String:
	var h: int = Time.get_datetime_dict_from_system().hour
	if h >= 4 and h < 10:
		return "morning"
	if h >= 10 and h < 18:
		return "day"
	if h >= 18 and h < 20:
		return "evening"
	return "night"
