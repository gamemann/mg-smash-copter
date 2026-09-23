extends Node

const ScGame := preload("../game/sc_game.gd")
const ScPlatforms := preload("../game/sc_platforms.gd")
const ScLayouts := preload("../game/sc_layouts.gd")

## Renders the game and exits. The check no assertion in this repository makes.
##
## [b]Everything about this map that can be wrong is invisible to every check in the
## suite.[/b] The suite proves a platform leans toward a load, collapses at an angle and
## carries what is on it. Not one of its ninety-five checks can tell you that the lean is
## the wrong way round on screen, that a pillar is drawn through its own platform, that the
## prototype grid came out one metre or eight, that the chopper is a pile of boxes, or that
## a player forty metres up cannot see the floor they are standing on. Four bugs in this
## family were each found by a picture, and one of them — the sign of a platform's normal —
## was found in this game by an assertion only because the assertion was written to measure
## the surface rather than the state.
##
## xvfb-run, never `--headless`: the headless display driver does no rendering at all, so a
## capture under it is a black PNG — which is worse than no screenshot, because it looks
## like one.
##
## [codeblock]
## tools/shot.sh                  # the field from a player's eyes
## tools/shot.sh --view=field     # the whole map from above and to one side
## tools/shot.sh --view=lean      # a platform that has been leant on, from its own level
## tools/shot.sh --view=copter    # the chopper, close
## tools/shot.sh --view=showdown  # the corners the round is finished in
## tools/shot.sh --view=jump      # the first jump the layout means, from behind the runner
## [/codeblock]

const CHANNEL := "sc.shot"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var seconds := 4.0
	var out := "res://screenshots/smash.png"
	var view := "eyes"

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))
		elif arg.begins_with("--out="):
			out = arg.substr(6)
		elif arg.begins_with("--view="):
			view = arg.substr(7)

	var client: Node = load("res://game/sc.tscn").instantiate()
	add_child(client)

	var elapsed := 0.0

	while elapsed < seconds:
		elapsed += get_process_delta_time()
		await get_tree().process_frame

	var game: ScGame = client.get("game")

	if game != null and view != "eyes":
		await _place_camera(game, view)

	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var _saved := image.save_png(ProjectSettings.globalize_path(out))

	print("wrote ", out, " after %.1f s, view=%s" % [elapsed, view])

	if game != null:
		for line in game.describe_lines():
			print(line)

	get_tree().quit(0)


