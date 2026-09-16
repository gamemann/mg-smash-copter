extends Node

const ScArena := preload("sc_arena.gd")
const ScConfig := preload("sc_config.gd")
const ScContent := preload("sc_content.gd")
const ScPlatforms := preload("sc_platforms.gd")
const ScSpecials := preload("sc_specials.gd")

## The thing in the middle of the map, and everything it has thrown.
##
## [b]It aims.[/b] The obvious cannon fires straight up with a random lean and lets the
## arithmetic decide where anything lands, and it is much worse to play against: half the
## shots go nowhere and the other half are unreadable, so a player learns nothing from
## watching one. This one picks a platform, solves the arc that reaches it, and scatters
## the aim by a few metres — which means every shot is a warning a player can read off the
## sky and act on, and missing is still possible.
##
## [b]It also owns everything it fired.[/b] A prop is on a clock from the moment it leaves
## the tube, because the alternative is a map that is a scrapyard by the end of the round —
## and taking one away the moment it stops moving would remove the cover a player just
## earned by surviving it.

const CHANNEL := "sc.cannon"

## Something has left the tube. The client draws a puff; the server decided it.
signal launched(prop_id: StringName, at: Vector3, velocity: Vector3, tier: int)

## Metres per second of sideways drift a shot is given at random, on top of its aim.
##
## Separate from [member ScConfig.cannon_spread], which scatters where it is AIMED. This
## scatters how it flies, so two props aimed at the same square do not travel as a pair.
const DRIFT := 1.1

## How fast a prop is spinning when it leaves, in radians per second.
##
## [b]Not zero, and it is most of what makes the arc readable.[/b] A crate that rises and
## falls without turning reads as a sprite; one that tumbles reads as an object with a
## weight, which is the judgement a player has to make about it in about a second.
const TUMBLE := 3.4

@export var config: ScConfig = null

## Where props go. The world's own spawner, not a player's.
var props: DotPropSpawner = null

var platforms: ScPlatforms = null
var arena: ScArena = null

## The stream every one of this cannon's decisions is drawn from.
##
## [b]A named stream rather than the global generator, and it is what makes a round
## reproducible.[/b] Two servers on the same seed fire the same props at the same
## platforms at the same moments, which is what lets a bug report about "the monolith at
## ninety seconds" mean anything.
var stream: DotRandomStream = null

## Seconds until the next shot.
var _cooldown: float = 0.0

## Prop instance id -> seconds it has been in the world.
var _ages: Dictionary = {}

var shots_fired: int = 0
var props_launched: int = 0


func _ready() -> void:
	if config == null:
		config = ScConfig.new()


## Puts the cannon back to the state a round starts in.
##
## [b]Called on a round beginning, and the cooldown is not zero.[/b] A cannon that fired on
## the first tick of a round would land its first prop before anybody had finished being
## teleported onto a platform, which is a death with no decision in it.
func begin_round() -> void:
	_cooldown = maxf(config.cannon_interval, 0.1)
	_ages.clear()
	shots_fired = 0
	props_launched = 0


## One tick. [param elapsed] is how far into the survival phase the round is.
func advance(delta: float, elapsed: float, active: ScSpecials.Active) -> void:
	_age_props(delta)

	if not config.cannon_enabled or props == null or stream == null:
		return

	_cooldown -= delta

	if _cooldown > 0.0:
		return

	_cooldown += maxf(interval_at(elapsed, active), 0.05)
	fire(elapsed, active)


## How long the gap between shots is right now, in seconds.
##
## [b]It closes as the round goes on, and that is what makes surviving to the end
## mean something.[/b] A round whose threat is constant has its last thirty seconds
## identical to its first thirty; ramping the rate means the map a player has learned
## stops being the map they are standing on.
func interval_at(elapsed: float, active: ScSpecials.Active) -> float:
	var progress := clampf(elapsed / maxf(config.survival_seconds, 0.001), 0.0, 1.0)
	var ramp := lerpf(1.0, config.cannon_interval_ramp, progress)

	return config.cannon_interval * ramp * maxf(active.cannon_interval_scale, 0.01)


