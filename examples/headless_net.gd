extends Node

const ScEvents := preload("../game/net/sc_events.gd")
const ScNetBridge := preload("../game/net/sc_net_bridge.gd")
const ScNetCommand := preload("../game/net/sc_net_command.gd")
const ScPlatformNet := preload("../game/net/sc_platform_net.gd")

const ScConfig := preload("../game/sc_config.gd")
const ScContent := preload("../game/sc_content.gd")
const ScGame := preload("../game/sc_game.gd")
const ScLayouts := preload("../game/sc_layouts.gd")
const ScPlatforms := preload("../game/sc_platforms.gd")
const ScPlayer := preload("../game/sc_player.gd")
const ScSpecials := preload("../game/sc_specials.gd")

## mg-smash-copter over the wire: a real server, a real client, and a lossy loopback.
##
## [codeblock]
## godot --headless --path . res://examples/headless_net.tscn
## [/codeblock]
##
## [b]Everything here is the real path minus the socket.[/b] Two [ScGame]s, two
## [DotNetManager]s, two [ScNetBridge]s and two links, with `ScNetLink.loopback` standing in
## for the RPC — so the encoders, the schema seal, the snapshot build, the prediction and
## the reconciliation all run. What it cannot test is Godot's own RPC routing, and that is
## what `dedicated.gd` and a real client are for.
##
## [b]The client world lives in its own [World3D], and that is a finding rather than
## tidiness.[/b] Both halves are in one scene tree, so without it they share one physics
## space: the client's frozen mirrors sit exactly where the server's real bodies are, and
## every server body spends the round being pushed out of a copy of itself. Nothing errors —
## the positions simply stop agreeing, which reads as the replication being wrong when it is
## the harness that is.
##
## [b]And the client is deliberately on a different tick rate and a different field than the
## server.[/b] One process has one engine rate and one default configuration, so two halves
## agree by construction and a check asserting they agree passes for the wrong reason. A
## real client is a separate program with its own export. Make them disagree, and let HELLO
## and LAYOUT correct it.

const SECTIONS := 12
const CHECKS := 122

## Who the client is, on both ends.
const CLIENT_PEER := 7
const SESSION := 42

const SNAPSHOT_RATE := 30

## What the client's own export would have been built at.
const CLIENT_ENGINE_TICK_RATE := 30

const SERVER_TICK_RATE := 64

## Ticks a client stamps ahead of the server, so its command arrives before its tick.
const INPUT_LEAD := 3

## What the client's own configuration says the field is, which is not what the server runs.
const CLIENT_COLUMNS := 3
const SERVER_COLUMNS := 5

## A platform's lean is eleven bits over a range of one radian, so about half a
## milliradian. Everything compared across the wire is checked against this and not against
## zero — a quantised value is not the value, and a suite that demanded equality would be
## asserting that the compression does not work.
const LEAN_EPSILON := 0.004

var _passed := 0
var _failed := 0
var _sections_entered := 0
var _sections_finished := 0
var _failures := PackedStringArray()

var _server_game: ScGame = null
var _client_game: ScGame = null
var _server_net: DotNetManager = null
var _client_net: DotNetManager = null
var _server_bridge: ScNetBridge = null
var _client_bridge: ScNetBridge = null

var _to_client: Array = []
var _to_server: Array = []

var _tick: int = 0
var _snapshot_count: int = 0

## Drop one snapshot in this many. Zero for a perfect link.
var _drop_every: int = 0


func _ready() -> void:
	DotLog.set_level(DotLog.Level.ERROR)
	_run.call_deferred()


func _run() -> void:
	print("smash-copter over the wire")
	print("")

	_test_the_wire()

	if await _build():
		await _test_a_client_joins()
		await _test_the_field_arrives()
		await _test_a_platform_leans_across_the_wire()
		await _test_a_platform_collapses_across_the_wire()
		await _test_props_arrive()
		await _test_moving()
		await _test_the_phases()
		await _test_a_special_is_announced()
		await _test_chat_crosses()
		await _test_a_lossy_link()
		await _test_leaving()

	print("")
	print("%d sections entered, %d finished" % [_sections_entered, _sections_finished])
	print("%d passed, %d failed" % [_passed, _failed])

	for line in _failures:
		print("  FAIL  %s" % line)

	var code := 1 if _failed > 0 else 0

	if _sections_entered != _sections_finished:
		print("ERROR: %d of %d sections finished." % [_sections_finished, _sections_entered])
		code = 1

	if _passed + _failed != CHECKS:
		print("ERROR: %d checks ran, %d expected. A section aborted part-way." % [
			_passed + _failed, CHECKS
		])
		code = 1

	get_tree().quit(code)


# --- The wire ---------------------------------------------------------------