## Puts a camera somewhere a first-person one can never be.
##
## [b]The one thing a player's own camera cannot show is the thing they are standing on.[/b]
## Every view below exists because a question about this map cannot be answered from eye
## height: whether the field reads as a field, whether a lean reads as a lean, and whether
## the machine in the sky reads as a helicopter.
func _place_camera(game: ScGame, view: String) -> void:
	var camera := Camera3D.new()
	camera.name = "Look"
	camera.fov = 70.0
	add_child(camera)

	match view:
		"field":
			# High and off one corner, which is the only angle that shows a grid of
			# platforms AS a grid — and the only one that shows how far apart they are,
			# which is the decision a player makes every few seconds.
			var reach := float(game.config.columns) * game.config.column_pitch
			camera.global_position = Vector3(
				reach * 0.78, game.config.deck_height + reach * 0.52, reach * 0.92
			)
			camera.look_at(Vector3(0.0, game.config.deck_height - 6.0, 0.0), Vector3.UP)
		"lean":
			await _lean_one(game)
			var deck := game.platforms.deck_at(0)

			if deck == null:
				camera.global_position = Vector3(0.0, game.config.deck_height + 10.0, 30.0)
				camera.look_at(Vector3(0.0, game.config.deck_height, 0.0), Vector3.UP)
				return

			# [b]Square on to the axis it is leaning about, and far enough back to see both
			# edges.[/b] A tilt photographed from above is a rhombus and a tilt photographed
			# from on top of it is nothing at all: what says which way a platform has gone is
			# one edge being lower than the other against the sky, which needs the camera at
			# about deck height and off to the side of the lean rather than along it.
			camera.global_position = deck.centre + Vector3(
				0.0, 3.4, deck.half * 4.2
			)
			camera.look_at(deck.centre, Vector3.UP)
		"copter":
			var copter := _a_copter(game)

			if copter == null:
				camera.global_position = Vector3(0.0, game.config.deck_height + 14.0, 26.0)
				camera.look_at(Vector3(0.0, game.config.deck_height, 0.0), Vector3.UP)
			else:
				var at := copter.position()
				camera.global_position = at + Vector3(9.0, 3.4, 9.0)
				camera.look_at(at, Vector3.UP)
		"jump":
			# [b]From where a runner stands before the jump the layout MEANS[/b], a little
			# above their eye, looking along the line they will run. A field from above says
			# where the platforms are and nothing about whether the gap between two of them
			# is a jump; this is the picture of the one question the reach section asks.
			var pair := _first_meant_jump(game)

			if pair == Vector2i(-1, -1):
				camera.global_position = Vector3(0.0, game.config.deck_height + 18.0, 42.0)
				camera.look_at(Vector3(0.0, game.config.deck_height, 0.0), Vector3.UP)
			else:
				var from := game.platforms.deck_at(pair.x).centre
				var to := game.platforms.deck_at(pair.y).centre
				var line := Vector3(to.x - from.x, 0.0, to.z - from.z).normalized()
				camera.global_position = from - line * 4.0 + Vector3.UP * 3.2
				camera.look_at(to + Vector3.UP * 0.5, Vector3.UP)
		"showdown":
			var middle := game.arena.showdown_centre()
			camera.global_position = middle + Vector3(
				0.0, game.config.corner_distance * 0.9, game.config.corner_distance * 1.5
			)
			camera.look_at(middle, Vector3.UP)
		_:
			camera.global_position = Vector3(0.0, game.config.deck_height + 18.0, 42.0)
			camera.look_at(Vector3(0.0, game.config.deck_height, 0.0), Vector3.UP)

	camera.current = true
	await get_tree().process_frame


## The first pair of platforms the round's layout means a player to jump between.
func _first_meant_jump(game: ScGame) -> Vector2i:
	if game.layout == null or game.layout.jumps == 0:
		return Vector2i(-1, -1)

	for pair: Vector3i in ScLayouts.pairs(game.platforms.cells()):
		if (game.layout.jumps & pair.z) != 0:
			return Vector2i(pair.x, pair.y)

	return Vector2i(-1, -1)


## Leans the first platform hard, so there is something to photograph.
##
## A platform in a fresh round is level, and a picture of a level platform says nothing
## about whether the lean is drawn the right way round — which is the bug this view exists
## to catch.
func _lean_one(game: ScGame) -> void:
	var platforms := game.platforms
	var deck := platforms.deck_at(0)

	if deck == null:
		return

	var at := deck.centre + Vector3(deck.half * 0.85, 0.0, 0.0)

	# [b]Heavy, because the spring is the point.[/b] A platform finds an equilibrium against
	# whatever is standing on it, so an ordinary player's eighty kilograms is three degrees —
	# which is exactly the amount a picture cannot settle. What is being checked here is which
	# WAY it goes, so the load is enough to take it near its own collapse angle.
	for _i in range(90):
		platforms.begin_loads()
		platforms.add_load(0, at, 520.0, 0.0)
		platforms.step(1.0 / 64.0)
		await get_tree().process_frame

	print("leaned platform 0 by %.1f degrees toward +X" % rad_to_deg(deck.tilt()))


func _a_copter(game: ScGame) -> DotVehicleInstance:
	if game.vehicles == null:
		return null

	var all := game.vehicles.all_vehicles()

	if not all.is_empty():
		return all[0]

	# A layout without one still has to be photographable, or the only way to look at the
	# machine is to keep re-rolling until a layout with a pad comes up.
	return game.vehicles.spawn(
		&"copter",
		Vector3(0.0, game.config.deck_height + game.config.chopper_pad_height, 0.0),
		&"world"
	)
