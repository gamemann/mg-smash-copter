extends Node

const ScArena := preload("../game/sc_arena.gd")
const ScCannon := preload("../game/sc_cannon.gd")
const ScConfig := preload("../game/sc_config.gd")
const ScContent := preload("../game/sc_content.gd")
const ScCopter := preload("../game/sc_copter.gd")
const ScGame := preload("../game/sc_game.gd")
const ScHud := preload("../game/sc_hud.gd")
const ScLayouts := preload("../game/sc_layouts.gd")
const ScPlatforms := preload("../game/sc_platforms.gd")
const ScPaths := preload("../game/sc_paths.gd")
const ScPlayer := preload("../game/sc_player.gd")
const ScSpecials := preload("../game/sc_specials.gd")

## Proves the platforms, the cannon, the round and the chopper all actually work.
##
## [codeblock]
## godot --headless --path . res://examples/headless_run.tscn
## [/codeblock]
##
## [b]The checks that matter are the ones that cross an addon boundary, and the ones that
## measure the model this game invented.[/b] dot-props, dot-combat, dot-match and dot-vehicle
## are each tested in their own repository and each of them passes there; what has never run
## before this game is the joins — and [ScPlatforms] has never run anywhere, because nothing
## in the family models a floor that tips. So the sections are named after behaviours a
## player would describe rather than after classes.
##
## [b]It steps the world by hand.[/b] `ScGame._physics_process` drives itself on a server; a
## suite that let it would be asserting against a tick count it does not control, so
## `set_physics_process(false)` goes on first and every section advances the world itself.

## Sections entered, against sections that ran to their last line.
const SECTIONS := 23

## And the total this counter cannot be.
##
## [b]A runtime error inside a section aborts that FUNCTION and nothing says so.[/b] The
## checks that already ran still print ok, the ones after it never happen, and the section
## counter is satisfied because the section announced itself on the way in. dot-settings
## reported "8 sections, 63 passed, 0 failed" and exited 0 with eight checks missing.
const CHECKS := 149

const TICK_RATE := 64
const TICK := 1.0 / float(TICK_RATE)

var _passed := 0
var _failed := 0
var _sections_entered := 0
var _sections_finished := 0
var _failures := PackedStringArray()

## Every world this run has built and not yet taken down.
var _worlds: Array[ScGame] = []


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("smash-copter headless run")
	print("")

	_test_config()
	_test_delivery()
	_test_layouts()
	await _test_world_builds()
	await _test_a_platform_leans()
	await _test_walking_is_gentler()
	await _test_a_platform_collapses()
	await _test_the_carry()
	await _test_the_cannon()
	await _test_an_impact()
	await _test_falling_off()
	await _test_the_round()
	await _test_sides_agree()
	await _test_specials()
	await _test_a_shot_lands()
	await _test_the_chopper()
	await _test_reach()
	await _test_the_throat()
	await _test_the_showdown_walk()
	await _test_the_zigzag()
	await _test_the_spine()
	await _test_a_slope_holds()
	await _test_blind_and_beacon_drawn()

	for world in _worlds.duplicate():
		await _dispose(world)

	await get_tree().process_frame

	print("")
	print("%d sections entered, %d finished" % [_sections_entered, _sections_finished])
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	var code := 1 if _failed > 0 else 0

	if _sections_entered != _sections_finished or _sections_entered != SECTIONS:
		print("ERROR: %d of %d sections finished, %d expected." % [
			_sections_finished, _sections_entered, SECTIONS
		])
		code = 1

	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		code = 1

	get_tree().quit(code)


# --- Sections ---------------------------------------------------------------

func _test_config() -> void:
	_section("the configuration refuses what it cannot play")

	var config := ScConfig.new()
	_check(config.validate().ok, "the defaults are playable")

	# Armed: each of these is a real contradiction the game cannot run, and every one of
	# them used to be checked nowhere.
	var teams := ScConfig.new()
	teams.team_count = 9
	_check(not teams.validate().ok, "nine sides is refused")

	var overlapping := ScConfig.new()
	overlapping.column_pitch = overlapping.platform_size - 1.0
	_check(not overlapping.validate().ok, "platforms that would overlap are refused")

	var plinth := ScConfig.new()
	plinth.pillar_radius = plinth.platform_size * 0.5
	_check(not plinth.validate().ok, "a pillar as wide as its platform is refused")

	var weightless := ScConfig.new()
	weightless.cannon_tier_weights = PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	_check(not weightless.validate().ok, "a cannon that could never choose anything is refused")

	var sinking := ScConfig.new()
	sinking.chopper_lift = 1.0
	_check(not sinking.validate().ok, "a chopper that cannot leave the pad is refused")

	var short := ScConfig.new()
	short.cannon_tier_unlock = PackedFloat32Array([0.0, 1.0])
	_check(not short.validate().ok, "a tier table with the wrong number of entries is refused")

	_check(
		is_equal_approx(
			config.round_seconds(),
			config.survival_seconds + config.showdown_warmup_seconds + config.showdown_seconds
		),
		"a round is both halves and the pause between them"
	)

	_finished()


func _test_layouts() -> void:
	_section("every layout describes a field somebody could play on")

	var config := ScConfig.new()
	var layouts := ScLayouts.all(config)

	_check(layouts.size() >= 6, "there are several layouts", "%d" % layouts.size())

	var ids: Dictionary = {}
	var all_have_platforms := true
	var all_bridges_land := true

	for layout in layouts:
		ids[layout.id] = true
		var cells := layout.cells(config)
		var platforms: Dictionary = {}
		var bridges: Array[Vector3i] = []

		for cell: Vector3i in cells:
			if cell.z == 1:
				bridges.append(cell)
			else:
				platforms["%d,%d" % [cell.x, cell.y]] = true

		if platforms.is_empty():
			all_have_platforms = false

		# [b]A bridge with nothing at either end of it is a diving board.[/b] The layout
		# refuses to place one, and this is what says so — it is the only rule in that file
		# whose absence would be invisible until somebody walked off the end.
		for bridge in bridges:
			if not platforms.has("%d,%d" % [bridge.x, bridge.y]):
				all_bridges_land = false

			if not platforms.has("%d,%d" % [bridge.x, bridge.y + 1]):
				all_bridges_land = false

	_check(all_have_platforms, "no layout is empty")
	_check(all_bridges_land, "every bridge has a platform at both ends")
	_check(ids.size() == layouts.size(), "no two layouts share an id")

	# Seeded, so two servers lay out the same round. The whole reason a seed exists.
	var one := DotRandomStream.new(4242, &"layout")
	var two := DotRandomStream.new(4242, &"layout")
	var picks_agree := true

	for _i in range(24):
		if ScLayouts.pick(config, one).id != ScLayouts.pick(config, two).id:
			picks_agree = false

	_check(picks_agree, "two streams on one seed pick the same layouts")

	_finished()


func _test_world_builds() -> void:
	_section("the world comes up")

	var game := await _world()

	_check(game.platforms != null and game.platforms.count() > 0,
		"there are platforms", "%d" % game.platforms.count())
	_check(game.arena != null, "there is an arena")
	_check(game.cannon != null, "there is a cannon")
	_check(game.physics != null, "the collision layout built")

	# [b]Applied, not merely assigned.[/b] Five games in this family set a layout and put it
	# on no bodies at all; everything stayed on layer one masking layer one. A platform whose
	# layer is still the default is exactly that bug.
	var deck := game.platforms.deck_at(0)
	var world_layer := game.physics.layer_mask(&"world")
	_check(deck.body.collision_layer == world_layer,
		"a platform is on the world layer", "%d vs %d" % [deck.body.collision_layer, world_layer])

	# Every platform except a bridge stands on its own pillar, which is the entire premise.
	var pillars := 0
	var bridges := 0

	for i in range(game.platforms.count()):
		var each := game.platforms.deck_at(i)

		if each.is_bridge:
			bridges += 1
		elif each.pillar != null:
			pillars += 1

	_check(pillars + bridges == game.platforms.count(),
		"every platform is on a pillar or is a bridge", "%d + %d" % [pillars, bridges])

	# The muzzle clears the tube it comes out of. A body spawned inside a collider is two
	# shapes sharing a volume, which the solver resolves by throwing one of them sideways.
	_check(game.arena.muzzle().y > game.config.deck_height * 0.8,
		"the muzzle is above the tube", "%.1f m" % game.arena.muzzle().y)

	_check(game.platforms.index_at(deck.centre.x, deck.centre.z) == 0,
		"a point over a platform finds it")
	_check(game.platforms.index_at(9000.0, 9000.0) == -1,
		"a point over nothing finds nothing")

	# [b]The showdown's edges, which were designed, documented twice and built nowhere.[/b]
	# `_pad` was described as "one flat surface with a kerb around it", `CORNER_LIP` had a
	# doc comment explaining why the lip is not cover, and no line put one in the world. A
	# render found it; nothing here could have, so this is the check that keeps it.
	#
	# Counted rather than measured: a pad is four kerbs and a catwalk is two, because a kerb
	# across a catwalk's short end is a step in the middle of the walkway rather than a rail
	# beside it.
	#
	# Counted by SIDE rather than by piece, because a side a catwalk joins is two pieces
	# with the catwalk between them. Whether that gap is really there is not something a
	# count can say — the showdown walk below is what says it.
	var pads := 0
	var walks := 0
	var thin := PackedStringArray()

	for child: Node in game.arena.find_children("*", "StaticBody3D", true, false):
		var sides: Dictionary = {}

		for piece: Node in child.get_children():
			var piece_name := String(piece.name)

			if piece_name.begins_with("KerbHit"):
				sides[piece_name.trim_prefix("KerbHit").get_slice("_", 0)] = true

		var kerbs := sides.size()

		if String(child.name).begins_with("Catwalk"):
			walks += 1

			if kerbs != 2:
				thin.append("%s has %d" % [child.name, kerbs])
		elif String(child.name).begins_with("Pad") or child.name == "Ring":
			pads += 1

			if kerbs != 4:
				thin.append("%s has %d" % [child.name, kerbs])

	_check(pads == game.config.team_count + 1,
		"every corner and the ring is a pad", "%d pads" % pads)
	_check(walks == game.config.team_count,
		"and every corner has a catwalk to the ring", "%d walks" % walks)
	_check(thin.is_empty(),
		"a pad is edged on four sides and a catwalk on two",
		", ".join(thin))

	await _dispose(game)
	_finished()