## Every encoder against its own decoder, and nothing else.
##
## [b]Nothing checks that a pair are inverses for you.[/b] This family has already shipped a
## serialisation whose two ends never met: dot-moderation wrote `"voice muted"` and read back
## a warning, and the one thing that addon existed for silently did nothing. Every pair in
## `ScEvents` is round-tripped here, and a new one without a line in this section is a new
## one nothing has ever decoded.
func _test_the_wire() -> void:
	_section("every message survives the trip")

	var hello := ScEvents.read_hello(_reader(
		ScEvents.write_hello(SESSION, 128, 9001, 5, 150.0, 75.0, 3.5)
	))
	_check(bool(hello["ok"]), "hello decodes")
	_check(int(hello["player_id"]) == SESSION, "with the session id")
	_check(int(hello["tick_rate"]) == 128, "the server's tick rate")
	_check(int(hello["server_tick"]) == 9001, "and the tick it was sent on")
	_check(int(hello["team_count"]) == 5, "how many sides are playing")
	_check(absf(float(hello["survival_seconds"]) - 150.0) < 0.2, "and both halves of a round")

	var cells: Array[Vector3i] = [
		Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(1, 0, 1),
	]
	var layout := ScEvents.read_layout(_reader(ScEvents.write_layout(
		&"gauntlet", 5, 2, 11.4, 24.0, 10.5, 40.0, 0.82, 0.66, cells
	)))
	_check(bool(layout["ok"]), "a layout decodes")
	_check(StringName(layout["layout_id"]) == &"gauntlet", "with its id")
	_check(int(layout["columns"]) == 5 and int(layout["rows"]) == 2, "its shape")
	_check(absf(float(layout["deck_height"]) - 40.0) < 0.05, "how high the field is")
	_check(absf(float(layout["pitch_scale"]) - 0.82) < 0.01, "and the scales it is played at")

	var came_back: Array[Vector3i] = layout["cells"]
	_check(came_back.size() == cells.size(), "every cell comes back", "%d" % came_back.size())
	_check(
		came_back.size() == cells.size() and came_back[2] == cells[2] and came_back[3] == cells[3],
		"in the same order, bridges and all"
	)

	var platform := ScEvents.read_platform(_reader(ScEvents.write_platform(88, 11)))
	_check(
		bool(platform["ok"]) and int(platform["net_id"]) == 88 and int(platform["index"]) == 11,
		"a platform's net id and index decode"
	)

	var fell := ScEvents.read_collapse(_reader(
		ScEvents.write_collapse(6, ScPlatforms.WHY_SHATTERED)
	))
	_check(
		bool(fell["ok"]) and int(fell["index"]) == 6
			and StringName(fell["why"]) == ScPlatforms.WHY_SHATTERED,
		"and so does a collapse, with its reason"
	)

	var join := ScEvents.read_join(_reader(ScEvents.write_join(SESSION, 5, "Ada", 4)))
	_check(
		bool(join["ok"]) and int(join["player_id"]) == SESSION and str(join["name"]) == "Ada"
			and int(join["team"]) == 4,
		"a join carries a name and a side"
	)
	_check(ScEvents.read_player(_reader(ScEvents.write_player(SESSION))) == SESSION,
		"a leave carries who left")

	var team := ScEvents.read_team(_reader(ScEvents.write_team(SESSION, 6)))
	_check(bool(team["ok"]) and int(team["team"]) == 6, "a side change carries six sides")

	var death := ScEvents.read_death(_reader(
		ScEvents.write_death(SESSION, 9, ScGame.DIED_CRUSHED)
	))
	_check(
		bool(death["ok"]) and int(death["by"]) == 9
			and StringName(death["why"]) == ScGame.DIED_CRUSHED,
		"a death carries who and what"
	)

	var armed := ScEvents.read_armed(_reader(ScEvents.write_armed(SESSION, &"drum_shotgun")))
	_check(
		bool(armed["ok"]) and StringName(armed["weapon_id"]) == &"drum_shotgun",
		"and a survivor's weapon is named"
	)

	var at := Vector3(-41.25, 46.5, 17.75)
	var prop := ScEvents.read_prop(_reader(
		ScEvents.write_prop(3, ScContent.MONOLITH, at, false)
	))
	_check(bool(prop["ok"]) and StringName(prop["kind_id"]) == ScContent.MONOLITH,
		"a prop names its catalogue entry")
	_check(
		(prop["position"] as Vector3).distance_to(at) < 0.01,
		"and arrives where it was put",
		"%.4f m out" % (prop["position"] as Vector3).distance_to(at)
	)
	_check(not bool(prop["vehicle"]), "and says it is not a vehicle")

	var copter := ScEvents.read_prop(_reader(
		ScEvents.write_prop(4, ScContent.COPTER, at, true)
	))
	_check(bool(copter["ok"]) and bool(copter["vehicle"]), "and a chopper says it is one")

	var gone := ScEvents.read_prop_gone(_reader(
		ScEvents.write_prop_gone(3, DotPropSpawner.REASON_CLEANUP)
	))
	_check(bool(gone["ok"]) and int(gone["net_id"]) == 3, "a removal names what went")

	var seat := ScEvents.read_seat(_reader(ScEvents.write_seat(SESSION, 12, true)))
	_check(bool(seat["ok"]) and bool(seat["seated"]), "a seat change decodes")

	var clock := ScEvents.read_clock(_reader(
		ScEvents.write_clock(3, 61.5, ScGame.Phase.SHOWDOWN, 9, 5, 2, true)
	))
	_check(bool(clock["ok"]) and int(clock["round"]) == 3, "the clock carries the round")
	_check(absf(float(clock["elapsed"]) - 61.5) < 0.1, "how far into it we are")
	_check(int(clock["phase"]) == ScGame.Phase.SHOWDOWN, "which half it is")
	_check(
		int(clock["standing"]) == 9 and int(clock["alive"]) == 5 and int(clock["teams_alive"]) == 2,
		"and the three numbers a client cannot count for itself"
	)

	var round_info := ScEvents.read_round(_reader(ScEvents.write_round(7, false, 3)))
	_check(
		bool(round_info["ok"]) and int(round_info["round"]) == 7
			and not bool(round_info["began"]) and int(round_info["winner"]) == 3,
		"a round ending names its winner"
	)

	var phase := ScEvents.read_phase(_reader(ScEvents.write_phase(ScGame.Phase.HANDOVER)))
	_check(bool(phase["ok"]) and int(phase["phase"]) == ScGame.Phase.HANDOVER,
		"a phase change decodes")

	var special := ScEvents.read_special(_reader(
		ScEvents.write_special(&"feather", true, "LOW GRAVITY — mind the landing")
	))
	_check(bool(special["ok"]) and StringName(special["special_id"]) == &"feather",
		"a special names itself")
	_check(
		str(special["blurb"]).begins_with("LOW GRAVITY"),
		"and carries what to shout, so an older client can still say something"
	)

	var blast := ScEvents.read_blast(_reader(ScEvents.write_blast(at, 6.5)))
	_check(
		bool(blast["ok"]) and (blast["position"] as Vector3).distance_to(at) < 0.01
			and absf(float(blast["radius"]) - 6.5) < 0.05,
		"a blast decodes where and how far"
	)

	var said := ScEvents.read_say(_reader(ScEvents.write_say(&"team", "north bridge")))
	_check(
		bool(said["ok"]) and str(said["channel"]) == "team" and str(said["text"]) == "north bridge",
		"what a client types decodes"
	)

	var notice := ScEvents.read_notice(_reader(ScEvents.write_notice("you are talking too fast")))
	_check(bool(notice["ok"]) and str(notice["text"]).begins_with("you are"),
		"and a notice to one person")

	var wire := {
		"n": 12, "t": 1700000000, "c": "near", "k": "say",
		"s": "u42", "d": "Ada", "w": "", "m": "watch the gap", "x": {"p": SESSION},
	}
	var chat := ScEvents.read_chat(_reader(ScEvents.write_chat(wire)))
	_check(bool(chat["ok"]) and str(chat["m"]) == "watch the gap", "a routed line decodes")
	_check(str(chat["d"]) == "Ada" and str(chat["c"]) == "near", "with its speaker and channel")
	_check(
		typeof(chat.get("x")) == TYPE_DICTIONARY and int((chat["x"] as Dictionary)["p"]) == SESSION,
		"and the one meta field this game carries"
	)

	var asked := ScEvents.read_ask_team(_reader(ScEvents.write_ask_team(5)))
	_check(bool(asked["ok"]) and int(asked["team"]) == 5, "and a request for a side")

	# [b]A reader past its end returns plausible zeros rather than failing.[/b] dot-net
	# shipped with exhaustion that was not sticky, so a decoder that skipped the `ok` check
	# got a believable value for the field AFTER the overrun — and a truncated packet decodes
	# as a valid message about nothing.
	var truncated := ScEvents.read_hello(DotNetReader.new(PackedByteArray([1, 2])))
	_check(not bool(truncated["ok"]), "and a truncated message says so rather than guessing")

	_finished()


