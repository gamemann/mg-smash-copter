extends Node3D

const ScConfig := preload("sc_config.gd")
const ScTextures := preload("sc_textures.gd")

## Everything in the world that is not a platform: the sky, the floor a player lands on,
## the tube in the middle, and the corners the round is finished in.
##
## [b]Built in code and prototype-textured, like every other map in this family.[/b] There
## is no art here and there does not need to be — the whole of this game's geometry is a
## grid of squares, a cylinder and a ring of pads, and what a player has to read off it is
## height, distance and which way the floor is tilting. A one-metre grid is better at all
## three than a texture would be.
##
## [b]The floor is drawn even though nobody survives touching it.[/b] Forty metres of
## nothing under a platform is a drop a player cannot judge; forty metres of grid going
## past is a drop they can count. It is also the only thing on screen that tells somebody
## who has just fallen that they are falling rather than that the game has stopped.

const CHANNEL := "sc.arena"

## Metres of floor beyond the outermost platform, so the map has a horizon.
const FLOOR_MARGIN := 46.0

## How tall the tube in the middle is, as a fraction of the deck height.
##
## Below one on purpose: the muzzle is under the platforms, so a prop leaves the tube,
## climbs past the decks and comes down on them. A tube that finished above the decks
## would be a wall down the middle of the map.
const TUBE_HEIGHT_FRACTION := 0.86

## The tube's radius, in metres. Wide enough to read as a mouth from across the map.
const TUBE_RADIUS := 3.1

## Metres above the top of the tube that a prop is actually created at.
##
## [b]Clear of the rim, and the first version was not.[/b] A body spawned overlapping the
## tube's own collider is two solid shapes sharing a volume, which the solver resolves by
## throwing the lighter one sideways at a speed nothing asked for — so every third shot
## went out flat instead of up and the cannon read as broken.
const MUZZLE_CLEARANCE := 2.6

## How wide a catwalk between a corner pad and the middle of the showdown ring is.
const CATWALK_WIDTH := 3.4

## How high the lip around a corner pad and the ring is.
##
## [b]Low, and it is not a wall.[/b] Falling is this map's one rule and it stays true in
## the showdown; what a lip stops is sliding off something you were not looking at, which
## is a death nobody chose. It is a kerb, not cover.
const CORNER_LIP := 0.34

## How wide the band around a pad's edge is, in metres.
##
## [b]The same answer the platforms reached, for the same reason, on the half of the map
## where being wrong is permanent.[/b] A pad sixty metres up against a flat sky has no
## horizon behind it and no neighbour beside it, so its edge seen from a standing player's
## eye height is a line one pixel thick against a background the same brightness. The
## platforms got a coloured band for this; the showdown was built without one because the
## screenshot that would have shown it was taken from above.
const PAD_BAND := 0.6
const LIP_HEIGHT := 0.55

@export var config: ScConfig = null

## The collision layout everything here is classified against.
var physics: DotPhysicsLayout = null

## Where the showdown happens. Built once and left standing, because it is visible from
## the platforms and a player who can see where the round ends plays the first half
## differently.
var _showdown: Node3D = null

var _floor_body: StaticBody3D = null


func _ready() -> void:
	if config == null:
		config = ScConfig.new()


## Lays the world out. Called again every round, which is why it clears first.
func build() -> void:
	_clear()
	_build_light()
	_build_floor()
	_build_tube()
	_build_showdown()

	DotLog.info(CHANNEL, "the arena is up", describe())


## Out of the tree at once, freed at the end of the frame. See [method ScPlatforms.clear]
## for why neither half of that is enough on its own.
func _clear() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_showdown = null
	_floor_body = null


# --- The sky ----------------------------------------------------------------