func _test_a_platform_leans() -> void:
	_section("a platform leans toward whoever is standing on it")

	var game := await _world()
	var platforms := game.platforms
	var deck := platforms.deck_at(0)

	_check(is_zero_approx(deck.tilt()), "it starts level")

	# Eighty kilograms on the +X edge, standing still.
	var at := deck.centre + Vector3(deck.half * 0.8, 0.0, 0.0)

	for _i in range(40):
		platforms.begin_loads()
		platforms.add_load(0, at, 80.0, 0.0)
		platforms.step(TICK)

	_check(deck.lean.x > 0.0, "it leaned toward the load", "%.4f rad" % deck.lean.x)
	_check(is_zero_approx(deck.lean.y) or absf(deck.lean.y) < 0.0001,
		"and not sideways", "%.5f" % deck.lean.y)

	# The surface actually moved under that point, which is the thing a player feels.
	var under := platforms.surface_y(0, at.x, at.z)
	_check(under < deck.centre.y, "the surface under the load is lower than the pivot",
		"%.3f vs %.3f" % [under, deck.centre.y])

	var high := platforms.surface_y(0, deck.centre.x - deck.half * 0.8, deck.centre.z)
	_check(high > under, "and the far side is higher", "%.3f vs %.3f" % [high, under])

	# Let go, and it comes back. A spring that did not would be a ramp.
	var leaned := deck.lean.x

	for _i in range(240):
		platforms.begin_loads()
		platforms.step(TICK)

	_check(absf(deck.lean.x) < leaned * 0.5, "it settles back when the load goes",
		"%.4f from %.4f" % [deck.lean.x, leaned])
	_check(deck.is_standing(), "and it is still standing")

	await _dispose(game)
	_finished()


func _test_walking_is_gentler() -> void:
	_section("walking leans a platform less than running does")

	var game := await _world()
	var platforms := game.platforms
	var config := game.config

	var walking := platforms.deck_at(0)
	var running := platforms.deck_at(1)
	var at_walk := walking.centre + Vector3(walking.half * 0.7, 0.0, 0.0)
	var at_run := running.centre + Vector3(running.half * 0.7, 0.0, 0.0)

	for _i in range(60):
		platforms.begin_loads()
		platforms.add_load(0, at_walk, config.player_mass, config.run_speed * config.walk_speed_scale)
		platforms.add_load(1, at_run, config.player_mass, config.run_speed)
		platforms.step(TICK)

	_check(running.lean.x > walking.lean.x,
		"the running player leaned theirs further",
		"run %.4f vs walk %.4f" % [running.lean.x, walking.lean.x])

	# [b]Armed.[/b] With `platform_motion_gain` at zero the two are identical, which is what
	# this check exists to notice: a gain that was read by nothing would pass every other
	# assertion in this file.
	_check(running.lean.x > walking.lean.x * 1.2,
		"and by a margin a player could feel",
		"%.2fx" % (running.lean.x / maxf(walking.lean.x, 0.00001)))

	await _dispose(game)
	_finished()


func _test_a_platform_collapses() -> void:
	_section("a platform comes off its pillar")

	var game := await _world()
	var platforms := game.platforms
	var config := game.config

	var fell: Array[int] = []
	platforms.collapsed.connect(func(index: int, _why: StringName) -> void: fell.append(index))

	var deck := platforms.deck_at(0)
	var at := deck.centre + Vector3(deck.half, 0.0, 0.0)

	# A crowd on one edge. Enough to go over, given long enough.
	for _i in range(600):
		if not deck.is_standing():
			break

		platforms.begin_loads()
		platforms.add_load(0, at, 800.0, config.run_speed)
		platforms.step(TICK)

	_check(not deck.is_standing(), "enough weight on one edge takes it over",
		"%.3f rad" % deck.tilt())
	# An Array rather than a captured counter: a GDScript lambda captures locals BY VALUE, so
	# an `int` incremented in the handler stays zero outside it and the check reports a
	# failure for a signal that fired perfectly.
	_check(fell.has(0), "and it said so")

	# The collider goes NOW, not when the slab has finished falling. A player left riding it
	# would be carried forty metres by a floor that is gone from every other point of view.
	var collider := deck.body.get_node_or_null(^"Collision") as CollisionShape3D
	_check(collider != null and collider.disabled, "the floor is taken away at once")
	_check(platforms.index_of_body(deck.body.get_instance_id()) == -1,
		"and nothing can be standing on it")

	# A single big enough impact is the other way, and it does not care about health.
	var second := platforms.deck_at(1)
	var outcome := platforms.report_impact(
		1, config.platform_shatter_impulse * 2.0, 1.0, second.centre + Vector3(1.0, 0.0, 0.0)
	)
	_check(outcome == ScPlatforms.Impact.SHATTERED, "one big enough hit shatters a platform")
	_check(not second.is_standing(), "which takes it off its pillar in the same tick")

	# And a small one does not.
	var third := platforms.deck_at(2)
	var gentle := platforms.report_impact(2, 30.0, 6.0, third.centre + Vector3(1.0, 0.0, 0.0))
	_check(gentle == ScPlatforms.Impact.WOBBLE, "a crate landing only wobbles it")
	_check(third.is_standing(), "and leaves it standing")
	_check(third.lean_velocity.length() > 0.0, "though it is moving now",
		"%.4f rad/s" % third.lean_velocity.length())

	await _dispose(game)
	_finished()


func _test_the_carry() -> void:
	_section("a leaning platform carries what is standing on it")

	var game := await _world()
	var platforms := game.platforms
	var deck := platforms.deck_at(0)
	var at := deck.centre + Vector3(deck.half * 0.7, 0.0, 0.0)

	# Lean it, then measure what the surface did under one fixed point in one step.
	for _i in range(30):
		platforms.begin_loads()
		platforms.add_load(0, at, 400.0, 0.0)
		platforms.step(TICK)

	var before := platforms.surface_y(0, at.x, at.z)

	platforms.begin_loads()
	platforms.add_load(0, at, 400.0, 0.0)
	platforms.step(TICK)

	var after := platforms.surface_y(0, at.x, at.z)
	var lift := platforms.lift_at(0, at.x, at.z)

	_check(not is_zero_approx(lift), "the surface moved", "%.5f m" % lift)
	_check(is_equal_approx(lift, after - before),
		"and the lift is exactly how far it moved", "%.6f vs %.6f" % [lift, after - before])

	# [b]The same offset on both sides of the subtraction is the whole trick.[/b] What is
	# wanted is what the PLATFORM did; a lift measured against where the player was last tick
	# would fold their own walking in and carry them twice.
	var far_out := platforms.lift_at(0, deck.centre.x - deck.half * 0.7, deck.centre.z)
	_check(signf(far_out) != signf(lift) or is_zero_approx(far_out),
		"the far side went the other way", "%.5f vs %.5f" % [far_out, lift])

	# A point over nothing is not carried by anything.
	_check(is_zero_approx(platforms.lift_at(-1, 0.0, 0.0)), "nothing carries a point over nothing")

	await _dispose(game)
	_finished()


