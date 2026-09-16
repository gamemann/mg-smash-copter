extends DotGameServices

const ScGame := preload("sc_game.gd")
const ScNetBridge := preload("net/sc_net_bridge.gd")
const ScPlayer := preload("sc_player.gd")

## Chat, voice and moderation, wired to this game's sides.
##
## [b]Seventy lines, because [DotGameServices] holds the other five hundred.[/b] The five
## games written before that base each carry their own copy — 557 to 718 lines, differing in
## the channels, the rules and a voice range. What is left here is what is genuinely this
## game's: who can hear whom, and where somebody is standing.
##
## [b]Proximity is the channel that matters here, and no other game in this family says
## that.[/b] The whole first objective is a field of platforms in open air where everybody
## can see everybody, so the useful conversation is not "my team" — it is the four people on
## the platform next to yours, who are about to be somewhere you can shout at. A range of
## about two platform pitches reaches your neighbours and does not reach the far end of the
## map, which is what makes it a channel rather than a second "all".

# No `const CHANNEL`: [DotGameServices] declares one and GDScript refuses a redeclaration,
# which is the right refusal — one layer, one channel an operator can turn up.

const CH_ALL := &"all"
const CH_TEAM := &"team"
const CH_NEAR := &"near"
const CH_ADMIN := &"admin"
const CH_WHISPER := &"whisper"

## Metres a shout carries. About two platform pitches — see the class documentation.
const PROXIMITY_RANGE := 26.0

## The bridge, for the roster lookup [method _position_of] needs. Set before [method setup].
var bridge: ScNetBridge = null


func _services_name() -> String:
	return "smash-copter"


func _chat_rules() -> Object:
	return chat_rules()


## The same rules, as a static a CLIENT can ask for without building a services layer.
##
## [b]Static because the other end needs them and must not instantiate this.[/b] A services
## layer is a [Node] with a moderation store and a router under it; a client that called
## `new()` on one to read two numbers off it would build all of that, leak it, and — inside
## a delivered pack — fail to compile, because a script whose base class lives in the HOST
## build cannot hand its return type to a script in the mount. Both were measured in
## game-buses-from-hell: seven leaked objects in a suite, and a client scene that would not
## load at all on a real server.
static func chat_rules() -> DotChatRules:
	var rules := DotChatRules.new()
	rules.max_length = 140
	rules.refuse_over_length = false
	rules.allow_newlines = false
	rules.escape_markup = true
	rules.strip_invisible = true
	rules.collapse_whitespace = true
	rules.rate_per_minute = 22
	rules.burst = 4.0
	rules.flood_penalty_sec = 10.0
	rules.duplicate_window_sec = 8.0
	rules.duplicate_depth = 3
	rules.command_prefixes = PackedStringArray(["!", "/"])
	# An unclaimed `!command` is not broadcast: a player typing `!ban` at a server with no
	# such command would otherwise say "!ban" to everybody, which is worse than nothing
	# happening.
	rules.broadcast_unknown_commands = false
	rules.history_limit = 300
	return rules


func _chat_channels() -> Array:
	return chat_channels()


static func chat_channels() -> Array[DotChatChannel]:
	var out: Array[DotChatChannel] = []

	var everyone := DotChatChannel.make(CH_ALL, "All", DotChatChannel.Scope.EVERYONE)
	everyone.colour = Color(0.93, 0.94, 0.96)
	# Short, because a round is a few minutes: a backlog longer than the round is a
	# conversation from a game the new player was not in.
	everyone.backlog = 10
	everyone.history_limit = 200
	out.append(everyone)

	var team := DotChatChannel.make(CH_TEAM, "Team", DotChatChannel.Scope.TEAM)
	team.prefix = "[team]"
	team.colour = Color(0.55, 0.82, 0.95)
	# [b]No backlog, and the showdown is what makes that matter.[/b] A backlog is handed to
	# whoever joins, and a replayed team line in the second half of a round is one side's
	# plan handed to the people it is about.
	team.backlog = 0
	team.history_limit = 120
	out.append(team)

	var near := DotChatChannel.make(CH_NEAR, "Near", DotChatChannel.Scope.RADIUS)
	near.prefix = "[near]"
	near.colour = Color(0.82, 0.86, 0.72)
	near.radius = PROXIMITY_RANGE
	near.backlog = 0
	near.history_limit = 80
	out.append(near)

	var admin := DotChatChannel.make(CH_ADMIN, "Admin", DotChatChannel.Scope.EVERYONE)
	admin.prefix = "[ADMIN]"
	admin.colour = Color(0.98, 0.72, 0.35)
	admin.admin_only = true
	# A gag is about a player's speech; an admin who has been gagged has a bigger problem
	# than chat.
	admin.ignores_gag = true
	admin.backlog = 0
	out.append(admin)

	var whisper := DotChatChannel.make(CH_WHISPER, "Whisper", DotChatChannel.Scope.DIRECT)
	whisper.prefix = "[w]"
	whisper.colour = Color(0.78, 0.71, 0.93)
	whisper.backlog = 0
	out.append(whisper)

	return out