# --- Building both halves ---------------------------------------------------

func _build() -> bool:
	_section("bringing both halves up")

	var server_side := Node.new()
	server_side.name = "ServerSide"
	add_child(server_side)

	# The client's own physics space. See the class note: without it the client's frozen
	# mirrors and the server's real bodies are in one world, in the same cubic metres, and
	# the server's field is quietly pushed apart by a copy of itself.
	var client_view := SubViewport.new()
	client_view.name = "ClientView"
	client_view.own_world_3d = true
	client_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(client_view)

	var client_side := Node.new()
	client_side.name = "ClientSide"
	client_view.add_child(client_side)

	_server_game = _make_game(true, server_side)
	_client_game = _make_game(false, client_side)

	await get_tree().process_frame

	_check(
		_server_game.get_world_3d() != _client_game.get_world_3d(),
		"the two halves are in separate physics worlds, as two processes would be"
	)
	_check(
		_client_game.tick_rate != _server_game.tick_rate,
		"the client is on its own export's tick rate",
		"%d vs %d" % [_client_game.tick_rate, _server_game.tick_rate]
	)
	_check(
		_client_game.platforms.count() != _server_game.platforms.count(),
		"and has built its own default field, which is not the server's",
		"%d vs %d platforms" % [
			_client_game.platforms.count(), _server_game.platforms.count()
		]
	)

	Engine.physics_ticks_per_second = CLIENT_ENGINE_TICK_RATE

	_server_net = _make_manager(true, &"server", 1, server_side, _server_game.tick_rate)
	_client_net = _make_manager(
		false, &"client", CLIENT_PEER, client_side, _client_game.tick_rate
	)

	_server_bridge = ScNetBridge.new()
	_server_bridge.name = "Bridge"
	server_side.add_child(_server_bridge)

	_client_bridge = ScNetBridge.new()
	_client_bridge.name = "Bridge"
	client_side.add_child(_client_bridge)

	var attached := _server_bridge.attach(_server_game, _server_net)
	_check(attached.ok, "the server bridge attaches",
		str(attached.error) if not attached.ok else "")

	var client_attached := _client_bridge.attach(_client_game, _client_net)
	_check(client_attached.ok, "the client bridge attaches",
		str(client_attached.error) if not client_attached.ok else "")

	# The one mistake this check exists for: a client world handed a server manager. Both
	# halves are the same class, so nothing but this comparison can tell them apart.
	var wrong := ScNetBridge.new()
	add_child(wrong)
	var refused := wrong.attach(_client_game, _server_net)
	_check(
		not refused.ok and refused.error.code == DotError.CODE_STATE,
		"a client world on a server manager is refused"
	)
	wrong.queue_free()

	_server_bridge.open_link(server_side)
	_client_bridge.open_link(client_side)
	_check(_server_bridge.link != null and _client_bridge.link != null, "both links open")
	_check(
		_server_bridge.link.name == _client_bridge.link.name,
		"and are named the same on both ends, because the name is the routing",
		String(_server_bridge.link.name)
	)

	_server_net.messages.seal()
	_client_net.messages.seal()
	_check(
		_server_net.messages.schema_hash() == _client_net.messages.schema_hash(),
		"both ends agree on the message schema"
	)

	_server_bridge.link.loopback = _on_server_send
	_client_bridge.link.loopback = _on_client_send

	# What a real client wires to `DotClientLink.ping_ms()`. Nothing in dot-net writes an RTT
	# sample, and a client that feeds none has a clock that believes the link is instant — so
	# every command it stamps arrives after its tick has passed.
	_client_bridge.rtt_source = func() -> float:
		return 40.0

	_check(_server_game.external_tick, "the server world hands its tick to the bridge")
	_check(
		_client_game.external_tick,
		"and so does the client's, which predicts and interpolates instead"
	)

	var _server_started := _server_net.start()
	var _client_started := _client_net.start()

	# A stand-in on the other side, before anybody joins. A round needs two sides to exist
	# at all, and `_side_for_new_player` puts a joiner on the smallest — so seating one first
	# is also what decides which side the client under test ends up on.
	var stand_in := _server_bridge.add_bot("Stand-in", 1)
	_check(stand_in != null and stand_in.is_bot, "a stand-in is seated before anybody joins")
	_check(
		int(_server_bridge.describe()["players"]) == 1,
		"and is replicated exactly like a person, minus the socket"
	)

	# The world is started AFTER the bridge is attached, which is what the module does and
	# for the reason written there: a field laid out before anything was listening to
	# `world_rebuilt` is a field no client is ever told about.
	_server_game.start()
	await get_tree().physics_frame

	_check(
		int(_server_bridge.describe()["bodies"]) > 0,
		"and the server's field is replicated from the moment it is laid out",
		"%d bodies" % int(_server_bridge.describe()["bodies"])
	)

	_finished()
	return _failed == 0