## The sun and the sky.
##
## [b]Built here rather than left to the host scene, and the first render of
## game-buses-from-hell is why.[/b] A Godot scene with no [DirectionalLight3D] and no
## [WorldEnvironment] is not dark — it is FLAT: every surface comes back its own albedo
## with no shading at all, so a deck, the pillar under it and the sky behind it are three
## tones of the same colour and the depth a player judges a forty-metre drop by is simply
## absent. It reads as a fog bug and is the absence of any lighting whatsoever.
##
## Not dot-lighting: that addon reads a document off imported map data and this map has no
## data, because it is built in code. One sun and one sky is what a document would have
## produced anyway.
func _build_light() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	# High and a little to one side. Low sun over a field of platforms puts every deck in
	# the shadow of its neighbour, and a deck a player cannot see the tilt of is a deck
	# they cannot play on — which is the one thing this map's lighting has to protect.
	sun.rotation = Vector3(deg_to_rad(-56.0), deg_to_rad(38.0), 0.0)
	# [b]Measured against a rendered frame, not chosen.[/b] At 1.05 with an ambient of 0.42
	# and a filmic curve, every surface in this map came back within a few percent of white:
	# the platforms, the pillars and the floor were three shades of the same nothing and the
	# prototype grid — the one thing a player reads a tilt off — was gone. This game renders
	# under `gl_compatibility` because the browser is the client shell's target, and
	# game-buses-from-hell found out the same way that a scene lit for Forward+ is blown out
	# there with nothing reporting it.
	sun.light_energy = 0.82
	sun.light_color = Color(1.0, 0.97, 0.91)
	sun.shadow_enabled = true
	add_child(sun)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY

	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color(0.29, 0.45, 0.72)
	material.sky_horizon_color = Color(0.71, 0.78, 0.86)
	material.ground_bottom_color = Color(0.22, 0.24, 0.29)
	material.ground_horizon_color = Color(0.62, 0.66, 0.72)
	sky.sky_material = material
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	# Higher than a ground-level map wants and lower than it was. Everything here is seen
	# from above or from below, and the underside of a platform lit only by a sun overhead is
	# black — which on the one surface a falling player is looking at is the wrong answer. At
	# 0.42 it was the other failure: no surface had any shading left at all.
	env.ambient_light_energy = 0.34

	# Filmic rather than Godot's default, which is not a tone map at all — it is a clip.
	# game-g2gfast measured the difference over imported maps and it is the single largest
	# change for the cost.
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.62

	# Enough to put the far end of the map behind some air, and far enough out that
	# nothing a player has to react to is hidden in it. A prop arriving out of fog is a
	# prop nobody could have moved away from.
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.76, 0.84)
	env.fog_density = 0.0014

	var world_env := WorldEnvironment.new()
	world_env.name = "Environment"
	world_env.environment = env
	add_child(world_env)


# --- The floor --------------------------------------------------------------

func _build_floor() -> void:
	var reach := _field_reach() + FLOOR_MARGIN

	var body := StaticBody3D.new()
	body.name = "Floor"
	body.position = Vector3(0.0, config.kill_height - 1.0, 0.0)

	var shape := BoxShape3D.new()
	shape.size = Vector3(reach * 2.0, 2.0, reach * 2.0)

	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	body.add_child(collider)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	# [b]Dark, and the first render is why.[/b] The floor was the hazard colour, on the
	# reasoning that it is the one surface nobody survives — and it came out as four hundred
	# metres of bright red filling ninety percent of every frame, with the platforms a player
	# actually has to read reduced to pale specks on top of it. The thing that says "do not
	# go there" is the drop, which is forty metres of nothing; the floor's job is to be far
	# away and to carry a grid so the drop can be counted.
	mesh.material_override = ScTextures.surface(ScTextures.Role.PILLAR)
	body.add_child(mesh)

	_classify(body, &"world")
	add_child(body)
	_floor_body = body


## How far the platform field reaches from the middle, in metres.
##
## [b]The field alone, and [method showdown_centre] is placed from it.[/b] A reach that
## included the showdown would be a definition that chases itself: the arena is put a reach
## away, which makes the reach bigger, which moves the arena.
func _field_reach() -> float:
	var across := float(config.columns - 1) * config.column_pitch * 0.5 + config.platform_size
	var deep := float(config.rows - 1) * config.row_pitch * 0.5 + config.platform_size
	return maxf(across, deep)


## How far the floor has to reach to be under everything, in metres.
func _map_reach() -> float:
	var showdown := showdown_centre()
	var to_showdown := Vector2(showdown.x, showdown.z).length() \
		+ config.corner_distance + config.corner_size
	return maxf(_field_reach(), to_showdown)


