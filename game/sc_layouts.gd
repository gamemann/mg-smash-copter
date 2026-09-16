extends RefCounted

const ScConfig := preload("sc_config.gd")

## What shape the platform field takes this round, as a catalogue of documents.
##
## [b]The same platforms in a different arrangement is a different round to play, and it
## costs nothing.[/b] This map's geometry is a grid of squares on pillars; knocking a
## column out of it, taking the bridges away, or pushing the rows apart changes where a
## player can go and therefore where the cannon can corner them — which is the whole of
## the first objective. A round that always looked the same would be a round players
## solve once.
##
## [b]A document rather than a scene each, for the family's usual reason and one of its
## own.[/b] A layout is six numbers, so the whole catalogue travels in the HELLO as one
## id and a client rebuilds the identical field from it. A layout that was a `.tscn` would
## be content to deliver, to version and to keep in step across two machines, in exchange
## for nothing this cannot express.

const CHANNEL := "sc.layouts"

## Which cells of the grid carry a platform.
enum Gaps {
	## All of them. The full field.
	NONE,
	## Every other cell, offset by row, so no two neighbours touch.
	CHECKER,
	## Only the outer two columns at each end. Two islands and a lot of air.
	ENDS,
	## Everything except the middle. The cannon has nothing close to aim at.
	HOLLOW,
	## Every other column, which leaves a gap on each side of every platform.
	COMBED,
}

## Where the walkways between the rows go.
enum Bridges {
	## None. The rows are two separate worlds for the whole round.
	NONE,
	## At the outermost columns only, which is the shape the original map has.
	OUTER,
	## One at every column.
	ALL,
	## Every other column.
	ALTERNATE,
}

## One arrangement of the field.
class Layout extends RefCounted:
	var id: StringName = &""
	var display_name: String = ""

	## How likely this layout is against the others. See [method pick].
	var weight: float = 10.0

	var gaps: int = Gaps.NONE
	var bridges: int = Bridges.OUTER

	## Whether a chopper is parked on this layout.
	var with_chopper: bool = false

	## What the configured column spacing is multiplied by.
	##
	## Above one is a map of islands with jumps that have to be meant; below one is a map
	## where a collapsing platform takes its neighbour's footing with it.
	var pitch_scale: float = 1.0

	## What the configured platform stiffness is multiplied by.
	##
	## Below one is a wobblier field. It is the one property of a layout a player feels
	## before they can see it, so a layout that uses it says so in its name.
	var stiffness_scale: float = 1.0

	## A line for the HUD when the round begins, so a player knows what they are looking at.
	var blurb: String = ""

	## Every platform this layout puts out, as (column, row, is_bridge).
	##
	## [b]One description, and the field, the spawns, the cannon's target list and the
	## client's copy are all derived from it.[/b] This family has shipped the same list
	## twice and watched the copies drift more than once.
	func cells(config: ScConfig) -> Array[Vector3i]:
		var out: Array[Vector3i] = []

		for row in range(config.rows):
			for column in range(config.columns):
				if _has_platform(column, row, config):
					out.append(Vector3i(column, row, 0))

		# Bridges join row `r` to row `r + 1`, so there is one fewer set of them than
		# there are rows — and none at all on a single-row layout, where there is nothing
		# to join.
		for row in range(config.rows - 1):
			for column in range(config.columns):
				if _has_bridge(column, row, config):
					out.append(Vector3i(column, row, 1))

		return out

	func _has_platform(column: int, row: int, config: ScConfig) -> bool:
		match gaps:
			Gaps.CHECKER:
				return (column + row) % 2 == 0
			Gaps.ENDS:
				return column < 2 or column >= config.columns - 2
			Gaps.HOLLOW:
				# The middle third, rounded so a five-column field loses its centre one.
				var low := config.columns / 3
				var high := config.columns - 1 - config.columns / 3
				return column < low or column > high
			Gaps.COMBED:
				return column % 2 == 0
			_:
				return true

	func _has_bridge(column: int, row: int, config: ScConfig) -> bool:
		# A bridge with nothing at either end of it is a diving board. Both platforms it
		# joins have to be there, or it is left out — which is what makes CHECKER a layout
		# with almost no bridges on it however many it asked for.
		if not _has_platform(column, row, config) or not _has_platform(column, row + 1, config):
			return false

		match bridges:
			Bridges.ALL:
				return true
			Bridges.OUTER:
				return column == 0 or column == config.columns - 1
			Bridges.ALTERNATE:
				return column % 2 == 1
			_:
				return false

	func describe() -> Dictionary:
		return {
			"id": String(id),
			"gaps": Gaps.keys()[gaps],
			"bridges": Bridges.keys()[bridges],
			"chopper": with_chopper,
			"pitch": "%.2f" % pitch_scale,
			"stiffness": "%.2f" % stiffness_scale,
		}