# --- Joining ----------------------------------------------------------------

func _test_a_client_joins() -> void:
	_section("a client joins")

	var seated := _server_bridge.add_player(CLIENT_PEER, SESSION, "Ada")
	_check(seated.ok, "the server seats them", str(seated.error) if not seated.ok else "")

	_client_bridge.ask_ready()
	_exchange()
	_exchange()

	# [b]And then let the round actually begin, which re-lays the field from inside the
	# netcode's own loop.[/b] dot-match runs a warmup before the first round and nothing has
	# ticked yet, so without this every section below would be asserting about a world that
	# had not started — and the round would begin in the middle of whichever one ticked
	# first. It is also what a real client joining a live server sees: the field is rebuilt
	# under them at the top of every round.
	await _steps(12)

	_check(_client_bridge.local_player_id == SESSION, "and the client is told who it is",
		"%d" % _client_bridge.local_player_id)

	# [b]The server's tick rate, and another game in this family shipped with HELLO carrying
	# it and nothing reading it.[/b] A browser client counted at the 60 its export declared
	# against a server on 128, so every replicated time was out by 128/60 — produced
	# correctly and consumed by nothing.
	_check(
		_client_game.tick_rate == SERVER_TICK_RATE,
		"it adopts the server's tick rate",
		"%d" % _client_game.tick_rate
	)
	_check(
		Engine.physics_ticks_per_second == SERVER_TICK_RATE,
		"and so does the engine it is drawing with",
		"%d" % Engine.physics_ticks_per_second
	)
	_check(
		_client_net.clock.tick_rate == SERVER_TICK_RATE,
		"and the live clock, not only the config it was built from"
	)

	var mine: ScPlayer = _client_game.players.get(ScNetBridge.player_key(SESSION))
	_check(mine != null, "the client has a body for itself")
	_check(
		_client_game.players.size() == 2,
		"and one for everybody already on the server",
		"%d" % _client_game.players.size()
	)
	_check(
		mine != null and not mine.samples_input,
		"which does not sample a keyboard, because the client loop hands it commands"
	)
	_check(
		_client_game.config.team_count == _server_game.config.team_count,
		"the client took the server's number of sides"
	)
	_check(
		absf(_client_game.config.survival_seconds - _server_game.config.survival_seconds) < 0.5,
		"and both halves of its round"
	)

	_finished()


# --- The field --------------------------------------------------------------

func _test_the_field_arrives() -> void:
	_section("the field arrives")

	_check(
		_client_game.platforms.count() == _server_game.platforms.count(),
		"the client rebuilt the server's field",
		"%d vs %d" % [_client_game.platforms.count(), _server_game.platforms.count()]
	)

	# [b]In the same ORDER, which is what the wire addresses a platform by.[/b] A client that
	# derived the field from a catalogue of its own would build the right field right up
	# until its build was one layout behind — and then its platform seven would be somewhere
	# else and every snapshot after that would move the wrong floor, silently.
	var same_places := true
	var worst := 0.0

	for i in range(_server_game.platforms.count()):
		var here := _server_game.platforms.deck_at(i)
		var there := _client_game.platforms.deck_at(i)

		if there == null:
			same_places = false
			break

		worst = maxf(worst, here.centre.distance_to(there.centre))

		if here.centre.distance_to(there.centre) > 0.01:
			same_places = false

	_check(same_places, "platform by platform, in the same order", "%.4f m worst" % worst)

	var bridges_here := 0
	var bridges_there := 0

	for i in range(_server_game.platforms.count()):
		if _server_game.platforms.deck_at(i).is_bridge:
			bridges_here += 1

		if _client_game.platforms.deck_at(i).is_bridge:
			bridges_there += 1

	_check(bridges_here == bridges_there, "and the bridges are bridges on both ends",
		"%d vs %d" % [bridges_here, bridges_there])

	_check(
		_client_game.platforms.count() > 0
			and _client_game.platforms.deck_at(0).body != null,
		"every mirrored platform has a body a player can stand on"
	)

	# The client runs no model at all. This is the check that says so: its platforms are
	# moved by snapshots and by nothing else.
	_check(not _client_game.platforms.authoritative, "and the client runs no platform model")

	var mapped := 0

	for i in range(_client_game.platforms.count()):
		var deck := _client_game.platforms.deck_at(i)

		if deck.body != null and deck.body.get_node_or_null(^"Net") != null:
			mapped += 1

	_check(
		mapped == _client_game.platforms.count(),
		"and every one of them is bound to a net id",
		"%d of %d" % [mapped, _client_game.platforms.count()]
	)

	_finished()