# --- The cannon's tube ------------------------------------------------------

## Where a launched prop leaves from.
##
## [b]One number, and the tube, the cannon and the client's copy all read it.[/b] This
## family has shipped the same figure in two files before and watched them drift; a muzzle
## in one place and a mouth drawn in another is a cannon that visibly fires from nowhere.
func muzzle() -> Vector3:
	return Vector3(0.0, config.deck_height * TUBE_HEIGHT_FRACTION + MUZZLE_CLEARANCE, 0.0)


func _build_tube() -> void:
	var height := config.deck_height * TUBE_HEIGHT_FRACTION

	var body := StaticBody3D.new()
	body.name = "Tube"
	body.position = Vector3(0.0, height * 0.5, 0.0)

	var shape := CylinderShape3D.new()
	shape.radius = TUBE_RADIUS
	shape.height = height

	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	body.add_child(collider)

	var column := CylinderMesh.new()
	column.top_radius = TUBE_RADIUS
	column.bottom_radius = TUBE_RADIUS * 1.35
	column.height = height
	column.radial_segments = 16

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = column
	mesh.material_override = ScTextures.surface(ScTextures.Role.CANNON)
	body.add_child(mesh)

	_classify(body, &"world")
	add_child(body)

	# A collar at the mouth, mesh only. It is what makes the tube read as a barrel rather
	# than as a pillar somebody forgot to put a platform on — and it carries no collider
	# deliberately, because a lip at the one height props pass through is a lip that
	# catches them.
	var collar := MeshInstance3D.new()
	collar.name = "Collar"
	var ring := CylinderMesh.new()
	ring.top_radius = TUBE_RADIUS * 1.5
	ring.bottom_radius = TUBE_RADIUS * 1.5
	ring.height = 1.1
	ring.radial_segments = 16
	collar.mesh = ring
	collar.position = Vector3(0.0, height - 0.55, 0.0)
	collar.material_override = ScTextures.surface(ScTextures.Role.HAZARD)
	add_child(collar)


# --- The corners ------------------------------------------------------------

## Where the showdown happens: a structure in the sky, well clear of the platform field.
##
## [b]Off to one side rather than over the middle, and the suite found out why.[/b] The
## first version put the ring on the map's own centre line at a few metres above the decks
## — which is exactly where the cannon's tube is, where the cannon's arc passes, and where
## a chopper parks. A machine spawned on its pad came up inside the underside of the ring
## and sat there pinned, holding perfectly level and refusing to climb, with every number
## about it correct. It reads as a broken helicopter and is two pieces of geometry sharing
## a volume.
##
## So the whole complex is moved a map's width away along -Z. It is still in plain sight
## from every platform — which is the point, because a player who can see where the round
## ends plays the first half differently — and nothing this game fires, flies or drops can
## reach it.
func showdown_centre() -> Vector3:
	return Vector3(
		0.0,
		config.deck_height + config.corner_rise,
		-(_field_reach() + config.corner_distance * 1.6)
	)


## Where team [param index] of [param count] finishes the round, on the pad's surface.
##
## [b]Evenly around a circle, starting at +X, so two teams are at opposite ends.[/b] That
## is the arrangement the map this game is built from uses for its own two-sided finish,
## and it is the only one where the number of teams does not change what a corner means.
func corner_point(index: int, count: int) -> Vector3:
	var teams := maxi(count, 1)
	var angle := TAU * float(index) / float(teams)
	var centre := showdown_centre()

	return Vector3(
		centre.x + cos(angle) * config.corner_distance,
		centre.y,
		centre.z + sin(angle) * config.corner_distance
	)


## Where one player stands when they arrive in a corner.
##
## Spread along the pad's inner edge rather than stacked on its middle: sixteen capsules
## at one coordinate is dot-spawn's own documented failure, and it happens here every time
## a full team survives.
func showdown_spawn(team_index: int, team_count: int, slot: int, slots: int) -> Vector3:
	var centre := corner_point(team_index, team_count)
	var middle := showdown_centre()
	var inward := Vector3(middle.x - centre.x, 0.0, middle.z - centre.z).normalized()

	if inward.length() < 0.001:
		inward = Vector3.FORWARD

	var across := Vector3(-inward.z, 0.0, inward.x)
	var spread := config.corner_size * 0.6
	var places := maxi(slots, 1)
	var offset := 0.0

	if places > 1:
		offset = -spread * 0.5 + spread * float(slot) / float(places - 1)

	return centre + across * offset - inward * config.corner_size * 0.25 + Vector3.UP * 1.2


