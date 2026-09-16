extends CanvasLayer

const ScGame := preload("sc_game.gd")
const ScPlayer := preload("sc_player.gd")

## The clock, the health, and the two numbers that say whether this is still winnable.
##
## [b]How many platforms are left is the number that is not obvious and is the most
## important of the four.[/b] Health says how many mistakes you have left and the clock says
## how long you have to survive; neither says whether surviving is still possible. The
## platform count does: a field down to its last three is a field where standing still has
## stopped working, and a player who watches that number fall starts moving before it is too
## late rather than after.
##
## [b]And the lean of the floor you are on, which nothing else could tell you.[/b] A player
## in first person looking at the horizon cannot see the platform under their feet; the one
## in third person can see it and cannot judge it. Ten degrees is the number, and the bar
## goes red at the angle a player starts sliding.

# No `const CHANNEL`. This draws numbers from state somebody else owns and has nothing an
# operator would act on; the round, the deaths and the collapses are logged by [ScGame],
# which is where the decisions are. A channel declared and never used is a file that meant
# to say something and does not.

## Radians of lean at which the tilt bar goes red. The angle a player slides at.
const SLIDE_LEAN := 0.244

var game: ScGame = null
var player: ScPlayer = null

var _clock: Label = null
var _phase: Label = null
var _health: Label = null
var _field: Label = null
var _special: Label = null
var _shout: Label = null
var _tilt_back: ColorRect = null
var _tilt_fill: ColorRect = null
var _root: Control = null

## Seconds left of the big shouted line in the middle of the screen.
var _shout_for: float = 0.0


func bind(p_game: ScGame, p_player: ScPlayer) -> void:
	game = p_game
	player = p_player

	if _root == null:
		_build()


func _build() -> void:
	# [b]A full-rect Control between the CanvasLayer and the labels, and the first render of
	# game-buses-from-hell is why.[/b] A CanvasLayer is not a Control and does not lay its
	# children out, so anchors on a Label parented straight to one resolve against nothing:
	# every label lands in the top-left corner on top of the others, and the only one
	# visible is whichever drew last, clipped in half by the edge of the screen. It reads as
	# the HUD being half-written.
	_root = Control.new()
	_root.name = "Screen"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var size := 22

	_clock = _label(size + 14)
	_clock.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_clock.offset_top = 16.0
	_clock.offset_bottom = 72.0
	_clock.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_phase = _label(size)
	_phase.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_phase.offset_top = 74.0
	_phase.offset_bottom = 108.0
	_phase.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_special = _label(size)
	_special.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_special.offset_top = 110.0
	_special.offset_bottom = 144.0
	_special.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_special.add_theme_color_override("font_color", Color(0.98, 0.78, 0.33))

	_shout = _label(size + 20)
	_shout.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_shout.offset_top = 190.0
	_shout.offset_bottom = 260.0
	_shout.offset_left = -520.0
	_shout.offset_right = 520.0
	_shout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shout.add_theme_color_override("font_color", Color(0.99, 0.86, 0.40))

	# [b]Above the chat box, because the chat box also draws itself bottom-left.[/b] The
	# first render had the health number and the first line of chat in the same forty pixels,
	# one on top of the other — which is exactly the shape of the bug game-buses-from-hell
	# shipped with four HUD labels, and is invisible to a headless suite because a headless
	# viewport is 64 x 64 and nothing there can overlap anything.
	_health = _label(size + 16)
	_health.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_health.offset_left = 30.0
	_health.offset_right = 300.0
	_health.offset_top = -210.0
	_health.offset_bottom = -150.0

	_field = _label(size)
	_field.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_field.offset_left = -400.0
	_field.offset_right = -30.0
	_field.offset_top = -80.0
	_field.offset_bottom = -26.0
	_field.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	_build_tilt()

	# A dot rather than a cross. For the whole first half there is nothing to aim at, and in
	# the second half every weapon in the pack has its own spread — so what a player needs is
	# "the point I am looking at", which is one pixel.
	var dot := ColorRect.new()
	dot.name = "Crosshair"
	dot.color = Color(1.0, 1.0, 1.0, 0.75)
	dot.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	dot.offset_left = -3.0
	dot.offset_top = -3.0
	dot.offset_right = 3.0
	dot.offset_bottom = 3.0
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dot)