func _test_the_cannon() -> void:
	_section("the cannon aims")

	var game := await _world()
	var cannon := game.cannon
	var plain := ScSpecials.Active.new()

	var sent := cannon.fire(0.0, plain)
	_check(sent > 0, "it fires", "%d props" % sent)
	_check(game.props.world_count() > 0, "and the props are in the world")

	# Everything in the first seconds is tier one: the unlock table is what makes the opening
	# of a round survivable, and a tier that arrived early would be invisible to any check
	# that only counted props.
	var early_tiers_ok := true

	for prop in game.props.all_props():
		if ScContent.tier_of(prop.def) != 1:
			early_tiers_ok = false

	_check(early_tiers_ok, "and all of them are the small ones at zero seconds")

	# The arc is solved rather than tuned. This is the check that says so: a body launched at
	# a target reaches it, within the scatter it was given.
	var target := Vector3(18.0, game.config.deck_height, 6.0)
	var from := game.arena.muzzle()
	var velocity := ScCannon.solve_arc(from, target, 25.0, game.config.gravity)

	_check(velocity.y > 0.0, "a solved arc goes up first", "%.1f m/s" % velocity.y)

	# Integrate it by hand, which is the only honest way to check a ballistic solution.
	var where := from
	var moving := velocity
	var closest := INF

	for _i in range(600):
		moving.y -= game.config.gravity * TICK
		where += moving * TICK
		closest = minf(closest, Vector2(where.x - target.x, where.z - target.z).length())

		if where.y < target.y and moving.y < 0.0:
			break

	_check(closest < 2.0, "and it lands on what it was aimed at", "%.2f m away" % closest)
	_check(where.y <= target.y + 1.0, "at about the right height", "%.1f m" % where.y)

	# The rate closes as the round goes on, which is what makes the last thirty seconds
	# different from the first thirty.
	var opening := cannon.interval_at(0.0, plain)
	var closing := cannon.interval_at(game.config.survival_seconds, plain)
	_check(closing < opening, "it speeds up over a round", "%.2f s to %.2f s" % [opening, closing])

	var early_volley := cannon.volley_at(0.0, plain)
	var late_volley := cannon.volley_at(game.config.survival_seconds, plain)
	_check(late_volley > early_volley, "and throws more at once",
		"%d to %d" % [early_volley, late_volley])

	# A prop is on a clock from the moment it leaves, or the map is a scrapyard by the end.
	#
	# [b]Named rather than counted, because advancing the cannon also FIRES it.[/b] A check
	# on `world_count()` measures the old props leaving and the new ones arriving at once,
	# and passes or fails on which of the two happened to win.
	var was_up: Array[int] = []

	for prop in game.props.all_props():
		was_up.append(prop.instance_id)

	cannon.advance(game.config.prop_life_seconds + 1.0, 0.0, plain)

	var survivors := 0

	for prop in game.props.all_props():
		if was_up.has(prop.instance_id):
			survivors += 1

	_check(was_up.size() > 0 and survivors == 0, "and takes its props back eventually",
		"%d of %d left" % [survivors, was_up.size()])

	await _dispose(game)
	_finished()


func _test_an_impact() -> void:
	_section("something landing leans the platform it landed on")

	var game := await _world()
	var platforms := game.platforms
	var deck := platforms.deck_at(0)

	var struck: Array[int] = []
	platforms.struck.connect(
		func(index: int, _at: Vector3, _impulse: float, _outcome: int) -> void:
			struck.append(index)
	)

	var at := deck.centre + Vector3(deck.half * 0.6, 0.0, 0.0)
	var outcome := platforms.report_impact(0, 110.0, 14.0, at)

	_check(outcome == ScPlatforms.Impact.WOBBLE, "a boulder wobbles it")
	_check(struck.has(0), "and it said so")
	_check(deck.lean_velocity.x > 0.0, "it was pushed toward where it landed",
		"%.4f rad/s" % deck.lean_velocity.x)
	_check(deck.sink_velocity < 0.0, "and pressed down", "%.4f m/s" % deck.sink_velocity)
	_check(deck.health < 1.0, "and it took damage", "%.3f left" % deck.health)

	# [b]Dead centre is the one case with no lever arm, and it still has to do
	# something.[/b] A monolith dropped exactly on the pillar would otherwise be absorbed by
	# a platform that cannot tell it happened.
	var centred := platforms.deck_at(1)
	var _hit := platforms.report_impact(1, 110.0, 14.0, centred.centre)
	_check(centred.lean_velocity.length() > 0.0, "a hit dead on the pillar still leans it",
		"%.4f rad/s" % centred.lean_velocity.length())

	# Impacts add up. A platform that has been hit twice is one more hit from gone.
	var health_after_one := deck.health
	var _again := platforms.report_impact(0, 110.0, 14.0, at)
	_check(deck.health < health_after_one, "two hits are worse than one",
		"%.3f then %.3f" % [health_after_one, deck.health])

	# And nothing at all happens to a platform that has already gone.
	var _gone := platforms.collapse(2)
	var missed := platforms.report_impact(2, 900.0, 40.0, platforms.deck_at(2).centre)
	_check(missed == ScPlatforms.Impact.NONE, "a platform that has gone cannot be hit again")

	await _dispose(game)
	_finished()


func _test_sides_agree() -> void:
	_section("dot-match puts everybody where the game did")

	var game := await _world()

	# The offline client's own line-up: every stand-in on team 2 before anybody is on 1.
	# dot-match's default refuses a join that puts a side two ahead, and its elimination
	# rule counts survivors off its own teams — so a refused stand-in is one it never sees.
	for i in range(3):
		game.add_player(StringName("bot%d" % i), "Stand-in", 2)
	game.add_player(&"local", "You", 1)

	var disagree: Array[String] = []
	for id: StringName in game.players:
		if game.match_node.teams.team_of(String(id)) != game.team_of(id):
			disagree.append(String(id))

	_check(disagree.is_empty(), "every stand-in is on a side dot-match can count",
		"it disagrees about %s" % ", ".join(disagree))

	await _dispose(game)
	_finished()


func _test_falling_off() -> void:
	_section("running out of map is fatal")

	var game := await _world()

	var player := game.add_player(&"faller", "Faller", 1)
	game.add_player(&"other", "Other", 2)

	var deaths: Array[StringName] = []
	game.player_died.connect(
		func(id: StringName, _by: StringName, why: StringName) -> void:
			deaths.append(why)
	)

	_check(player.is_alive(), "they start up")
	_check(player.entity_id != 0, "with an entity id")
	_check(DotEntity.is_kind(player.entity_id, DotEntity.KIND_PLAYER),
		"and the id says what kind of thing they are")

	# Put them under the floor and step once. A height comparison cannot be stepped over,
	# which is the whole reason this is not a trigger volume: at terminal velocity a falling
	# body crosses a thin trigger between two ticks without ever being inside it.
	player.place_at(Vector3(0.0, game.config.kill_height - 5.0, 0.0), 0.0)
	game.simulate(TICK)

	_check(not player.is_alive(), "below the floor is dead")
	_check(deaths.has(ScGame.DIED_FELL), "and it is recorded as a fall",
		", ".join(Array(deaths).map(func(v: Variant) -> String: return String(v))))

	# [b]dot-combat keeps a health record per entity and nothing else tells it to let
	# go.[/b] game-buses-from-hell leaked one per player who ever joined, pointing at a node
	# freed with them — invisible, because a stale entity is never asked about.
	var id := player.entity_id
	_check(game.combat.health_of(id) != null, "the combat manager knows them")
	game.remove_player(&"faller")
	_check(game.combat.health_of(id) == null, "and forgets them when they leave")
	_check(game.entities.key_for_id(id) == &"", "the entity table closes them too")

	await _dispose(game)
	_finished()


func _test_the_round() -> void:
	_section("a round is two games with a teleport in the middle")

	var game := await _world(func(c: ScConfig) -> void:
		c.survival_seconds = 4.0
		c.showdown_warmup_seconds = 1.0
		c.showdown_seconds = 20.0
		c.warmup_seconds = 0.0
		c.cannon_enabled = false
		c.clear_platforms_for_showdown = false
	)

	game.add_player(&"a", "A", 1)
	game.add_player(&"b", "B", 2)
	game.start()

	await _step(game, 4)
	_check(game.phase == ScGame.Phase.SURVIVAL, "it starts on the platforms",
		ScGame.Phase.keys()[game.phase])

	var somewhere: Vector3 = (game.players[&"a"] as ScPlayer).controller.state.position
	_check(somewhere.y > game.config.deck_height * 0.5, "with everybody up in the air",
		"%.1f m" % somewhere.y)

	# Past the survival clock.
	await _step(game, int(4.2 * TICK_RATE))
	_check(game.phase == ScGame.Phase.HANDOVER, "the clock sends them to the corners",
		ScGame.Phase.keys()[game.phase])

	var corner: ScPlayer = game.players[&"a"]
	var expected := game.arena.corner_point(0, game.config.team_count)
	var moved := Vector2(
		corner.controller.state.position.x - expected.x,
		corner.controller.state.position.z - expected.z
	).length()

	_check(moved < game.config.corner_size, "they are actually in their corner",
		"%.1f m from the middle of it" % moved)
	_check(corner.weapons != null, "and they are holding something")
	_check(corner.health.invulnerable, "and cannot be shot yet")

	# [b]Facing inward, and a teleport that gets the position right and the yaw wrong is
	# invisible to every count and obvious to every player.[/b] The corner is on +X for team
	# one, so facing the middle is facing -X, which in this motor's frame is a yaw of -90.
	var facing := Basis.from_euler(Vector3(0.0, deg_to_rad(corner.controller.state.yaw), 0.0))
	var middle := game.arena.showdown_centre()
	var toward_middle := Vector3(
		middle.x - expected.x, 0.0, middle.z - expected.z
	).normalized()
	_check((-facing.z).dot(toward_middle) > 0.7, "looking at the middle",
		"%.2f" % (-facing.z).dot(toward_middle))

	await _step(game, int(1.2 * TICK_RATE))
	_check(game.phase == ScGame.Phase.SHOWDOWN, "and then the weapons go hot",
		ScGame.Phase.keys()[game.phase])
	_check(not corner.health.invulnerable, "with nobody protected any more")

	# The round ends when a side has nobody left, which is dot-match's elimination rule
	# reading this game's own `alive_fn`. Unwired it falls back to a clock, and the tell is
	# visible in the first round played.
	var ended: Array[int] = []
	game.round_over.connect(func(_number: int, winner: int) -> void: ended.append(winner))

	game.players[&"b"].health.health = 0.0
	game.players[&"b"].health.alive = false

	await _step(game, 8)

	_check(not ended.is_empty(), "the round ends when a side is wiped out")
	_check(ended.is_empty() or ended[0] == 1, "and the other side won",
		"winner=%d" % (ended[0] if not ended.is_empty() else -1))

	await _dispose(game)
	_finished()


