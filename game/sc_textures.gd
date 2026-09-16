extends RefCounted

const ScPaths := preload("sc_paths.gd")

## The prototype textures every surface in this map is drawn with, and the grid that
## stands in when they are missing.
##
## [b]A pattern of a known size is the only thing that tells a player a platform is
## tilting.[/b] That is not decoration in this game, it is the first objective: a flat
## colour under a five-degree lean and a flat colour under no lean are the same picture,
## and a player standing on the second one has no reason to move. A one-metre grid seen
## from eye height at the far end of a 10.5 m platform reads as ten squares that are not
## square any more, which is a tilt somebody can act on.
##
## [b]A role, not a colour.[/b] The map passes "this is a deck" and "this is a pillar";
## what those are drawn as is decided here once. The alternative is a colour per box,
## which means replacing the look is editing every line that builds a box.
##
## The six files are [b]Kenney's Prototype Textures 1.0[/b], CC0 — public domain, no
## attribution required, strictly more permissive than the MIT this repository ships
## under. `textures/prototype/LICENSE.txt` is Kenney's own, copied unchanged. Only the six
## referenced files are vendored; the kit is six colours by thirteen patterns and the rest
## is not needed.

const CHANNEL := "sc.textures"

## What a surface is FOR, which is what decides how it is drawn.
enum Role {
	## The top and sides of a platform. The thing a player stands on and reads a lean off.
	DECK,
	## The single column under a platform. Dark, so a deck reads against it.
	PILLAR,
	## The cannon in the middle. The one colour nothing else in the map wears.
	CANNON,
	## A corner arena, where the round is finished.
	ARENA,
	## Anything that kills: the floor of the map, and the rim of the tube.
	HAZARD,
	## A spawn pad and the chopper's landing square.
	SAFE,
}

## The file each role loads. Dropping a different PNG in is the whole of a re-skin.
##
## [b]`texture_02` from each colour folder, and not `texture_13`, which is the same
## grid.[/b] Kenney's numbering is not the same pattern in every colour folder and several
## of the `texture_13`s have `WALL / 1 x 1 meter / 1024 x 1024` painted into the corner of
## the image. Tiled across a map that is a label repeating every eight metres, and the
## number on it is wrong here anyway. game-g2gfast checked this per file rather than per
## number and wrote down why; this is the same six choices.
const ROLE_FILES := {
	Role.DECK: "deck.png",
	Role.PILLAR: "pillar.png",
	Role.CANNON: "cannon.png",
	Role.ARENA: "arena.png",
	Role.HAZARD: "hazard.png",
	Role.SAFE: "safe.png",
}

## What the generated fallback grid is tinted with, per role, when no set is installed.
const ROLE_COLOURS := {
	Role.DECK: Color(0.74, 0.76, 0.79),
	Role.PILLAR: Color(0.30, 0.31, 0.34),
	Role.CANNON: Color(0.86, 0.48, 0.18),
	Role.ARENA: Color(0.55, 0.43, 0.68),
	Role.HAZARD: Color(0.72, 0.27, 0.26),
	Role.SAFE: Color(0.36, 0.62, 0.38),
}

## How many squares are across one tile of the installed set.
##
## [b]Eight, measured rather than assumed, and the wrong answer was plausible.[/b]
## game-g2gfast measured `ramp.png` and found lines on rows 0, 128, 256, 384, 512, 640,
## 768, 896 and 1023 of 1024 — but they alternate STRONG and FAINT, ninety-seven luma
## steps every 256 pixels and ten every 128, so a threshold picked to ignore compression
## noise finds four and draws every surface at half scale.
const INSTALLED_SQUARES_PER_TILE := 8

## How many squares are across one tile of the generated grid.
const GENERATED_SQUARES_PER_TILE := 4

## How big one square is in the world, in metres.
##
## [b]One metre, and it is the unit this whole map is judged in.[/b] A platform is 10.5
## squares across, the gap between two is one square, and a player who has to decide
## whether a jump is on is counting them.
const METRES_PER_SQUARE := 1.0

## Pixels per square in the generated tile.
const GENERATED_PIXELS_PER_SQUARE := 128

## How much darker an alternate square is in the composited checker.
##
## [b]Ink is the only thing that survives a mipmap, and Kenney's tile has almost
## none.[/b] Measured by game-g2gfast: their tile is a flat field with a one-pixel line on
## a 128-pixel square, so 1.4% to 3.5% of the image is anything but the field colour —
## and a tile that is 97% one colour IS that colour a few metres away. On a platform seen
## from the far end of a 24 m gap, which is the angle this game is played at, the grid is
## simply gone. Alternate squares darkened by six percent are not: a checker is half the
## image, so it survives being averaged.
const CHECKER := 0.93

## How much darker a grid line is in the generated tile.
const LINE := 0.70

## Where a texture set is looked for. A missing directory is a supported state.
static var TEXTURE_DIR := ScPaths.rebase("res://textures/prototype")

## Built materials, by role. One per role for the whole map — a map is a few hundred
## boxes and a material each would be a few hundred shader compilations for one texture.
static var _materials: Dictionary = {}

## Composited installed textures, by role. Null means "looked for it and it is not here".
static var _installed: Dictionary = {}

## The one generated tile, shared by every role and tinted per role.
static var _grid: ImageTexture = null


