extends Node

const ScArena := preload("../game/sc_arena.gd")
const ScCannon := preload("../game/sc_cannon.gd")
const ScConfig := preload("../game/sc_config.gd")
const ScContent := preload("../game/sc_content.gd")
const ScCopter := preload("../game/sc_copter.gd")
const ScGame := preload("../game/sc_game.gd")
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
const SECTIONS := 14

## And the total this counter cannot be.
##
## [b]A runtime error inside a section aborts that FUNCTION and nothing says so.[/b] The
## checks that already ran still print ok, the ones after it never happen, and the section
## counter is satisfied because the section announced itself on the way in. dot-settings
## reported "8 sections, 63 passed, 0 failed" and exited 0 with eight checks missing.
const CHECKS := 106

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
	await _test_specials()
	await _test_the_chopper()

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
	var pads := 0
	var walks := 0
	var thin := PackedStringArray()

	for child: Node in game.arena.find_children("*", "StaticBody3D", true, false):
		var kerbs := 0

		for piece: Node in child.get_children():
			if String(piece.name).begins_with("KerbHit"):
				kerbs += 1

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

	await _dispose(game)
	_finished()


## [b]The one thing neither the suite nor the editor can see: what happens once this is a
## pack.[/b] Every finding in this section came from a delivered server rather than from
## here, and each is a check written afterwards so the next one is caught before the boot.
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
