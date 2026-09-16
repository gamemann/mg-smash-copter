extends RigidBody3D

const ScTextures := preload("../game/sc_textures.gd")

## The chopper, built out of boxes and cylinders in code.
##
## [b]There is no helicopter in the art this game vendors, and that is the honest reason
## this is geometry rather than a model.[/b] Kenney's kits have a garbage truck, a
## tractor and eighteen blasters and no aircraft of any kind; the alternatives were to
## ship a machine that looks like a van or to draw one. Every other map surface in this
## game is already a prototype-textured primitive, so a chopper made of the same three
## shapes is the one that does not look borrowed.
##
## [b]The rotor is the only thing that moves and it is the only thing that matters.[/b] A
## helicopter with a still rotor reads as a wreck; one with a turning rotor reads as a
## machine somebody is flying, from any distance and at any angle, which on a map where it
## is usually a silhouette forty metres up is the whole of its presentation.

const CHANNEL := "sc.copter.body"

## Metres. The hull a player and the world collide with.
const HULL := Vector3(2.2, 1.8, 5.0)

## The rotor disc's radius, which is most of what anybody sees.
const ROTOR_RADIUS := 4.1

## Radians a second at rest, and at full tilt. It never stops: a parked chopper is idling.
const ROTOR_IDLE := 7.0
const ROTOR_FLYING := 46.0

var _rotor: Node3D = null
var _tail_rotor: Node3D = null

## How fast the disc is turning right now, so it spins up and down rather than snapping.
var _rotor_speed: float = ROTOR_IDLE


func _ready() -> void:
	_build_collision()
	_build_hull()
	_build_tail()
	_build_skids()
	_build_rotors()
	_build_seats()


func _build_collision() -> void:
	# [b]One box, and the tail is deliberately outside it.[/b] A collider that followed
	# the silhouette would put a two-metre boom behind the machine that catches on every
	# platform edge it backs over — and a pilot cannot see it. dot-props documents the same
	# choice from the other end: the art is a shape and the physics is a primitive.
	var collider := CollisionShape3D.new()
	collider.name = "Collision"
	var box := BoxShape3D.new()
	box.size = HULL
	collider.shape = box
	add_child(collider)


func _build_hull() -> void:
	_box("Hull", Vector3(0.0, 0.0, 0.0), HULL, ScTextures.Role.SAFE)
	# A cockpit block, narrower and set forward, so the machine has a nose. -Z is forward.
	_box("Nose", Vector3(0.0, 0.1, -2.9), Vector3(1.5, 1.2, 1.4), ScTextures.Role.CANNON)


func _build_tail() -> void:
	_box("Boom", Vector3(0.0, 0.35, 3.6), Vector3(0.5, 0.5, 3.0), ScTextures.Role.SAFE)
	_box("Fin", Vector3(0.0, 1.05, 4.9), Vector3(0.18, 1.2, 0.9), ScTextures.Role.CANNON)


func _build_skids() -> void:
	for side in [-1.0, 1.0]:
		_box(
			"Skid%s" % ("L" if side < 0.0 else "R"),
			Vector3(side * 0.95, -1.15, 0.0),
			Vector3(0.18, 0.18, 4.0),
			ScTextures.Role.PILLAR
		)
		_box(
			"Strut%s" % ("L" if side < 0.0 else "R"),
			Vector3(side * 0.7, -0.6, 0.0),
			Vector3(0.16, 0.9, 0.16),
			ScTextures.Role.PILLAR
		)