func _test_specials() -> void:
	_section("specials multiply and stack")

	var plain := ScSpecials.Active.new()
	_check(plain.is_plain(), "nothing in force is nothing in force")
	_check(is_equal_approx(plain.gravity_scale, 1.0), "and multiplies nothing")

	var feather := ScSpecials.by_id(&"feather")
	var barrage := ScSpecials.by_id(&"barrage")
	_check(feather != null and barrage != null, "the catalogue has the ones it says it has")

	var both := ScSpecials.Active.new()
	both.fold(feather)
	both.fold(barrage)

	_check(both.ids.size() == 2, "two at once is two at once")
	_check(both.gravity_scale < 1.0, "low gravity is still low gravity",
		"%.2f" % both.gravity_scale)
	_check(both.cannon_interval_scale < 0.5, "and the barrage is still a barrage",
		"%.2f" % both.cannon_interval_scale)

	# An allow-list of ids that names nothing is an operator's typo, and a server whose
	# specials silently never happen is worse than one that ignores the setting.
	var mistyped := ScConfig.new()
	mistyped.special_ids = PackedStringArray(["not_a_special"])
	_check(ScSpecials.available(mistyped).size() == ScSpecials.all().size(),
		"a special list naming nothing falls back to everything")

	var narrowed := ScConfig.new()
	narrowed.special_ids = PackedStringArray(["feather", "slick"])
	_check(ScSpecials.available(narrowed).size() == 2, "and a real list narrows it")

	# It reaches the world: low gravity is one call on the physics space and one on every
	# player's tunables, and a special that changed neither would be a document nothing reads.
	var game := await _world(func(c: ScConfig) -> void:
		c.specials_enabled = false
	)
	var player := game.add_player(&"light", "Light", 1)
	var before := player.controller.tunables.gravity

	player.retune(both)
	_check(player.controller.tunables.gravity < before, "a player's own gravity comes down",
		"%.1f from %.1f" % [player.controller.tunables.gravity, before])
	_check(player.controller.tunables.max_speed > 0.0, "and they can still move")

	await _dispose(game)
	_finished()


## [b]The half of this game that is a gunfight, asserted for the first time.[/b]
##
## Everything else here checks that a weapon EXISTS: that a survivor is holding one, that
## the fire counter goes up, that hitboxes are registered, that a health record is kept. The
## round test kills its loser by assigning `health = 0.0`. So every check in this repository
## passed on a showdown in which no shot had ever reduced anybody's health, and there was no
## way to tell from the inside.
##
## What made it visible was running bots against each other for twenty rounds: every round
## ended with exactly two alive and a draw, which is one survivor per side, every time. A
## number that is the same every round is a number nothing is deciding.
##
## So this is the whole chain in one check — a command's button, the arsenal's tick, the
## shot it emits, the trace against the world, the hitbox it finds, the damage rules, and
## the health record — and it is the only check here that fails if any link in it breaks.
func _test_a_shot_lands() -> void:
	_section("a shot finds a player")

	var game := await _world(func(c: ScConfig) -> void:
		c.survival_seconds = 2.0
		c.showdown_warmup_seconds = 0.5
		c.showdown_seconds = 60.0
		c.warmup_seconds = 0.0
		c.cannon_enabled = false
	)

	var shooter := game.add_player(&"shooter", "Shooter", 1)
	var target := game.add_player(&"target", "Target", 2)
	game.start()

	await _step(game, int(3.0 * TICK_RATE))

	var hot := game.phase == ScGame.Phase.SHOWDOWN
	_check(hot, "the showdown is running", ScGame.Phase.keys()[game.phase])

	if not hot:
		# Deliberately NOT returning early: a section that stops adding checks is a section
		# the CHECKS total reports as a hole rather than as a failure, and a hole reads like
		# somebody edited the file. Everything below fails honestly instead.
		pass

	_check(shooter.weapons != null and target.weapons != null, "both are armed")
	_check(not target.health.invulnerable, "and the target can be hurt")

	# Face to face at eight metres, on the shooter's own pad, so the trace has the pad under
	# it and nothing else between them. Placed rather than walked: this check is about the
	# shot, and a bot that fell off on the way would fail it for the wrong reason.
	var stand := shooter.controller.state.position
	var toward := game.arena.showdown_centre() - stand
	toward.y = 0.0
	toward = toward.normalized()

	shooter.place_at(stand, rad_to_deg(atan2(-toward.x, -toward.z)))
	target.place_at(stand + toward * 8.0, rad_to_deg(atan2(toward.x, toward.z)))

	await _step(game, 4)

	var before := target.health.health
	_check(before > 0.0, "the target starts alive", "%.0f hp" % before)

	# Aimed at the chest rather than along the floor: a trace from an eye to a point eight
	# metres away at the same height passes through a standing capsule, and one aimed at the
	# feet does not.
	var eye := shooter.eye_position()
	var at := target.eye_position()
	var line := (at - eye).normalized()

	var fired := 0

	for _i in range(int(1.5 * TICK_RATE)):
		var command := DotFpsCommand.new()
		command.yaw = rad_to_deg(atan2(-line.x, -line.z))
		command.pitch = clampf(rad_to_deg(asin(clampf(line.y, -1.0, 1.0))), -89.0, 89.0)
		command.set_button(DotFpsCommand.BUTTON_USER_0, true)
		shooter.controller.apply_command(command)

		fired = maxi(fired, shooter.weapons.fire_seq)
		game.simulate(TICK)
		await _physics_frame()

		if target.health.health < before:
			break

	_check(shooter.weapons.fire_seq > 0, "the weapon fires",
		"%d uses" % shooter.weapons.fire_seq)
	_check(
		target.health.health < before,
		"and the target takes damage",
		"%.0f -> %.0f hp after %d uses"
			% [before, target.health.health, shooter.weapons.fire_seq]
	)

	# [b]The other half of the rule, and the one a game gets wrong quietly.[/b] Friendly fire
	# is off, so a shot down the same line at a team mate has to find nothing to do. A game
	# that resolved it anyway would play correctly right up until two people on one side
	# stood in front of each other.
	var mate := game.add_player(&"mate", "Mate", 1)
	mate.place_at(stand + toward * 8.0, rad_to_deg(atan2(toward.x, toward.z)))
	target.place_at(stand + toward * 40.0, rad_to_deg(atan2(toward.x, toward.z)))

	await _step(game, 4)

	var mate_before := mate.health.health

	for _i in range(int(1.0 * TICK_RATE)):
		var command := DotFpsCommand.new()
		command.yaw = rad_to_deg(atan2(-line.x, -line.z))
		command.pitch = 0.0
		command.set_button(DotFpsCommand.BUTTON_USER_0, true)
		shooter.controller.apply_command(command)
		game.simulate(TICK)
		await _physics_frame()

	_check(
		is_equal_approx(mate.health.health, mate_before),
		"a team mate in the way takes none",
		"%.0f -> %.0f hp" % [mate_before, mate.health.health]
	)

	await _dispose(game)
	_finished()