## The voice format, which both ends must agree on exactly.
##
## Static, because the CLIENT builds one too and a sample rate that differs between two peers
## is a stream of packets the router refuses for being the wrong length, counted and said to
## nobody. [method DotVoiceConfig.format_fingerprint] exists for that reason.
static func voice_format() -> DotVoiceConfig:
	var config := DotVoiceConfig.new()
	config.sample_rate = 16000
	config.frame_ms = 20.0
	config.codec_id = &"adpcm"
	# [b]Push to talk, because the survival phase is two minutes of people shouting.[/b] A
	# platform going over under somebody is the single loudest thing that happens to a
	# player, and open-mic voice across a side of six is six people reacting to six different
	# platforms over the one thing anybody needed to hear.
	config.push_to_talk = true
	config.activation_rms = 0.02
	config.hangover_ms = 250.0
	config.jitter_ms = 60.0
	config.jitter_max_ms = 400.0
	config.proximity_range = PROXIMITY_RANGE
	config.max_bytes_per_second = 6144
	return config


func _voice_config() -> Object:
	return voice_format()


## Voice goes to the whole server, and the map is the reason.
##
## game-buses-from-hell defaults to the team because its two sides are the game. Here every
## side is on the same field for the first two minutes with the same problem, and half the
## fun is hearing somebody else find out their platform was already going. Team voice is a
## key away and is what the showdown is played on.
func _voice_default_channel() -> int:
	return DotVoiceRouter.Channel.ALL


## Which side somebody is on, for the team channel and for team voice.
##
## [b]Read off the game rather than cached, because sides change between rounds.[/b] Anything
## holding a team id would put a player in the conversation they were in last round.
func _team_of(peer_id: int) -> int:
	var player := _player_of(peer_id)
	return (game as ScGame).team_of(player.player_id) if player != null else 0


func _position_of(peer_id: int) -> Vector3:
	var player := _player_of(peer_id)

	# [b]The simulated state, not the node.[/b] The node is wherever the last frame drew
	# them, which on an interpolating client is between two ticks; the state is where the
	# tick that is being resolved put them — and a proximity channel resolved against a
	# rendered position is one whose range is a frame's worth of walking out.
	return player.controller.state.position if player != null else Vector3.ZERO


func _player_of(peer_id: int) -> ScPlayer:
	if bridge == null or game == null:
		return null

	var session_id := bridge.player_for_peer(peer_id)

	if session_id == 0:
		return null

	return (game as ScGame).players.get(ScNetBridge.player_key(session_id))


## The team seam dot-chat and dot-voice both ask for, which the base cannot wire.
##
## [DotGameServices] knows nothing about teams — a lobby has none — so the two `team_fn`
## hooks are set here, after the base has built each router.
func setup(p_server: DotServer, p_game: Object, p_link: Object) -> DotResult:
	var ready_now: DotResult = await super.setup(p_server, p_game, p_link)

	if not ready_now.ok:
		return ready_now

	if chat != null:
		chat.set("team_fn", Callable(self, "_team_of"))

	if voice != null:
		voice.set("team_fn", Callable(self, "_team_of"))

	DotLog.info(CHANNEL, "chat, voice and moderation are up for this game", describe())
	return ready_now