# --- A platform, over the wire ----------------------------------------------

func _test_a_platform_leans_across_the_wire() -> void:
	_section("a lean crosses the wire")

	var here := _server_game.platforms.deck_at(0)
	var there := _client_game.platforms.deck_at(0)
	var at := here.centre + Vector3(here.half * 0.8, 0.0, 0.0)

	_check(there.tilt() < 0.01, "the client's copy starts level", "%.4f rad" % there.tilt())

	# [b]An impact rather than a load, and the difference is the game's own tick.[/b]
	# `ScGame._load_platforms` calls `begin_loads()` every tick and re-gathers what is
	# standing on each platform, so a load added by hand from outside is wiped before it is
	# ever integrated — the first version of this section did that and measured the lean of
	# the one player who happened to be standing there. An impact is not a load: it is a
	# push on the lean velocity, which is exactly what a prop landing does, and it survives
	# the next `begin_loads`.
	var _hit := _server_game.platforms.report_impact(0, 260.0, 12.0, at)

	for _i in range(20):
		await _step()

	_check(here.tilt() > 0.02, "the server's platform leaned", "%.4f rad" % here.tilt())
	_check(
		absf(there.lean.x - here.lean.x) < LEAN_EPSILON,
		"and the client's copy leans the same way, to the bit",
		"%.5f vs %.5f" % [there.lean.x, here.lean.x]
	)
	_check(
		absf(there.lean.y - here.lean.y) < LEAN_EPSILON,
		"on both axes"
	)

	# [b]The SURFACE, which is what a player actually stands on.[/b] Two leans that agree
	# and two surfaces that do not would be a client drawing the right angle about the wrong
	# pivot — and the thing a player falls through is the surface.
	var surface_here := _server_game.platforms.surface_y(0, at.x, at.z)
	var surface_there := _client_game.platforms.surface_y(0, at.x, at.z)
	_check(
		absf(surface_here - surface_there) < 0.05,
		"and the surface under one point is at the same height on both ends",
		"%.4f m apart" % absf(surface_here - surface_there)
	)

	# And the body a motor sweeps against actually moved, rather than the number alone.
	_check(
		there.body != null and absf(there.body.global_basis.y.y - 1.0) > 0.0001,
		"the mirrored body is genuinely tilted, not just the number"
	)

	_finished()


func _test_a_platform_collapses_across_the_wire() -> void:
	_section("a collapse takes the client's floor away")

	var index := 1
	var here := _server_game.platforms.deck_at(index)
	var there := _client_game.platforms.deck_at(index)

	var told: Array[int] = []
	_client_bridge.collapse_received.connect(
		func(i: int, _why: StringName) -> void: told.append(i)
	)

	_check(there.is_standing(), "it is standing on both ends to begin with")

	var _fell := _server_game.platforms.collapse(index, ScPlatforms.WHY_SHATTERED)
	await _steps(6)

	_check(not here.is_standing(), "the server takes it off its pillar")
	# An Array, never a captured counter: a GDScript lambda captures locals BY VALUE, so an
	# `int` incremented in a handler stays zero outside it and the check reports a failure
	# for a signal that fired perfectly.
	_check(told.has(index), "the client is told, reliably, which one and why")
	_check(not there.is_standing(), "and its own copy stops standing",
		ScPlatforms.State.keys()[there.state])

	# [b]The collider goes with it, and this is the check that matters.[/b] A client that
	# knew a platform had gone and left the floor there is a player standing on something
	# that does not exist anywhere else — which is the worst version of the bug the whole
	# platform model exists to avoid.
	var collider := there.body.get_node_or_null(^"Collision") as CollisionShape3D \
		if there.body != null else null
	_check(collider == null or collider.disabled, "and the floor under it is gone")

	_check(
		_client_game.platforms.index_of_body(
			there.body.get_instance_id() if there.body != null else 0
		) == -1,
		"so nothing on the client can be standing on it"
	)

	_finished()


# --- Props ------------------------------------------------------------------