func _test_the_chopper() -> void:
	_section("the chopper flies")

	var game := await _world(func(c: ScConfig) -> void:
		c.cannon_enabled = false
		c.chopper_enabled = true
	)

	var copter := game.vehicles.spawn(
		ScContent.COPTER,
		Vector3(0.0, game.config.deck_height + 8.0, 0.0),
		ScContent.WORLD_OWNER
	)

	_check(copter != null, "it spawns")

	if copter == null:
		# Three checks that cannot run without one. Counted anyway, because a section that
		# quietly runs fewer checks than it says is the thing the CHECKS total exists for.
		_check(false, "it has a chassis")
		_check(false, "it climbs on full collective")
		_check(false, "and holds height at neutral")
		_check(false, "and will not climb past its ceiling")
		_check(false, "a pilot who puts it down on the floor has fallen")
		_check(false, "and it is recorded as a fall")
		await _dispose(game)
		_finished()
		return

	var chassis := copter.chassis as ScCopter
	_check(chassis != null, "it has a chassis")

	chassis.lift_ratio = game.config.chopper_lift
	chassis.gravity = game.config.gravity
	copter.meta[ScCopter.META_CEILING] = game.config.deck_height + game.config.chopper_ceiling

	var body := copter.body()
	var started_at := body.global_position.y

	# Full collective for two seconds. A helicopter that cannot climb is one nobody can tell
	# from a broken one.
	var climb := DotVehicleCommand.new()
	climb.throttle = 1.0

	for _i in range(int(2.0 * TICK_RATE)):
		chassis.drive(climb, TICK)
		await _physics_frame()

	_check(body.global_position.y > started_at + 1.0, "it climbs on full collective",
		"%.1f m from %.1f m" % [body.global_position.y, started_at])

	# And it holds itself up at neutral, which is what makes the control readable: a machine
	# whose neutral is a slow sink is one a player is fighting the whole time.
	#
	# [b]From rest, because neutral does not arrest a climb and should not.[/b] A helicopter
	# at neutral collective is holding its weight, not braking — so a pilot who lets go at
	# eighteen metres a second keeps going up, which is what the ceiling is for. Measuring
	# that as "drift" would be asserting that the machine has air brakes.
	body.linear_velocity = Vector3.ZERO
	var hovering := body.global_position.y
	var hover := DotVehicleCommand.new()

	for _i in range(int(1.0 * TICK_RATE)):
		chassis.drive(hover, TICK)
		await _physics_frame()

	_check(absf(body.global_position.y - hovering) < 2.5, "and holds height at neutral",
		"%.2f m of drift" % (body.global_position.y - hovering))

	# The ceiling holds rather than shoves. One that pushed back would throw a pilot who
	# touched it through the map.
	body.global_position = Vector3(0.0, float(copter.meta[ScCopter.META_CEILING]) + 3.0, 0.0)
	body.linear_velocity = Vector3.ZERO

	for _i in range(int(1.5 * TICK_RATE)):
		chassis.drive(climb, TICK)
		await _physics_frame()

	_check(body.linear_velocity.y <= 0.5, "and will not climb past its ceiling",
		"%.2f m/s" % body.linear_velocity.y)

	# [b]The floor is the one thing nobody survives, and a seat used to be the exception.[/b]
	# A rider was skipped by the fall check because their own position stops moving while
	# they are carried — so a pilot could park on the floor out of the cannon's reach, or fly
	# off the edge of the map and fall for the rest of the round, and be handed a weapon in
	# the corners either way. Measured by the machine now, parked where it would really rest.
	var pilot := game.add_player(&"pilot", "Pilot", 1)
	game.add_player(&"other", "Other", 2)

	var deaths: Array[StringName] = []
	game.player_died.connect(
		func(id: StringName, _by: StringName, why: StringName) -> void:
			if id == &"pilot":
				deaths.append(why)
	)

	body.global_position = Vector3(0.0, game.config.deck_height, game.arena._field_reach() + 10.0)
	body.linear_velocity = Vector3.ZERO
	pilot.place_at(body.global_position + Vector3(1.0, 0.0, 0.0), 0.0)
	var boarded := game.try_board(&"pilot")

	body.global_position.y = game.config.kill_height + 0.9

	for _i in range(4):
		game.simulate(TICK)
		await _physics_frame()

	_check(boarded.ok and not pilot.is_alive() and not pilot.riding,
		"a pilot who puts it down on the floor has fallen",
		"boarded %s, alive %s, riding %s" % [boarded.ok, pilot.is_alive(), pilot.riding])
	_check(deaths.has(ScGame.DIED_FELL), "and it is recorded as a fall",
		", ".join(Array(deaths).map(func(v: Variant) -> String: return String(v))))

	await _dispose(game)
	_finished()


## [b]The one thing neither the suite nor the editor can see: what happens once this is a
## pack.[/b] Every finding in this section came from a delivered server rather than from
## here, and each is a check written afterwards so the next one is caught before the boot.
func _test_reach() -> void:
	_section("every jump a layout means is inside a running jump, and no other is")

	var game := await _world(func(c: ScConfig) -> void:
		c.cannon_enabled = false
		c.specials_enabled = false
	)
	var config := game.config
	var platforms := game.platforms

	# [b]The arithmetic first, so a wrong answer below is a wrong map and not wrong sums.[/b]
	# Read off the controller's own tunables: flat, a running jump is the run speed times
	# the whole airtime; above the apex it is no jump at all.
	var t := ScPlayer.tunables_for(config, null)
	var flat := ScPlayer.jump_reach(config, 0.0)
	var airtime := 2.0 * sqrt(2.0 * t.gravity * t.jump_height) / t.gravity
	_check(
		absf(flat - t.max_speed * airtime) < 0.001
			and ScPlayer.jump_reach(config, 0.5) < flat
			and is_zero_approx(ScPlayer.jump_reach(config, t.jump_height + 0.01)),
		"the reach is the movement's own, and shrinks as the landing rises",
		"%.2f m flat, %.2f m onto 0.5 m" % [flat, ScPlayer.jump_reach(config, 0.5)]
	)

	var too_far := PackedStringArray()
	var too_near := PackedStringArray()
	var unmet := PackedStringArray()
	var closest := PackedStringArray()
	var parked := PackedStringArray()

	for layout in ScLayouts.all(config):
		platforms.build(layout, game.physics)
		var cells := platforms.cells()
		var meant := 0
		var tightest := ""
		var tightest_margin := INF

		for pair: Vector3i in ScLayouts.pairs(cells):
			var declared := (layout.jumps & pair.z) != 0

			# Both ways, because the dip is the LAUNCH platform's and two platforms need
			# not lean alike.
			for way: Vector2i in [Vector2i(pair.x, pair.y), Vector2i(pair.y, pair.x)]:
				var air := platforms.clear_air(way.x, way.y)
				var gap := air.y
				var label := "%s %s->%s" % [layout.id, _cell_name(platforms, way.x),
					_cell_name(platforms, way.y)]

				if declared:
					meant += 1
					var dip := _run_up_dip(platforms, config, way.x, way.y, air.x)
					var reach := ScPlayer.jump_reach(config, dip)

					if gap > reach:
						too_far.append("%s %.2f m of air, %.2f m reach off a %.2f m dip" % [
							label, gap, reach, dip])
					elif reach - gap < tightest_margin:
						tightest_margin = reach - gap
						tightest = "%s %.2f m of %.2f" % [label, gap, reach]
				elif gap <= flat:
					# The most generous jump there is: flat, at a run. Anything inside it is
					# a crossing the layout never meant and a player will find.
					too_near.append("%s %.2f m of air, inside %.2f m" % [label, gap, flat])

		if layout.jumps != 0 and meant == 0:
			unmet.append(String(layout.id))

		if tightest != "":
			closest.append(tightest)

		if layout.with_chopper:
			for i in range(config.chopper_count):
				var pad := game.arena.chopper_pad(i, config.chopper_count)

				if platforms.index_at(pad.x, pad.z) < 0:
					parked.append("%s chopper %d" % [layout.id, i])

	_check(too_far.is_empty(), "every jump a layout means can be made from a run",
		"; ".join(too_far) if not too_far.is_empty() else ", ".join(closest))
	_check(too_near.is_empty(), "and every jump it does not mean cannot",
		"; ".join(too_near))
	_check(unmet.is_empty(), "and no layout means a kind of jump it has none of",
		", ".join(unmet))
	# The chopper is parked in the air and comes to rest on whatever is under it; over a
	# gap it comes to rest forty metres down, where nobody can get into it.
	_check(parked.is_empty(), "every parked chopper settles onto a platform",
		", ".join(parked))

	await _dispose(game)
	_finished()


func _test_the_throat() -> void:
	_section("nothing is built over the cannon's mouth, and every shot gets out")

	var game := await _world(func(c: ScConfig) -> void:
		c.specials_enabled = false
	)
	var config := game.config
	var platforms := game.platforms
	var muzzle := game.arena.muzzle()
	var active := ScSpecials.Active.new()

	var crowded := PackedStringArray()
	var margins := PackedStringArray()
	var stuck := PackedStringArray()
	var fired := 0

	for layout in ScLayouts.all(config):
		platforms.build(layout, game.physics)
		await _physics_frame()
		await _physics_frame()

		var clear := platforms.clearance_from(muzzle.x, muzzle.z)
		margins.append("%s %.1f" % [layout.id, clear])

		if clear < ScArena.THROAT_CLEARANCE:
			crowded.append("%s %.2f m" % [layout.id, clear])

		# [b]Fired, not only measured[/b], and with every tier unlocked: at the start of a
		# round the cannon throws crates, and a crate gets through a slot a monolith does
		# not. Eight shots a layout, each watched for half a second.
		var blocked := 0

		for _shot in range(8):
			var prop: DotPropInstance = game.cannon.call("_launch_one", 1000.0, active)

			if prop == null:
				continue

			fired += 1
			var top := -INF

			for _t in range(32):
				game.simulate(TICK)
				await _physics_frame()
				var body := prop.body()

				if body == null or not is_instance_valid(body):
					break

				top = maxf(top, body.global_position.y)

			if top < config.deck_height + 2.0:
				blocked += 1

			var _gone := game.props.remove(prop.instance_id, DotPropSpawner.REASON_CLEANUP)

		if blocked > 0:
			stuck.append("%s %d of 8" % [layout.id, blocked])

	_check(crowded.is_empty(), "no layout builds anything over the cannon's mouth",
		"; ".join(crowded) if not crowded.is_empty() else ", ".join(margins))
	_check(fired == 8 * ScLayouts.all(config).size() and stuck.is_empty(),
		"and every shot on every layout climbs past the decks",
		"%d fired; %s" % [fired, ", ".join(stuck) if not stuck.is_empty() else "none held"])

	await _dispose(game)
	_finished()