static func _make(
	p_id: StringName,
	p_name: String,
	p_weight: float,
	p_gaps: int,
	p_bridges: int,
	p_blurb: String
) -> Layout:
	var layout := Layout.new()
	layout.id = p_id
	layout.display_name = p_name
	layout.weight = p_weight
	layout.gaps = p_gaps
	layout.bridges = p_bridges
	layout.blurb = p_blurb
	return layout


## Every layout this game can play, in the order they were written.
static func all(config: ScConfig) -> Array[Layout]:
	var out: Array[Layout] = []

	out.append(_make(
		&"full", "Full Deck", 20.0, Gaps.NONE, Bridges.OUTER,
		"Every platform is up. Nowhere is safe and everywhere is reachable."
	))

	var checker := _make(
		&"checker", "Chequerboard", 13.0, Gaps.CHECKER, Bridges.ALL,
		"Half the platforms. Every jump is a diagonal."
	)
	# Widened, because a chequerboard at the ordinary spacing leaves diagonals a player
	# cannot clear and the round becomes a standing contest.
	checker.pitch_scale = 0.88
	out.append(checker)

	var islands := _make(
		&"islands", "Two Islands", 10.0, Gaps.ENDS, Bridges.NONE,
		"Two islands and a lot of air between them. Nobody is crossing."
	)
	islands.pitch_scale = 1.15
	out.append(islands)

	var spine := _make(
		&"spine", "The Spine", 11.0, Gaps.NONE, Bridges.ALL,
		"Bridges everywhere. The walkways are the steady ground and everybody knows it."
	)
	# Steadier, because a map whose safe ground is a bridge wants the platforms either
	# side of it to be the dangerous half rather than both halves at once.
	spine.stiffness_scale = 1.15
	out.append(spine)

	var airfield := _make(
		&"airfield", "Airfield", 13.0, Gaps.NONE, Bridges.OUTER,
		"There is a chopper on the pad. Somebody is going to take it."
	)
	airfield.with_chopper = config.chopper_enabled
	out.append(airfield)

	var gauntlet := _make(
		&"gauntlet", "The Gauntlet", 11.0, Gaps.COMBED, Bridges.NONE,
		"Every platform stands alone, and none of them is holding still."
	)
	gauntlet.pitch_scale = 0.82
	# The wobbly one. Two thirds of the usual spring is a platform that leans under one
	# person walking, which on a layout with no bridges is the whole round.
	gauntlet.stiffness_scale = 0.66
	out.append(gauntlet)

	var broadside := _make(
		&"broadside", "Broadside", 9.0, Gaps.NONE, Bridges.ALTERNATE,
		"Pushed apart, half the bridges, and a chopper over the middle of it."
	)
	broadside.pitch_scale = 1.22
	broadside.with_chopper = config.chopper_enabled
	out.append(broadside)

	var hollow := _make(
		&"hollow", "Hollow Centre", 10.0, Gaps.HOLLOW, Bridges.OUTER,
		"Nothing in the middle. The cannon has to reach for you and it will."
	)
	hollow.stiffness_scale = 0.88
	out.append(hollow)

	return out


## The layout for a round, drawn by weight from [param stream].
##
## [b]Weighted rather than uniform, because the full field is the one a player should see
## most.[/b] A round that is a variant every time has no baseline to be a variant of.
static func pick(config: ScConfig, stream: DotRandomStream) -> Layout:
	var layouts := all(config)

	if not config.vary_layout or layouts.is_empty():
		return layouts[0] if not layouts.is_empty() else _make(
			&"full", "Full Deck", 1.0, Gaps.NONE, Bridges.OUTER, ""
		)

	var weights := PackedFloat32Array()

	for layout in layouts:
		weights.append(maxf(layout.weight, 0.0))

	var index := stream.next_weighted(weights)
	return layouts[clampi(index, 0, layouts.size() - 1)]


## One layout by id, or null. What a console command and the suite use.
static func by_id(config: ScConfig, id: StringName) -> Layout:
	for layout in all(config):
		if layout.id == id:
			return layout

	return null


## Every layout's id, for a console command's completion and for a log line.
static func ids(config: ScConfig) -> PackedStringArray:
	var out := PackedStringArray()

	for layout in all(config):
		out.append(String(layout.id))

	return out