func _build_rotors() -> void:
	_rotor = Node3D.new()
	_rotor.name = "Rotor"
	_rotor.position = Vector3(0.0, 1.25, 0.0)
	add_child(_rotor)

	var mast := MeshInstance3D.new()
	mast.name = "Mast"
	var column := CylinderMesh.new()
	column.top_radius = 0.16
	column.bottom_radius = 0.16
	column.height = 0.5
	column.radial_segments = 8
	mast.mesh = column
	mast.position = Vector3(0.0, -0.25, 0.0)
	mast.material_override = ScTextures.surface(ScTextures.Role.PILLAR)
	_rotor.add_child(mast)

	# Four blades rather than two, because at speed a two-blade disc strobes badly against
	# a frame rate and reads as a rotor that has stopped — which is the one impression this
	# machine must never give.
	for i in range(4):
		var blade := MeshInstance3D.new()
		blade.name = "Blade%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 0.06, ROTOR_RADIUS)
		blade.mesh = box
		blade.position = Vector3(0.0, 0.0, 0.0)
		blade.rotation = Vector3(0.0, TAU * float(i) / 4.0, 0.0)
		# Offset along its own length, which is what `transform` after `rotation` gives:
		# the blade runs from the mast outward rather than through it.
		blade.transform.origin = blade.transform.basis * Vector3(0.0, 0.0, ROTOR_RADIUS * 0.5)
		blade.material_override = ScTextures.surface(ScTextures.Role.HAZARD)
		_rotor.add_child(blade)

	_tail_rotor = Node3D.new()
	_tail_rotor.name = "TailRotor"
	_tail_rotor.position = Vector3(0.22, 1.05, 4.9)
	add_child(_tail_rotor)

	for i in range(2):
		var blade := MeshInstance3D.new()
		blade.name = "TailBlade%d" % i
		var box := BoxMesh.new()
		box.size = Vector3(0.06, 1.5, 0.16)
		blade.mesh = box
		blade.rotation = Vector3(TAU * float(i) / 4.0, 0.0, 0.0)
		blade.material_override = ScTextures.surface(ScTextures.Role.HAZARD)
		_tail_rotor.add_child(blade)


## Where a rider is put. [DotVehicleSeat.attach_path] names these by node path.
func _build_seats() -> void:
	var pilot := Marker3D.new()
	pilot.name = "PilotSeat"
	pilot.position = Vector3(-0.55, 0.25, -1.4)
	add_child(pilot)

	var rider := Marker3D.new()
	rider.name = "RiderSeat"
	rider.position = Vector3(0.55, 0.25, -1.4)
	add_child(rider)

	# Where a dropped prop leaves from: under the belly, clear of the skids, so it does
	# not land on the machine that dropped it.
	var bay := Marker3D.new()
	bay.name = "DropBay"
	bay.position = Vector3(0.0, -2.2, 0.0)
	add_child(bay)


func _box(node_name: String, at: Vector3, size: Vector3, role: ScTextures.Role) -> void:
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	mesh.material_override = ScTextures.surface(role)
	add_child(mesh)


## Turns the rotors. Presentation only, on render frames, and it writes nothing.
##
## [b]A render frame and not a tick, which is the line every game in this family draws in
## the same place.[/b] A rotor spun on the simulation tick turns in visible steps at 64 Hz
## on a 144 Hz screen; one spun on the frame is smooth and is identical on a machine that
## has switched it off. Nothing the simulation reads is touched here, so a player with the
## effect disabled simulates the same round as everybody else.
func _process(delta: float) -> void:
	var wanted := ROTOR_IDLE

	if not freeze:
		# Spun up in proportion to how hard the machine is working, measured off what it
		# is doing rather than off a control this node does not see: a mirrored chopper on
		# a client has no command at all and still has to look like it is flying.
		var effort := clampf(linear_velocity.length() / 12.0, 0.0, 1.0)
		wanted = lerpf(ROTOR_IDLE * 2.2, ROTOR_FLYING, effort)

	_rotor_speed = move_toward(_rotor_speed, wanted, 30.0 * delta)

	if _rotor != null:
		_rotor.rotate_y(_rotor_speed * delta)

	if _tail_rotor != null:
		_tail_rotor.rotate_x(_rotor_speed * 1.6 * delta)