## How far below the deck the lip a runner leaves from has gone by the time they reach it.
##
## [b]The platform's own model, stepped the way a run steps it.[/b] A lone runner from the
## middle to the edge at full speed, loading the deck the way [ScGame] loads it, and the
## surface under the edge read at the moment they arrive. That is the rise the jump has to
## make up — at the ordinary numbers about 0.3 m mid-edge and 0.7 m at a corner, which on
## a 1.15 m apex is most of the difference between a jump and a wall.
func _run_up_dip(
	platforms: ScPlatforms, config: ScConfig, from: int, to: int, leave: float
) -> float:
	var deck := platforms.deck_at(from)
	var target := platforms.deck_at(to)
	deck.lean = Vector2.ZERO
	deck.lean_velocity = Vector2.ZERO
	deck.sink = 0.0
	deck.sink_velocity = 0.0

	var heading := Vector3(target.centre.x - deck.centre.x, 0.0, target.centre.z - deck.centre.z)
	heading = heading.normalized()
	var at := deck.centre
	var run := config.run_speed * TICK
	var travelled := 0.0

	while travelled < leave:
		travelled = minf(travelled + run, leave)
		at = deck.centre + heading * travelled
		platforms.begin_loads()
		platforms.add_load(from, at, config.player_mass, config.run_speed)
		platforms.step(TICK)

	var dip := config.deck_height - platforms.surface_y(from, at.x, at.z)

	deck.lean = Vector2.ZERO
	deck.lean_velocity = Vector2.ZERO
	deck.sink = 0.0
	deck.sink_velocity = 0.0

	return maxf(dip, 0.0)


func _cell_name(platforms: ScPlatforms, index: int) -> String:
	var deck := platforms.deck_at(index)
	return "(%d,%d)" % [deck.column, deck.row]


func _test_the_showdown_walk() -> void:
	_section("a survivor can walk from their corner onto the ring")

	# Two sides, where every catwalk meets its edges square on, and three, where two of
	# them meet the ring at an angle and a gap cut along the edge has to be wider.
	for sides: int in [2, 3]:
		var game := await _world(func(c: ScConfig) -> void:
			c.team_count = sides
			c.cannon_enabled = false
			c.specials_enabled = false
		)

		var corner := sides - 1
		var start := game.arena.corner_point(corner, sides)
		var middle := game.arena.showdown_centre()
		var ring := game.config.corner_size * 0.85
		var walker := game.add_player(&"walker", "Walker", 1)
		var yaw := game.arena.showdown_yaw(corner, sides)
		walker.place_at(start + Vector3.UP * 0.2, yaw)

		var arrived := false
		var lowest := INF

		# Running, which is the case the kerb was stopping. Walking is stopped the same way.
		for _i in range(int(8.0 * TICK_RATE)):
			var command := DotFpsCommand.new()
			command.yaw = yaw
			command.move = Vector2(0.0, 1.0)
			walker.controller.apply_command(command)
			game.simulate(TICK)
			await _physics_frame()

			var at := walker.controller.state.position
			lowest = minf(lowest, at.y)

			if Vector2(at.x - middle.x, at.z - middle.z).length() < ring - 2.0:
				arrived = true
				break

		var ended := walker.controller.state.position
		_check(arrived and lowest > middle.y - 0.5,
			"with %d sides, from corner %d onto the ring" % [sides, corner],
			"%.1f m from the middle, lowest %.2f m against %.2f" % [
				Vector2(ended.x - middle.x, ended.z - middle.z).length(), lowest, middle.y])

		await _dispose(game)

	_finished()


func _test_the_zigzag() -> void:
	_section("the chequerboard is crossed on the diagonals and only on them")

	var game := await _world(func(c: ScConfig) -> void:
		c.cannon_enabled = false
		c.specials_enabled = false
		c.layout_ids = PackedStringArray(["checker"])
	)
	var platforms := game.platforms

	# Through the operator's own knob, so the render and a server running it are the same
	# field this drives.
	_check(game.layout != null and game.layout.id == &"checker",
		"the round is laid out as the chequerboard",
		String(game.layout.id) if game.layout != null else "none")

	var runner := game.add_player(&"runner", "Runner", 1)
	game.add_player(&"other", "Other", 2)

	# Along the whole field: (0,0) (1,1) (2,0) (3,1) (4,0). Four jumps, each one a
	# diagonal, each from the middle of a platform that is leaning under the person on it.
	var route: Array[int] = []

	for column in range(game.config.columns):
		route.append(_deck_at_cell(platforms, column, column % 2))

	_check(not route.has(-1), "the zigzag is all there", str(route))

	var start := platforms.deck_at(route[0])
	runner.place_at(start.centre + Vector3.UP * 0.2, 0.0)
	await _step(game, 20)

	var made := PackedStringArray()

	for leg in range(route.size() - 1):
		var from := route[leg]
		var to := route[leg + 1]
		await _walk_to(game, runner, platforms.deck_at(from).centre)
		var landed := await _jump_across(game, runner, from, to)
		made.append("%s%s" % [_cell_name(platforms, to), "" if landed else " MISSED"])

		if not landed:
			break

	_check(made.size() == route.size() - 1 and not ", ".join(made).contains("MISSED"),
		"a runner crosses the field on four diagonals", ", ".join(made))
	_check(runner.is_alive() and runner.standing_on == route[route.size() - 1],
		"and is standing on the far corner platform at the end",
		"on %d, alive %s" % [runner.standing_on, runner.is_alive()])
	_check(platforms.standing_count() == platforms.count(),
		"with every platform they crossed still up",
		"%d of %d" % [platforms.standing_count(), platforms.count()])

	# [b]And the straight line is a fall, which is the other half of "every jump is a
	# diagonal".[/b] From the far corner back along the row toward (2,0), jumping at the lip.
	var along := _deck_at_cell(platforms, game.config.columns - 3, 0)
	await _walk_to(game, runner, platforms.deck_at(route[route.size() - 1]).centre)
	var crossed := await _jump_across(game, runner, route[route.size() - 1], along)
	_check(not crossed and runner.controller.state.position.y < game.config.deck_height - 3.0,
		"and running straight along a row is a fall",
		"%.1f m" % runner.controller.state.position.y)

	await _dispose(game)
	_finished()