## Which way a player faces when they arrive: toward the middle, in degrees.
##
## [b]Degrees, because that is what [DotFpsState.yaw] is in, and the two disagree
## everywhere in this family.[/b] `DotSpawnSite.yaw` is radians and the motor's forward is
## `(-sin y, 0, -cos y)`, so facing a direction is `atan2(-dx, -dz)` and not `atan2(dz,
## dx)`. A teleport that gets the position right and the yaw wrong is invisible to every
## count and obvious to every player, who arrives looking at a wall.
func showdown_yaw(team_index: int, team_count: int) -> float:
	var centre := corner_point(team_index, team_count)
	var middle := showdown_centre()
	var inward := Vector3(middle.x - centre.x, 0.0, middle.z - centre.z)

	if inward.length() < 0.001:
		return 0.0

	return rad_to_deg(atan2(-inward.x, -inward.z))


## The pads, the ring and the catwalks between them.
##
## [b]Connected, and a ring of separate pads would not be a fight.[/b] Six teams put in
## six corners with nothing between them is six people looking at each other across sixty
## metres of air until the clock runs out. The ring in the middle is the thing worth
## taking and the catwalks are the only way to it, so the showdown has a shape: hold your
## pad and shoot, or commit to the walk and close.
func _build_showdown() -> void:
	_showdown = Node3D.new()
	_showdown.name = "Showdown"
	add_child(_showdown)

	var middle := showdown_centre()
	var ring_radius := config.corner_size * 0.85

	_pad(
		"Ring",
		middle,
		Vector2(ring_radius * 2.0, ring_radius * 2.0),
		ScTextures.Role.ARENA
	)

	for index in range(config.team_count):
		var centre := corner_point(index, config.team_count)

		_pad(
			"Pad%d" % index,
			centre,
			Vector2(config.corner_size, config.corner_size),
			ScTextures.Role.SAFE
		)

		# The catwalk, from the pad's inner edge to the ring's rim. Solved from the two
		# radii rather than placed by eye: a walkway that stops short of either end is a
		# gap a player falls into on their first step, and one that overlaps is a seam a
		# sliding body catches on.
		var outward := Vector3(centre.x - middle.x, 0.0, centre.z - middle.z)

		if outward.length() < 0.001:
			continue

		outward = outward.normalized()

		var start := config.corner_distance - config.corner_size * 0.5
		var length := maxf(start - ring_radius, 0.5)
		var at := middle + outward * (ring_radius + length * 0.5)

		var walk := _pad(
			"Catwalk%d" % index,
			Vector3(at.x, middle.y, at.z),
			Vector2(CATWALK_WIDTH, length),
			ScTextures.Role.ARENA,
			false
		)
		walk.rotation = Vector3(0.0, atan2(outward.x, outward.z), 0.0)