func _test_props_arrive() -> void:
	_section("what the cannon throws arrives")

	var before := int(_client_bridge.describe()["bodies"])

	var sent := _server_game.cannon.fire(0.0, ScSpecials.Active.new())
	_check(sent > 0, "the server fires", "%d props" % sent)

	await _steps(10)

	var after := int(_client_bridge.describe()["bodies"])
	_check(after > before, "and the client is told about them",
		"%d bodies, was %d" % [after, before])

	# The client builds the body from the catalogue id it was sent, not from a script name —
	# which is the whole reason a prop is addressed that way. A mounted pack's `class_name`
	# globals are not registered in the host.
	var mirrored := 0
	var frozen := 0

	for child in _client_game.get_children():
		var body := child as RigidBody3D

		if body == null:
			continue

		mirrored += 1

		if body.freeze:
			frozen += 1

	_check(mirrored > 0, "it built real bodies for them", "%d" % mirrored)
	_check(
		mirrored == frozen,
		"and froze every one, because a mirror must not be simulated twice",
		"%d of %d" % [frozen, mirrored]
	)

	# And they are where the server has them, within the quantisation the wire uses.
	var worst := INF

	for prop in _server_game.props.all_props():
		var at := prop.body().global_position
		var closest := INF

		for child in _client_game.get_children():
			var body := child as RigidBody3D

			if body != null:
				closest = minf(closest, body.global_position.distance_to(at))

		worst = minf(worst, closest)

	_check(worst < 1.0, "in about the right place", "%.3f m" % worst)

	_finished()


# --- Moving -----------------------------------------------------------------

func _test_moving() -> void:
	_section("a client moves itself and the server agrees")

	var mine: ScPlayer = _client_game.players.get(ScNetBridge.player_key(SESSION))
	var theirs: ScPlayer = _server_game.players.get(ScNetBridge.player_key(SESSION))

	if mine == null or theirs == null:
		for what in [
			"the client predicts its own movement",
			"the server moved them the same way",
			"and the two agree about where they are",
			"with the predictor barely correcting",
			"a button the client holds reaches the server",
		]:
			_check(false, what)

		_finished()
		return

	var started := mine.controller.state.position

	var forward := DotFpsCommand.new()
	forward.move = Vector2(0.0, 1.0)
	forward.yaw = 0.0

	await _steps(40, forward)

	var moved := mine.controller.state.position.distance_to(started)
	_check(moved > 1.0, "the client predicts its own movement", "%.2f m" % moved)

	var server_moved := theirs.controller.state.position.distance_to(started)
	_check(server_moved > 1.0, "the server moved them the same way", "%.2f m" % server_moved)

	var apart := mine.controller.state.position.distance_to(theirs.controller.state.position)
	_check(apart < 1.5, "and the two agree about where they are", "%.3f m apart" % apart)

	# [b]Corrections, not packets.[/b] A correction is the number that says whether the two
	# ends are computing the same thing; a packet count says only that they are talking.
	var rate := _client_net.predictor.correction_rate()
	_check(rate < 0.5, "with the predictor correcting on a minority of snapshots",
		"%.2f" % rate)

	# A game button, all the way across. The fire button is what the showdown is played with
	# and it rides in the movement command rather than in a request, because it is held.
	var firing := DotFpsCommand.new()
	firing.set_button(ScNetCommand.BUTTON_FIRE, true)
	await _steps(4, firing)

	var behaviour: Variant = null

	for session_id in [SESSION]:
		behaviour = _server_bridge._behaviours.get(session_id)

	_check(
		behaviour != null and (behaviour as Node).get("last_move") != null
			and (behaviour.get("last_move") as DotFpsCommand).is_pressed(ScNetCommand.BUTTON_FIRE),
		"a button the client holds reaches the server"
	)

	_finished()


# --- Phases, specials, chat -------------------------------------------------

func _test_the_phases() -> void:
	_section("the round's halves reach the client")

	var seen: Array[int] = []
	_client_bridge.phase_received.connect(func(p: int) -> void: seen.append(p))

	_check(_server_game.phase == ScGame.Phase.SURVIVAL, "the server is on the platforms",
		ScGame.Phase.keys()[_server_game.phase])

	# Wind the survival clock on rather than waiting two minutes of simulated time.
	_server_game.round_elapsed = _server_game.config.survival_seconds - 0.05
	await _steps(10)

	_check(_server_game.phase == ScGame.Phase.HANDOVER, "the clock sends it to the corners",
		ScGame.Phase.keys()[_server_game.phase])
	_check(seen.has(ScGame.Phase.HANDOVER), "and the client is told")
	_check(_client_game.phase == ScGame.Phase.HANDOVER, "and adopts it",
		ScGame.Phase.keys()[_client_game.phase])

	var theirs: ScPlayer = _server_game.players.get(ScNetBridge.player_key(SESSION))
	_check(theirs != null and theirs.weapons != null, "the survivor was armed on the server")

	var corner := _server_game.arena.corner_point(
		theirs.team - 1, _server_game.config.team_count
	)
	var apart := Vector2(
		theirs.controller.state.position.x - corner.x,
		theirs.controller.state.position.z - corner.z
	).length()
	_check(apart < _server_game.config.corner_size, "and moved to their corner",
		"%.1f m from the middle of it" % apart)

	# And the client's copy follows them there, which is a sixty-metre teleport arriving
	# through the ordinary snapshot path.
	await _steps(8)

	var mine: ScPlayer = _client_game.players.get(ScNetBridge.player_key(SESSION))
	var followed := mine.controller.state.position.distance_to(theirs.controller.state.position)
	_check(followed < 3.0, "and the client's copy went with them", "%.2f m apart" % followed)

	_server_game.round_elapsed = _server_game.config.showdown_starts_at() + 0.05
	await _steps(10)

	_check(seen.has(ScGame.Phase.SHOWDOWN), "the showdown is announced too")

	_finished()