## The Spine's blurb: "the walkways are the steady ground". Until 2026-09-24 a bridge was a
## spring of its own pivoting on a pillar it does not have, and one runner at its end leaned
## it 9.7 degrees against 7.9 for the same runner at a platform's edge; two took it down.
## See [method ScPlatforms._rest_bridges].
func _test_the_spine() -> void:
	_section("The Spine's walkways are the steady ground")

	var game := await _world(func(c: ScConfig) -> void:
		c.cannon_enabled = false
		c.specials_enabled = false
		c.layout_ids = PackedStringArray(["spine"])
	)
	var platforms := game.platforms

	var bridges := 0
	var rested := 0

	for i in range(platforms.count()):
		var deck := platforms.deck_at(i)

		if deck.is_bridge:
			bridges += 1
			rested += 1 if deck.is_rested() else 0

	_check(bridges >= 4 and rested == bridges,
		"every bridge on The Spine rests on the two platforms it joins",
		"%d of %d" % [rested, bridges])

	# The model alone, on a field of its own: one runner's weight at a bridge's end against
	# the same at a platform's edge, each held until the spring has found its angle.
	var bridge_end := _spine_lean(true)
	var platform_edge := _spine_lean(false)
	_check(bridge_end < platform_edge * 0.5,
		"a runner at a bridge's end tilts it less than half what a platform's edge does",
		"%.1f deg against %.1f" % [rad_to_deg(bridge_end), rad_to_deg(platform_edge)])

	# Driven: running, not walking, from the middle of (0,0) over the bridge to (0,1).
	var from := _deck_at_cell(platforms, 0, 0)
	var to := _deck_at_cell(platforms, 0, 1)
	var bridge := -1

	for i in range(platforms.count()):
		var deck := platforms.deck_at(i)

		if deck.is_bridge and deck.column == 0 and deck.row == 0:
			bridge = i

	var runner := game.add_player(&"runner", "Runner", 1)
	game.add_player(&"other", "Other", 2)
	runner.place_at(platforms.deck_at(from).centre + Vector3.UP * 0.2, 0.0)
	await _step(game, 20)

	var target := platforms.deck_at(to).centre
	var span := platforms.deck_at(bridge)
	var worst_bridge := 0.0
	var worst_step := 0.0
	var lowest := INF
	var crossed_on := false
	var arrived := false

	for _i in range(int(6.0 * TICK_RATE)):
		var at := runner.controller.state.position
		var toward := Vector3(target.x - at.x, 0.0, target.z - at.z)

		if toward.length() < 1.0:
			arrived = true
			break

		var command := DotFpsCommand.new()
		command.yaw = rad_to_deg(atan2(-toward.x, -toward.z))
		command.move = Vector2(0.0, 1.0)
		runner.controller.apply_command(command)
		game.simulate(TICK)
		await _physics_frame()

		lowest = minf(lowest, runner.controller.state.position.y)
		worst_bridge = maxf(worst_bridge, span.tilt())
		crossed_on = crossed_on or runner.standing_on == bridge

		# Where the bridge meets each lip there is no step, whatever the platforms are doing.
		var x := span.centre.x
		worst_step = maxf(worst_step, absf(
			platforms.surface_y(bridge, x, span.lips.x) - platforms.surface_y(from, x, span.lips.x)))
		worst_step = maxf(worst_step, absf(
			platforms.surface_y(bridge, x, span.lips.y) - platforms.surface_y(to, x, span.lips.y)))

	await _step(game, 10)

	_check(crossed_on and arrived and runner.standing_on == to and runner.is_alive(),
		"a runner crosses a bridge from one row to the other",
		"on %d, alive %s, lowest %.2f m against a deck at %.2f" % [
			runner.standing_on, runner.is_alive(), lowest, game.config.deck_height])
	# Not the runner's height: the lip they leave from dips most of a metre under a runner,
	# which is the platform doing its job. The bridge is what is being asked about.
	_check(worst_bridge < deg_to_rad(4.0),
		"and the bridge under them never tilts past four degrees",
		"%.1f deg" % rad_to_deg(worst_bridge))
	_check(worst_step < 0.02, "and meets both lips with no step",
		"%.3f m at worst" % worst_step)

	# And it goes with either platform it rests on.
	var why: Array[StringName] = []
	platforms.collapsed.connect(func(index: int, reason: StringName) -> void:
		if index == bridge:
			why.append(reason))
	var _fell := platforms.collapse(from, ScPlatforms.WHY_SHATTERED)
	await _step(game, 2)
	_check(not span.is_standing() and why.has(ScPlatforms.WHY_UNSUPPORTED),
		"and falls when a platform it rests on does", str(why))

	await _dispose(game)
	_finished()


## The equilibrium lean one runner's weight at a bridge's end, or at a platform's edge, puts
## on it, on The Spine's own field.
func _spine_lean(on_bridge: bool) -> float:
	var config := ScConfig.new()
	var platforms := ScPlatforms.new()
	platforms.config = config
	add_child(platforms)
	platforms.build(ScLayouts.by_id(config, &"spine"))

	var index := -1

	for i in range(platforms.count()):
		if platforms.deck_at(i).is_bridge == on_bridge:
			index = i
			break

	var deck := platforms.deck_at(index)
	var half := platforms._footprint(deck)
	var at := deck.centre + (Vector3(0.0, 0.0, half.y * 0.9) if on_bridge \
		else Vector3(half.x * 0.9, 0.0, 0.0))
	var worst := 0.0

	for _i in range(8 * TICK_RATE):
		platforms.begin_loads()
		platforms.add_load(index, at, config.player_mass, config.run_speed)
		platforms.step(TICK)
		worst = maxf(worst, deck.tilt())

	remove_child(platforms)
	platforms.free()
	return worst


## [b]The slide angle is the design, and slopes being walkable must not have moved it.[/b]
## dot-player-controller made a slope under `max_slope_angle` walkable on 2026-09-24; this
## game's is 14 degrees against a collapse at 16, so a player is meant to hold a platform
## leaning 13.5 (and walk up it), and to be thrown off one leaning 15.
func _test_a_slope_holds() -> void:
	_section("a leaning platform holds a player below the slide angle, and not above it")

	var drift := {}

	for degrees: float in [13.5, 15.0]:
		for uphill: bool in [false, true]:
			var game := await _world(func(c: ScConfig) -> void:
				c.cannon_enabled = false
				c.specials_enabled = false
				c.layout_ids = PackedStringArray(["full"])
			)
			var platforms := game.platforms
			# Held at an angle rather than leant on: the model would move it under them.
			platforms.authoritative = false
			var lean := Vector2(deg_to_rad(degrees), 0.0)
			var deck := platforms.deck_at(0)
			platforms.adopt(0, lean, 0.0, ScPlatforms.State.STANDING)

			var player := game.add_player(&"stander", "Stander", 1)
			var start := deck.centre + Vector3(2.0, 0.0, 0.0)
			start.y = platforms.surface_y(0, start.x, start.z) + 0.05
			player.place_at(start, 90.0)

			# Settled first, as somebody already standing there when it tipped.
			for _i in range(40):
				platforms.adopt(0, lean, 0.0, ScPlatforms.State.STANDING)
				game.simulate(TICK)
				await _physics_frame()

			var x := player.controller.state.position.x

			for _i in range(TICK_RATE):
				platforms.adopt(0, lean, 0.0, ScPlatforms.State.STANDING)
				var command := DotFpsCommand.new()
				command.yaw = 90.0  # toward -X, up the lean
				command.move = Vector2(0.0, 1.0) if uphill else Vector2.ZERO
				command.set_button(DotFpsCommand.BUTTON_WALK, uphill)
				player.controller.apply_command(command)
				game.simulate(TICK)
				await _physics_frame()

			drift["%.1f %s" % [degrees, "up" if uphill else "idle"]] = \
				player.controller.state.position.x - x
			await _dispose(game)

	# +X is downhill.
	_check(absf(drift["13.5 idle"]) < 0.1, "a player stands still on a platform at 13.5 degrees",
		"%.2f m" % drift["13.5 idle"])
	_check(drift["13.5 up"] < -1.5, "and walks up it",
		"%.2f m in a second" % drift["13.5 up"])
	# Only standing still is asserted at 15. Pressing uphill there is dot-player-controller's
	# steep-surface air control, which holds a body against a slope the way it holds a surfer
	# on a ramp — so a player who keeps pushing climbs a platform past its slide angle. It is
	# in the detail and in the Queue rather than asserted, because it is the addon's.
	_check(drift["15.0 idle"] > 0.5,
		"and at 15 a player standing still slides down it",
		"%.2f m in a second; pushing uphill instead, %.2f m" % [
			drift["15.0 idle"], drift["15.0 up"]])
	_finished()


func _deck_at_cell(platforms: ScPlatforms, column: int, row: int) -> int:
	for i in range(platforms.count()):
		var deck := platforms.deck_at(i)

		if not deck.is_bridge and deck.column == column and deck.row == row:
			return i

	return -1


## Walks, with the brake held, to a point on whatever the player is standing on, and stops.
func _walk_to(game: ScGame, player: ScPlayer, target: Vector3) -> void:
	for _i in range(int(6.0 * TICK_RATE)):
		var at := player.controller.state.position
		var toward := Vector3(target.x - at.x, 0.0, target.z - at.z)
		var command := DotFpsCommand.new()
		command.yaw = player.controller.state.yaw

		if toward.length() < 0.4:
			player.controller.apply_command(command)
			game.simulate(TICK)
			await _physics_frame()
			break

		command.yaw = rad_to_deg(atan2(-toward.x, -toward.z))
		command.move = Vector2(0.0, 1.0)
		command.set_button(DotFpsCommand.BUTTON_WALK, true)
		player.controller.apply_command(command)
		game.simulate(TICK)
		await _physics_frame()

	# Let them and the platform settle, the way a person would before committing.
	await _step(game, 40)


## Runs at platform [param to] and jumps at the lip of [param from]. True if they land on it.
func _jump_across(game: ScGame, player: ScPlayer, from: int, to: int) -> bool:
	var platforms := game.platforms
	var target := platforms.deck_at(to).centre
	var jumped := false

	for _i in range(int(4.0 * TICK_RATE)):
		var at := player.controller.state.position
		var toward := Vector3(target.x - at.x, 0.0, target.z - at.z)
		var command := DotFpsCommand.new()
		command.yaw = rad_to_deg(atan2(-toward.x, -toward.z))
		command.move = Vector2(0.0, 1.0)

		# Off the last of the lip rather than past it. A capsule is half a metre across and a
		# deck leaning away under a runner stops holding them up a little before its edge.
		if not jumped and platforms.index_at(at.x, at.z) == from:
			var ahead := at + toward.normalized() * 0.6

			if platforms.index_at(ahead.x, ahead.z) != from:
				command.set_button(DotFpsCommand.BUTTON_JUMP, true)
				jumped = true

		player.controller.apply_command(command)
		game.simulate(TICK)
		await _physics_frame()

		if jumped and player.standing_on == to \
				and player.controller.state.mode == DotFpsState.Mode.GROUND:
			return true

		if player.controller.state.position.y < game.config.deck_height - 3.0:
			return false

	return false