## One flat surface with a kerb around it.
func _pad(
	node_name: String, at: Vector3, size: Vector2, role: ScTextures.Role,
	ends: bool = true
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = at

	var thickness := 0.7

	var shape := BoxShape3D.new()
	shape.size = Vector3(size.x, thickness, size.y)

	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	collider.shape = shape
	collider.position = Vector3(0.0, -thickness * 0.5, 0.0)
	body.add_child(collider)

	var mesh := MeshInstance3D.new()
	mesh.name = "Mesh"
	var box := BoxMesh.new()
	box.size = shape.size
	mesh.mesh = box
	mesh.position = collider.position
	mesh.material_override = ScTextures.surface(role)
	body.add_child(mesh)

	_build_kerb(body, size, ends)

	_classify(body, &"world")
	_showdown.add_child(body)
	return body


## The kerb this function's own name has promised since it was written.
##
## [b]It was documented in two places and built in neither.[/b] [constant CORNER_LIP] had a
## doc comment explaining why the lip is low and is not cover, `_pad` was described as "one
## flat surface with a kerb around it", and no line anywhere put one in the world — which is
## the same shape of gap as a value produced correctly and consumed by nothing, and just as
## invisible to a suite. A render of the showdown is what found it: three flat shapes
## floating against a flat sky with no edge on any of them.
##
## Two things, and they do different jobs. The BAND is drawn a hair proud of the surface
## with no collider, so an edge seen almost edge-on is still a line — that is the fix the
## platforms already have. The KERB is a real collider standing on the band, low enough to
## walk over deliberately and high enough to stop a body sliding off something its owner was
## not looking at. Falling stays this map's one rule; what a kerb removes is the death
## nobody chose.
## [param ends] is false for a catwalk, and that is not a detail.
##
## A catwalk's two SHORT edges are its junctions with the pad at one end and the ring at the
## other, so a kerb there is a step across the walkway rather than a rail beside it — a third
## of a metre high, at the exact moment a player is running for cover. It cost nothing to see
## in a render and would have been very hard to read as a bug from inside the game: a body
## that catches on it reads as the movement code being wrong.
func _build_kerb(body: StaticBody3D, size: Vector2, ends: bool = true) -> void:
	var material := ScTextures.surface(ScTextures.Role.CANNON)

	var edges: Array[Vector3] = [
		Vector3(0.0, 0.0, size.y * 0.5 - PAD_BAND * 0.5),
		Vector3(0.0, 0.0, -size.y * 0.5 + PAD_BAND * 0.5),
		Vector3(size.x * 0.5 - PAD_BAND * 0.5, 0.0, 0.0),
		Vector3(-size.x * 0.5 + PAD_BAND * 0.5, 0.0, 0.0),
	]

	for i in range(edges.size()):
		if not ends and i < 2:
			continue

		var along_x := i >= 2
		var span := Vector3(
			PAD_BAND if along_x else size.x,
			CORNER_LIP,
			size.y if along_x else PAD_BAND
		)

		var mesh := MeshInstance3D.new()
		mesh.name = "Kerb%d" % i
		var box := BoxMesh.new()
		box.size = span
		mesh.mesh = box
		# The pad's own surface is y = 0 on the body and the slab hangs below it, so the
		# kerb sits on top with its own middle half a lip up. Measuring from the mesh's
		# centre instead is what made the platforms' first rim invisible.
		mesh.position = edges[i] + Vector3(0.0, CORNER_LIP * 0.5, 0.0)
		mesh.material_override = material
		body.add_child(mesh)

		var shape := BoxShape3D.new()
		shape.size = span

		var collider := CollisionShape3D.new()
		collider.name = "KerbHit%d" % i
		collider.shape = shape
		collider.position = mesh.position
		body.add_child(collider)


# --- Where a chopper waits --------------------------------------------------

## Where chopper [param index] of [param count] is parked at the start of a round.
##
## Above the middle of the map and off to one side, so taking one is a decision made in
## the open: everybody on the platforms can see who is walking toward it.
func chopper_pad(index: int, count: int) -> Vector3:
	var places := maxi(count, 1)
	var angle := TAU * float(index) / float(places) + PI * 0.25
	var reach := float(config.columns - 1) * config.column_pitch * 0.32

	return Vector3(
		cos(angle) * reach,
		config.deck_height + config.chopper_pad_height,
		sin(angle) * reach
	)


# --- Helpers ----------------------------------------------------------------

func _classify(body: Node, layer_id: StringName) -> void:
	if physics == null:
		return

	var applied := physics.apply_to(body, layer_id)

	if not applied.ok:
		DotLog.warn(CHANNEL, "a body could not be put on its collision layer", {
			"body": body.name, "layer": String(layer_id), "why": applied.error.message,
		})


## Whether a point has fallen out of the world.
func is_below_the_map(at: Vector3) -> bool:
	return at.y <= config.kill_height


func describe() -> Dictionary:
	return {
		"reach": "%.0f m" % _map_reach(),
		"muzzle": "%.0f m" % muzzle().y,
		"corners": config.team_count,
		"corner_at": "%.0f m" % config.corner_distance,
		"floor": "%.1f m" % config.kill_height,
	}