## The one instrument in the game: how far over the floor you are standing on has gone.
func _build_tilt() -> void:
	_tilt_back = ColorRect.new()
	_tilt_back.name = "TiltBack"
	_tilt_back.color = Color(0.0, 0.0, 0.0, 0.42)
	_tilt_back.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tilt_back.offset_left = -150.0
	_tilt_back.offset_right = 150.0
	_tilt_back.offset_top = -46.0
	_tilt_back.offset_bottom = -30.0
	_tilt_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tilt_back)

	_tilt_fill = ColorRect.new()
	_tilt_fill.name = "TiltFill"
	_tilt_fill.color = Color(0.45, 0.82, 0.48, 0.9)
	_tilt_fill.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_tilt_fill.offset_left = -150.0
	_tilt_fill.offset_right = -150.0
	_tilt_fill.offset_top = -46.0
	_tilt_fill.offset_bottom = -30.0
	_tilt_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_tilt_fill)


func _label(size: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	# An outline rather than a panel behind it. This HUD is drawn over a bright sky, a dark
	# floor and a grey platform in the same frame; white is unreadable over one and black
	# over another, and an outline is readable over all three and costs nothing.
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(label)
	return label


## One line in the middle of the screen, for a few seconds. What a special announces itself
## with, and what a round ending says.
func shout(text: String, seconds: float = 3.5) -> void:
	if _shout == null:
		return

	_shout.text = text
	_shout_for = seconds


func _process(delta: float) -> void:
	if game == null or game.config == null or _root == null:
		return

	var left := game.seconds_left()
	_clock.text = "%d:%02d" % [int(left) / 60, int(left) % 60]
	_phase.text = _phase_line()
	_special.text = game.special_line()

	if player != null and player.health != null:
		_health.text = "%d" % int(round(player.health.health))
		# Red below a quarter, which in the showdown is one burst from gone and in the
		# survival phase is one crate.
		var hurt := player.health.health <= player.health.max_health * 0.25
		_health.add_theme_color_override(
			"font_color", Color(1.0, 0.35, 0.3) if hurt else Color(1, 1, 1)
		)

	_field.text = "%d up   %d left   %d sides" % [
		game.standing_platforms(), game.alive_count(), game.teams_alive(),
	]

	_draw_tilt()

	if _shout_for > 0.0:
		_shout_for -= delta

		if _shout_for <= 0.0:
			_shout.text = ""


func _phase_line() -> String:
	if not game.sides_are_playable():
		return "waiting for players"

	match game.phase:
		ScGame.Phase.SURVIVAL:
			if player != null and player.riding:
				return "flying"
			return "stay on something"
		ScGame.Phase.HANDOVER:
			return "hold — weapons hot shortly"
		ScGame.Phase.SHOWDOWN:
			return "last team standing"
		_:
			return "between rounds"


## The tilt bar, from the platform the player is actually on.
##
## Hidden when they are not on one, because a bar reading zero while somebody is falling
## says the floor is level rather than that there is no floor.
func _draw_tilt() -> void:
	if _tilt_fill == null or _tilt_back == null:
		return

	var deck = game.platforms.deck_at(player.standing_on) if player != null and game.platforms != null else null

	if deck == null:
		_tilt_back.visible = false
		_tilt_fill.visible = false
		return

	_tilt_back.visible = true
	_tilt_fill.visible = true

	var fraction := clampf(deck.tilt() / maxf(game.config.platform_collapse_lean, 0.001), 0.0, 1.0)
	_tilt_fill.offset_right = -150.0 + 300.0 * fraction

	var sliding := deck.tilt() >= SLIDE_LEAN

	_tilt_fill.color = (
		Color(0.92, 0.28, 0.26, 0.95) if sliding
		else Color(0.45, 0.82, 0.48, 0.9).lerp(Color(0.95, 0.76, 0.28, 0.92), fraction)
	)