## How many props one shot puts up right now.
func volley_at(elapsed: float, active: ScSpecials.Active) -> int:
	var progress := clampf(elapsed / maxf(config.survival_seconds, 0.001), 0.0, 1.0)
	var ramp := lerpf(1.0, config.cannon_volley_ramp, progress)
	var wanted := float(config.cannon_volley) * ramp * maxf(active.cannon_volley_scale, 0.0)

	return clampi(int(round(wanted)), 1, 24)


## One shot: a volley of props, each aimed at a platform of its own.
func fire(elapsed: float, active: ScSpecials.Active) -> int:
	var wanted := volley_at(elapsed, active)
	var sent := 0

	for _i in range(wanted):
		if _launch_one(elapsed, active) != null:
			sent += 1

	if sent > 0:
		shots_fired += 1

	return sent


func _launch_one(elapsed: float, active: ScSpecials.Active) -> DotPropInstance:
	if props.world_count() >= config.prop_budget:
		# Silently, and on purpose. The budget is a ceiling on the physics rather than a
		# rule of the game, and an operator who set it low should get a quieter cannon
		# rather than a line of warnings once a second.
		return null

	var tier := _pick_tier(elapsed, active)
	var prop_id := _pick_prop(tier)

	if prop_id == &"":
		return null

	var from := arena.muzzle()
	var target := _pick_target()
	var velocity := solve_arc(from, target, config.cannon_apex, _gravity(active))

	velocity.x += stream.next_range_f(-DRIFT, DRIFT)
	velocity.z += stream.next_range_f(-DRIFT, DRIFT)

	return _put_up(prop_id, from, velocity, tier)


## Drops a prop from a point, with whatever the dropper was doing.
##
## What the chopper's trigger does. It goes through the cannon rather than round it so
## that a dropped crate is on the same clock, counts against the same budget and is
## replicated by the same path as a fired one — three things a second spawn site would
## each have to remember.
func drop(at: Vector3, inherited: Vector3, tier: int) -> DotPropInstance:
	if props == null or stream == null:
		return null

	if props.world_count() >= config.prop_budget:
		return null

	var prop_id := _pick_prop(clampi(tier, 1, ScContent.TIERS))

	if prop_id == &"":
		return null

	return _put_up(prop_id, at, inherited, tier)


func _put_up(
	prop_id: StringName, from: Vector3, velocity: Vector3, tier: int
) -> DotPropInstance:
	var spin := Basis.from_euler(Vector3(
		stream.next_range_f(-PI, PI),
		stream.next_range_f(-PI, PI),
		stream.next_range_f(-PI, PI)
	))

	var prop := props.spawn(prop_id, ScContent.WORLD_OWNER, from, spin)

	if prop == null:
		return null

	var body := prop.body()

	if body != null:
		body.linear_velocity = velocity
		body.angular_velocity = Vector3(
			stream.next_range_f(-TUMBLE, TUMBLE),
			stream.next_range_f(-TUMBLE, TUMBLE),
			stream.next_range_f(-TUMBLE, TUMBLE)
		)

	_ages[prop.instance_id] = 0.0
	props_launched += 1

	launched.emit(prop_id, from, velocity, tier)
	return prop


## The velocity that takes a body from [param from] to [param to] over an arc of
## [param apex] metres.
##
## [b]Solved rather than tuned, because the alternative is a table of angles.[/b] The
## climb is decided by the apex alone, the fall is decided by the height difference, and
## the sideways speed is whatever covers the distance in the time those two take. A cannon
## whose arc was a constant would reach the near platforms and drop short of the far ones,
## and the map's outer columns would be safe for the whole round.
static func solve_arc(from: Vector3, to: Vector3, apex: float, gravity: float) -> Vector3:
	var g := maxf(gravity, 0.01)
	var rise := maxf(apex, 0.5)

	var up := sqrt(2.0 * g * rise)
	var climb := up / g

	# How far it falls from the top of the arc to the target. Negative — a target above
	# the apex — cannot be reached at all, so the drop is floored at nothing and the body
	# arrives on the way up, which is the honest answer rather than a NaN.
	var drop := maxf(from.y + rise - to.y, 0.0)
	var descent := sqrt(2.0 * drop / g)
	var flight := maxf(climb + descent, 0.05)

	var across := Vector3(to.x - from.x, 0.0, to.z - from.z)

	return Vector3(across.x / flight, up, across.z / flight)