## The material for a role. Cached; call it per box.
static func surface(role: Role) -> StandardMaterial3D:
	if _materials.has(role):
		return _materials[role]

	var material := StandardMaterial3D.new()
	var texture := installed(role)
	var squares := INSTALLED_SQUARES_PER_TILE

	if texture == null:
		texture = grid_texture()
		squares = GENERATED_SQUARES_PER_TILE
		# The generated tile is greyscale and is multiplied by the role's colour. An
		# installed set brings its own colour and is drawn white, because multiplying
		# Kenney's orange by a role tint is a double tint that produces mud.
		material.albedo_color = ROLE_COLOURS.get(role, Color.WHITE)

	material.albedo_texture = texture

	# [b]World-space triplanar, and without it none of the numbers above mean
	# anything.[/b] A [BoxMesh] maps every face to the same 0..1 square, so a 10.5 m
	# platform and a 1 m crate would show the same number of squares and the pattern would
	# stop carrying scale — which is its entire job here. game-buses-from-hell shipped this
	# flag set with no texture under it and had a comment claiming a readable scale beside
	# a map that was one unbroken tone.
	material.uv1_triplanar = true
	material.uv1_world_triplanar = true

	var metres_per_tile := METRES_PER_SQUARE * float(squares)
	var scale := 1.0 / maxf(metres_per_tile, 0.001)
	material.uv1_scale = Vector3(scale, scale, scale)

	material.roughness = 0.94
	material.metallic = 0.0

	# Nearest, which is a decision rather than a default: a prototype grid is meant to be
	# read as discrete squares at distance, and filtering blurs the lines out at exactly
	# the range a player is judging a platform's lean from.
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS

	_materials[role] = material
	return material


## The installed texture for a role, checkered, or null if no set is installed.
static func installed(role: Role) -> Texture2D:
	if _installed.has(role):
		return _installed[role]

	var path := "%s/%s" % [TEXTURE_DIR, ROLE_FILES.get(role, "deck.png")]

	# [method ResourceLoader.exists] rather than [method FileAccess.file_exists]: an
	# imported texture in an exported build is a `.ctex` beside a `.png` that is not
	# shipped, so asking the filesystem for the source file answers "no" in exactly the
	# build that matters.
	if not ResourceLoader.exists(path, "Texture2D"):
		DotLog.debug(CHANNEL, "no texture installed for a role", {
			"role": Role.keys()[role], "looked_at": path,
		})
		_installed[role] = null
		return null

	var loaded: Resource = ResourceLoader.load(path, "Texture2D")

	if not (loaded is Texture2D):
		_installed[role] = null
		return null

	var checkered := _with_checker(loaded as Texture2D)
	_installed[role] = checkered if checkered != null else loaded as Texture2D
	return _installed[role]


## The installed tile with a checker composited onto it. See [constant CHECKER].
##
## Null when the pixels could not be read, which is not an error — the caller falls back
## to the tile as it came.
static func _with_checker(source: Texture2D) -> ImageTexture:
	var image := source.get_image()

	if image == null or image.is_empty():
		return null

	image = image.duplicate() as Image

	if image.is_compressed():
		# A compressed import cannot be written into. Decompressing is cheap for six
		# 1024-pixel tiles and happens once for the life of the process.
		if image.decompress() != OK:
			return null

	var width := image.get_width()
	var height := image.get_height()

	if width <= 0 or height <= 0:
		return null

	var square_w := maxi(width / INSTALLED_SQUARES_PER_TILE, 1)
	var square_h := maxi(height / INSTALLED_SQUARES_PER_TILE, 1)

	for y in range(height):
		for x in range(width):
			# Alternate squares, which is `(column + row) & 1`. Half the image, which is
			# the point — see [constant CHECKER].
			if ((x / square_w) + (y / square_h)) % 2 == 0:
				continue

			var pixel := image.get_pixel(x, y)
			image.set_pixel(x, y, Color(
				pixel.r * CHECKER, pixel.g * CHECKER, pixel.b * CHECKER, pixel.a
			))

	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## The generated one-metre grid: a line every square, a checker underneath.
##
## [b]What is drawn when no texture set is installed, and it is a supported state.[/b] The
## map is playable and readable with an empty `textures/` directory, which is what lets
## this repository be cloned without the art and what makes removing a file a choice
## rather than a break.
static func grid_texture() -> ImageTexture:
	if _grid != null:
		return _grid

	var side := GENERATED_PIXELS_PER_SQUARE * GENERATED_SQUARES_PER_TILE
	var image := Image.create_empty(side, side, true, Image.FORMAT_RGB8)

	for y in range(side):
		for x in range(side):
			var shade := 1.0
			var column := x / GENERATED_PIXELS_PER_SQUARE
			var row := y / GENERATED_PIXELS_PER_SQUARE

			if (column + row) % 2 == 1:
				shade *= CHECKER

			# Three pixels, because one pixel of ink on a 128-pixel square is 0.8% of the
			# image and a mipmap has eaten it by the second level.
			if x % GENERATED_PIXELS_PER_SQUARE < 3 or y % GENERATED_PIXELS_PER_SQUARE < 3:
				shade *= LINE

			image.set_pixel(x, y, Color(shade, shade, shade))

	image.generate_mipmaps()
	_grid = ImageTexture.create_from_image(image)
	return _grid


## Forgets every cached material and texture. For a test that changes the install.
##
## [b]Not called `reset_state`.[/b] `Resource` already has one and GDScript takes the
## redefinition without a warning, so every call would silently bind to the engine's — a
## trap this family has already paid for once, in `DotRandomTable`.
static func forget_cache() -> void:
	_materials.clear()
	_installed.clear()
	_grid = null


static func describe() -> Dictionary:
	var installed_count := 0

	for role in ROLE_FILES:
		if installed(role) != null:
			installed_count += 1

	return {
		"directory": TEXTURE_DIR,
		"installed": "%d of %d roles" % [installed_count, ROLE_FILES.size()],
		"metres_per_square": METRES_PER_SQUARE,
	}