func _test_delivery() -> void:
	_section("a delivered pack's own paths still resolve")

	# The seventh form of the family's delivery bug, and the one that cost a boot. A
	# publisher REWRITES every `res://` string inside a `.tscn` onto the mount prefix, so an
	# exported `model_path` arrives at runtime already absolute — and rebasing it a second
	# time produced `res://dot_cloud/tmc/smash/0.1.0/dot_cloud/tmc/smash/0.1.0/assets/...`,
	# which does not load and is long enough that the doubling is easy to read past.
	#
	# Armed: reverted to the unconditional `root().path_join(...)` this fails, and the two
	# below it pass — which is what makes it worth having as its own check.
	# [b]Against a root given rather than the one this build has.[/b] Built in, `root()` is
	# `res://` and every `res://` path is already under it — so `rebase` is the identity here
	# however it is written, and asserting its behaviour against the real root passes with
	# the bug put back. That is measured: it did. [method ScPaths.rebase_onto] is the same
	# function taking the prefix, and this is the only way the mounted case is reachable
	# from a build.
	const MOUNT := "res://dot_cloud/tmc/smash/0.1.0"

	var once := ScPaths.rebase_onto("res://assets/kenney/car/debris-tire.glb", MOUNT)
	_check(
		once == MOUNT + "/assets/kenney/car/debris-tire.glb",
		"a path a script wrote is moved onto the mount",
		once
	)
	_check(
		ScPaths.rebase_onto(once, MOUNT) == once,
		"and one the publisher already rewrote is left alone"
	)

	_check(
		ScPaths.rebase("res://props/sc_crate.tscn") == ScPaths.root().path_join("props/sc_crate.tscn"),
		"and the real root is what rebase uses"
	)

	_check(
		ScPaths.rebase("user://recording.dat") == "user://recording.dat",
		"a path that is not res:// comes back untouched"
	)

	_check(
		ScPaths.rebase("res://textures/%s.png") % "deck" == ScPaths.rebase("res://textures/deck.png"),
		"a format specifier survives being rebased"
	)

	# Form one: a `class_name` in a game repository is a global the HOST does not register,
	# so a delivered pack mounts with every script in it dead and nothing reporting it. The
	# deploy tool refuses one; this says so here as well, because the deploy tool is not what
	# somebody adding a file runs.
	var declared := PackedStringArray()

	for path: String in _scripts_here():
		var text := FileAccess.get_file_as_string(path)

		for line: String in text.split("\n"):
			if line.begins_with("class_name "):
				declared.append(path)
				break

	_check(declared.is_empty(), "no script in this game declares a class_name", ", ".join(declared))

	# Form four: the pack carries what it references. Every model and atlas named in a prop
	# scene has to exist, because a missing one is a prop that spawns, falls, lands and
	# damages a platform while being invisible — which is what game-buses-from-hell shipped.
	var missing := PackedStringArray()
	var referenced := 0

	for path: String in _prop_scenes():
		var text := FileAccess.get_file_as_string(path)

		for line: String in text.split("\n"):
			if not (line.begins_with("model_path") or line.begins_with("atlas_path")):
				continue

			var quoted := line.get_slice("\"", 1)

			if quoted == "":
				continue

			referenced += 1

			if not ResourceLoader.exists(quoted) and not FileAccess.file_exists(quoted):
				missing.append(quoted)

	_check(referenced > 0, "the prop scenes name their art by path", "%d references" % referenced)
	_check(missing.is_empty(), "every model and atlas a prop scene names is in this repository", ", ".join(missing))

	_finished()


## Every script this game owns. Not `addons/`, which is somebody else's rules.
func _scripts_here() -> PackedStringArray:
	var found := PackedStringArray()

	for directory: String in ["res://game", "res://game/net", "res://props", "res://examples", "res://tools"]:
		for file: String in DirAccess.get_files_at(directory):
			if file.ends_with(".gd"):
				found.append(directory.path_join(file))

	return found


func _prop_scenes() -> PackedStringArray:
	var found := PackedStringArray()

	for file: String in DirAccess.get_files_at("res://props"):
		if file.ends_with(".tscn"):
			found.append("res://props".path_join(file))

	return found


# --- The harness ------------------------------------------------------------

func _section(name: String) -> void:
	_sections_entered += 1
	print(name)


func _finished() -> void:
	_sections_finished += 1


func _check(ok: bool, what: String, detail: String = "") -> void:
	if ok:
		_passed += 1
		print("  ok    %s%s" % [what, "" if detail == "" else "  (%s)" % detail])
		return

	_failed += 1
	var line := "%s%s" % [what, "" if detail == "" else "  (%s)" % detail]
	_failures.append(line)
	print("  FAIL  %s" % line)


## What an administrator's blind and beacon DRAW, which neither the net suite nor the
## dedicated one can reach: they assert the flags, and this asserts what a client does with
## them. Whether it looks right is `tools/shot.sh --view=beacon` and `--view=blind`.
##
## A headless viewport is 64 x 64, so "covers the viewport" is a weak claim here — but a
## blind the size of nothing, or of a HUD inset by a margin, is still caught, and the check
## was armed with the overlay anchored top-left at no size.
func _test_blind_and_beacon_drawn() -> void:
	_section("an admin's blind and beacon, drawn")

	var game := await _world()
	var me := game.add_player(&"me", "Me", 1)
	var them := game.add_player(&"them", "Them", 2)

	var hud := ScHud.new()
	add_child(hud)
	hud.bind(game, me)

	me.blinded = true
	for _i in range(30):
		hud.present_blind(1.0 / 60.0)
	_check(
		is_equal_approx(hud.blind_overlay.modulate.a, 1.0) and hud.blind_overlay.visible,
		"a blind fades the screen fully black within half a second",
		"%.2f" % hud.blind_overlay.modulate.a
	)
	var screen := hud.get_viewport().get_visible_rect()
	var covered := hud.blind_overlay.get_global_rect()
	_check(
		covered.encloses(screen) and covered.get_area() > 0.0,
		"and covers the whole viewport, not a HUD-sized part of it",
		"%s over %s" % [covered, screen]
	)
	_check(
		hud.blind_overlay.get_index() == 0,
		"under every number the HUD draws, which still say the round is going on"
	)

	me.blinded = false
	for _i in range(30):
		hud.present_blind(1.0 / 60.0)
	_check(not hud.blind_overlay.visible, "and lifts when the flag does")

	# The beacon, as the client presents it: once a frame at sixty frames a second for 2.9
	# seconds — short of three, because sixty sixtieths summed in floats land ON a period
	# boundary and the fourth ping would be a question about rounding. The promise is a
	# ripple a SECOND: a marker that pinged on every frame would be 174 pings, and a check
	# that asked only "does it ping" would still pass.
	them.beacon = true
	var pings := 0
	for _i in range(174):
		if them.present_beacon(1.0 / 60.0, them.global_position, false):
			pings += 1
	_check(pings == 3, "a beacon pings once a second, starting the moment it comes on",
		"%d pings in 2.9 s" % pings)
	_check(
		them.beacon_marker != null and them.beacon_marker.column_shown(),
		"and draws its column on somebody else's screen"
	)

	me.beacon = true
	var _mine := me.present_beacon(1.0 / 60.0, me.global_position, true)
	_check(
		me.beacon_marker != null and not me.beacon_marker.column_shown(),
		"but not on the beaconed player's own, where the camera is inside it"
	)

	them.beacon = false
	var _gone := them.present_beacon(1.0 / 60.0, them.global_position, false)
	_check(them.beacon_marker == null, "the marker goes when the flag does")

	me.health.alive = false
	var _out := me.present_beacon(1.0 / 60.0, me.global_position, true)
	_check(
		me.beacon_marker == null and me.beacon,
		"and while they are out, though the flag waits for the next round"
	)

	hud.queue_free()
	await _dispose(game)
	_finished()


## A world, built and stepped by hand.
##
## [b]`register_service` is off on every world after the first, and two of these in one
## process is the ordinary case here.[/b] A registry name is global, so the last one to
## register wins — and dot-core's own random manager has the same problem, which is why
## [ScGame] turns that off too.
func _world(configure: Callable = Callable()) -> ScGame:
	var config := ScConfig.new()
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.vary_layout = false

	if configure.is_valid():
		configure.call(config)

	var game := ScGame.new()
	game.name = "World%d" % _worlds.size()
	game.config = config
	game.tick_rate = TICK_RATE
	game.authoritative = true
	game.register_service = false
	add_child(game)
	game.set_physics_process(false)

	_worlds.append(game)

	# Two frames, so the arena, the platforms and every collider are in the physics space
	# before anything is asserted about them. `add_child` does not put a shape in a space;
	# the next physics step does.
	await _physics_frame()
	await _physics_frame()

	return game


func _step(game: ScGame, ticks: int) -> void:
	for _i in range(ticks):
		game.simulate(TICK)
		await _physics_frame()


func _physics_frame() -> void:
	await get_tree().physics_frame


func _dispose(game: ScGame) -> void:
	_worlds.erase(game)

	if not is_instance_valid(game):
		return

	remove_child(game)
	game.free()
	await get_tree().process_frame