func _test_a_special_is_announced() -> void:
	_section("something strange is announced")

	var told: Array[StringName] = []
	var blurbs: Array[String] = []

	_client_bridge.special_received.connect(
		func(id: StringName, starting: bool, blurb: String) -> void:
			if starting:
				told.append(id)
				blurbs.append(blurb)
	)

	var special := ScSpecials.by_id(&"feather")
	_server_game.special_changed.emit(special.id, true, special.blurb)
	_exchange()

	_check(told.has(&"feather"), "the client hears about it")
	_check(
		not blurbs.is_empty() and blurbs[0] == special.blurb,
		"and is handed what to shout, rather than looking it up in a catalogue it may not have"
	)

	# The folding itself is the server's, and the client never runs it — it is told the
	# consequences through the ordinary state.
	var both := ScSpecials.Active.new()
	both.fold(special)
	both.fold(ScSpecials.by_id(&"barrage"))
	_check(both.ids.size() == 2 and both.gravity_scale < 1.0, "two at once still multiply")

	_finished()


func _test_chat_crosses() -> void:
	_section("a line crosses")

	var asked: Array[String] = []
	var channels: Array[StringName] = []

	_server_bridge.say_requested.connect(
		func(peer_id: int, channel_id: StringName, text: String) -> void:
			asked.append("%d:%s" % [peer_id, text])
			channels.append(channel_id)
	)

	_client_bridge.ask_say(&"team", "bridge is going")
	_exchange()

	_check(asked.size() == 1, "the server is asked once", "%d" % asked.size())
	_check(
		not asked.is_empty() and asked[0] == "%d:bridge is going" % CLIENT_PEER,
		"with the peer the TRANSPORT reported, not one the body claimed",
		asked[0] if not asked.is_empty() else ""
	)
	_check(not channels.is_empty() and channels[0] == &"team", "and the channel asked for")

	# An empty line never leaves the client, which is the cheapest rate limit there is.
	_client_bridge.ask_say(&"team", "   ")
	_exchange()
	_check(asked.size() == 1, "an empty line is not sent at all")

	# And the other direction: a routed line the server hands back.
	var drawn: Array[String] = []
	_client_bridge.chat_received.connect(
		func(wire: Dictionary) -> void: drawn.append(str(wire.get("m", "")))
	)

	_server_bridge.send_chat(CLIENT_PEER, {
		"n": 1, "t": 0, "c": "team", "k": "say", "s": "u42", "d": "Ada", "w": "",
		"m": "on my way", "x": {"p": SESSION},
	})
	_exchange()

	_check(drawn.has("on my way"), "and a routed line comes back to be drawn")

	# A notice reaches one person. "You are talking too fast" is nobody else's business.
	var notices: Array[String] = []
	_client_bridge.notice_received.connect(func(text: String) -> void: notices.append(text))

	_server_bridge.notice(CLIENT_PEER, "you are gagged")
	_exchange()

	_check(notices.has("you are gagged"), "and a refusal reaches the one person who asked")

	_finished()


# --- A bad link -------------------------------------------------------------

func _test_a_lossy_link() -> void:
	_section("a link that loses things")

	var mine: ScPlayer = _client_game.players.get(ScNetBridge.player_key(SESSION))
	var theirs: ScPlayer = _server_game.players.get(ScNetBridge.player_key(SESSION))

	# One snapshot in three on the floor. Snapshots are unreliable by design: a newer one
	# supersedes a lost one and resending a hundred-millisecond-old position is worse than
	# useless.
	_drop_every = 3

	var forward := DotFpsCommand.new()
	forward.move = Vector2(0.0, 1.0)

	await _steps(50, forward)

	var apart := mine.controller.state.position.distance_to(theirs.controller.state.position)
	_check(apart < 3.0, "the two ends still agree about where the player is",
		"%.2f m apart" % apart)

	var dropped := _snapshot_count / maxi(_drop_every, 1)
	_check(dropped > 0, "with snapshots genuinely on the floor", "%d dropped" % dropped)

	# A platform's lean is in the snapshot, so a lossy link is exactly where a floor would
	# drift. It does not: the next snapshot carries the whole state rather than a delta
	# against one that never arrived.
	_drop_every = 0
	await _steps(8)

	# [b]The STANDING ones, because a falling platform's lean is not a comparable
	# number.[/b] It grows without bound on the way down and the wire carries half a radian,
	# so a falling platform saturates by design — and a check that included one would be
	# asserting that a quantised field can hold a value outside its own range.
	var worst := 0.0
	var compared := 0

	for i in range(_server_game.platforms.count()):
		var here := _server_game.platforms.deck_at(i)
		var there := _client_game.platforms.deck_at(i)

		if here == null or there == null or not here.is_standing():
			continue

		compared += 1
		worst = maxf(worst, (here.lean - there.lean).length())

	_check(compared > 0, "there are platforms left to compare", "%d" % compared)
	_check(worst < LEAN_EPSILON * 3.0, "and every standing platform's lean has caught up",
		"%.5f rad worst" % worst)

	_finished()


func _test_leaving() -> void:
	_section("leaving")

	var left: Array[int] = []
	_client_bridge.roster_changed.connect(func(id: int) -> void: left.append(id))

	var before := _client_game.players.size()

	# [b]The stand-in, not the client under test.[/b] `remove_player` takes a leaver out of
	# the ready set before it announces the LEAVE, which is correct — a server has nothing to
	# tell somebody who has gone — and it means the one departure a single-client suite can
	# actually observe is somebody else's.
	var bot_session := 0

	for session_id in _server_bridge._behaviours.keys():
		if int(session_id) != SESSION:
			bot_session = int(session_id)

	_check(bot_session != 0, "there is somebody else on the server to lose")

	_server_bridge.remove_player(bot_session)
	_exchange()
	_exchange()

	_check(
		not _server_game.players.has(ScNetBridge.player_key(bot_session)),
		"the server forgets them"
	)
	_check(left.has(bot_session), "the client is told")
	_check(
		_client_game.players.size() < before,
		"and forgets them too",
		"%d, was %d" % [_client_game.players.size(), before]
	)

	# And now the client itself, which is the path that cleans up dot-combat.
	var entity := (_server_game.players[ScNetBridge.player_key(SESSION)] as ScPlayer).entity_id
	_server_bridge.remove_player(SESSION)
	_exchange()

	_check(
		not _server_game.players.has(ScNetBridge.player_key(SESSION)),
		"and the client itself when it goes"
	)

	# [b]dot-combat keeps a health record per entity and nothing else tells it to let
	# go.[/b] game-buses-from-hell leaked one per player who ever joined, pointing at a node
	# freed with them — invisible, because a stale entity is never asked about.
	_check(_server_game.combat.health_of(entity) == null, "the combat manager let go of them")
	_check(_server_game.entities.key_for_id(entity) == &"", "and so did the entity table")

	_finished()