## Which tier this shot is allowed to be.
##
## Two gates, and they answer different questions: the clock says which tiers exist yet,
## and the configuration says which the server allows at all.
func _pick_tier(elapsed: float, active: ScSpecials.Active) -> int:
	var ceiling := clampi(config.cannon_max_tier + active.cannon_tier_bonus, 1, ScContent.TIERS)
	var weights := PackedFloat32Array()
	var tiers: Array[int] = []

	for tier in range(1, ScContent.TIERS + 1):
		if tier > ceiling:
			continue

		if elapsed < config.cannon_tier_unlock[tier - 1]:
			continue

		tiers.append(tier)
		weights.append(maxf(config.cannon_tier_weights[tier - 1], 0.0))

	if tiers.is_empty():
		return 1

	var total := 0.0
	for weight in weights:
		total += weight

	if total <= 0.0:
		return tiers[0]

	var index := stream.next_weighted(weights)
	return tiers[clampi(index, 0, tiers.size() - 1)]


## One prop id from a tier, or an empty name if the catalogue has none.
func _pick_prop(tier: int) -> StringName:
	if props == null or props.catalogue == null:
		return &""

	var ids := ScContent.ids_in_tier(props.catalogue, tier)

	if ids.is_empty():
		# Falling back down the tiers rather than refusing: a server that has narrowed
		# its catalogue should get a quieter cannon, not a silent one.
		for lower in range(tier - 1, 0, -1):
			ids = ScContent.ids_in_tier(props.catalogue, lower)

			if not ids.is_empty():
				break

	if ids.is_empty():
		return &""

	return ids[stream.next_range_i(0, ids.size() - 1)]


## Where this shot is going: a platform that is still standing, scattered.
func _pick_target() -> Vector3:
	var standing: Array[int] = []

	if platforms != null:
		for i in range(platforms.count()):
			var deck := platforms.deck_at(i)

			if deck != null and deck.is_standing():
				standing.append(i)

	var at := Vector3.ZERO

	if not standing.is_empty():
		var index: int = standing[stream.next_range_i(0, standing.size() - 1)]
		at = platforms.deck_at(index).centre

	var spread := maxf(config.cannon_spread, 0.0)
	at.x += stream.next_range_f(-spread, spread)
	at.z += stream.next_range_f(-spread, spread)

	return at


func _gravity(active: ScSpecials.Active) -> float:
	return config.gravity * maxf(active.gravity_scale, 0.05)


## Takes away anything that has been in the world too long.
##
## [b]Counted in simulated seconds, advanced by the host, never a wall clock.[/b] A wall
## clock lets a server having a bad second clear the map early, and makes the same round
## replayed twice look different.
func _age_props(delta: float) -> void:
	if props == null:
		return

	var expired: Array[int] = []

	for key: int in _ages:
		var age := float(_ages[key]) + delta
		_ages[key] = age

		if age >= config.prop_life_seconds:
			expired.append(key)

	for instance_id in expired:
		_ages.erase(instance_id)
		props.remove(instance_id, DotPropSpawner.REASON_CLEANUP)


## Forgets a prop that has gone for some other reason: broken, or the round ending.
func forget(instance_id: int) -> void:
	_ages.erase(instance_id)


## How many of this cannon's props are still up.
func live_count() -> int:
	return _ages.size()


func describe() -> Dictionary:
	return {
		"enabled": config.cannon_enabled,
		"shots": shots_fired,
		"launched": props_launched,
		"in_the_world": live_count(),
		"next_in": "%.2f s" % maxf(_cooldown, 0.0),
	}