# --- The harness ------------------------------------------------------------

func _make_game(server: bool, parent: Node) -> ScGame:
	var config := ScConfig.new()
	config.columns = SERVER_COLUMNS if server else CLIENT_COLUMNS
	config.rows = 2
	config.survival_seconds = 30.0
	config.showdown_warmup_seconds = 1.0
	config.showdown_seconds = 20.0
	config.warmup_seconds = 0.0
	config.intermission_seconds = 0.0
	config.minimum_players = 0
	config.cannon_enabled = false
	config.specials_enabled = false
	config.vary_layout = false
	config.chopper_enabled = false
	# The showdown must not clear the field in this suite: several sections assert about
	# platforms on both sides of the handover, and a field that vanished at the phase change
	# would make them assert about nothing.
	config.clear_platforms_for_showdown = false

	var game := ScGame.new()
	game.name = "World"
	game.config = config
	game.authoritative = server
	game.tick_rate = SERVER_TICK_RATE if server else CLIENT_ENGINE_TICK_RATE
	# Neither registers: a registry name is global to the process and the last one to
	# register wins, which is precisely the situation a server and a client in one process
	# is.
	game.register_service = false
	parent.add_child(game)
	game.set_physics_process(false)
	return game


func _make_manager(
	server: bool, scope: StringName, peer_id: int, parent: Node, tick_rate: int
) -> DotNetManager:
	var manager := DotNetManager.new()
	manager.name = "Server" if server else "Client"
	manager.is_server = server
	manager.local_peer_id = peer_id
	manager.service_scope = scope
	manager.auto_tick = false
	manager.config_file = ""

	var config := DotNetConfig.new()
	config.tick_rate = tick_rate
	config.snapshot_rate = SNAPSHOT_RATE
	config.enable_prediction = true
	config.enable_lag_compensation = false
	config.max_entities_per_snapshot = 192
	config.world_extent = ScGame.NET_WORLD_EXTENT
	manager.config = config

	parent.add_child(manager)
	var _ready_now := manager.setup()
	return manager


func _on_server_send(method: StringName, peer_id: int, payload: PackedByteArray) -> void:
	if method == &"snapshot":
		_snapshot_count += 1

		if _drop_every > 0 and _snapshot_count % _drop_every == 0:
			return

	if peer_id != 0 and peer_id != CLIENT_PEER:
		return

	_to_client.append({"method": method, "payload": payload})


func _on_client_send(method: StringName, _peer_id: int, payload: PackedByteArray) -> void:
	_to_server.append({"method": method, "payload": payload})


func _flush() -> void:
	var to_client := _to_client.duplicate()
	var to_server := _to_server.duplicate()
	_to_client.clear()
	_to_server.clear()

	for entry in to_client:
		_client_bridge.link.deliver(entry["method"], 1, entry["payload"])

	for entry in to_server:
		_server_bridge.link.deliver(entry["method"], CLIENT_PEER, entry["payload"])


## A request and its answer: the answer is queued during the first flush and delivered by
## the second.
func _exchange() -> void:
	_flush()
	_flush()


## One tick on both ends, with a real physics frame between them.
##
## [b]The awaited physics frame is not padding.[/b] Everything the cannon throws is a
## [RigidBody3D], and a rigid body is integrated by Godot's physics server on the physics
## frame and by nothing else. A suite that drove ticks in a tight loop would move no prop at
## all: the server's would stay exactly where they were put, the client's copies would match
## exactly, and every assertion about replication would pass without anything having been
## replicated.
func _step(command: DotFpsCommand = null) -> void:
	_tick += 1
	var _ticks := _client_net.clock.advance(1.0 / float(maxi(_client_game.tick_rate, 1)))
	_server_bridge.server_tick(_tick)
	_flush()
	_client_bridge.client_tick(
		_tick + INPUT_LEAD, command if command != null else DotFpsCommand.new()
	)
	_flush()
	await get_tree().physics_frame


func _steps(count: int, command: DotFpsCommand = null) -> void:
	for _i in range(count):
		await _step(command)


## How many times the predictor has had to correct this client.
##
## Off the predictor rather than off [DotNetStats], which counts packets. A correction is
## the number that says whether the two ends are computing the same thing.
func _corrections() -> int:
	if _client_net == null or _client_net.predictor == null:
		return 0

	# [b]The published rate, not a private counter.[/b] `_corrections` is the predictor's own
	# book-keeping and a suite that reached into it would be asserting about an
	# implementation. `correction_rate()` is what the addon offers, and it is the number that
	# says whether the two ends are computing the same thing.
	return int(round(_client_net.predictor.correction_rate() * 1000.0))


static func _reader(bytes: PackedByteArray) -> DotNetReader:
	return DotNetReader.new(bytes)


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
