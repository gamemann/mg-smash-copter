# mg-smash-copter

Stand on a platform balanced on one pillar while a cannon throws things at it. Whoever is still up when the clock stops finishes the round in the sky with a weapon they did not choose.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first, and each addon's own `CLAUDE.md` before working in it. This file is only about what this game decides.

## What this game is, versus the other six

game-arena is a deathmatch, game-g2gfast is a timer server, game-playground is a sandbox, game-hungario is an eating game, game-simple-lobby is a lobby and mg-buses-from-hell is asymmetric. This is the first one whose **primary antagonist is the floor**, and everything below comes from that.

Nothing can hurt anybody for the first two thirds of a round. There is no weapon, no objective to capture and nobody to shoot. The entire first phase is a question about where to stand on something that leans toward you, and the only inputs a player has are where they are and how fast they are moving. Then the clock runs out and it becomes an ordinary team fight — between exactly the people who were good at the first half.

Neither half would be much on its own. What makes the second one work is that the people in it earned their place by not falling over.


## The moderator's live tools, and what a floor game refuses

`ScServices` answers dot-game's `_mod_abilities` with noclip, freeze, speed and gravity (predicted modifiers, so a player an admin moves does not rubber-band), god, buddha, hp, slay and slap as ordinary damage, rename, and teleports that go through `ScPlayer.place_at` — the one way to move a player here that also moves the tick the client draws from. `@team:<n>` is the side.

Blind and beacon are supported — see below. Refused, with the reason `modtools` prints: **respawn**, because falling is how a round is lost and putting a faller back decides it; **give and strip**, because weapons are handed out at the handover, one each at random, and that draw is the second half's fairness. Anything that moves a body is refused while they fly the chopper. A round start is everybody's new body, so it ends a noclip or a freeze and keeps god.

**Blind and beacon were refused as "no client overlay" until 2026-09-24, and are two flags now**, after game-arena's pattern. `ScPlayer.blinded` and `ScPlayer.beacon` are set by the handlers on the server and replicated as per-player state in `ScPlayerNet` — `net_blind` **owner-only**, as the magazine is, because an opponent who could read it would know the moment somebody could not see; `net_beacon` to everybody. State rather than an event, so a joiner, a lost snapshot and a re-laid field are all corrected by the next snapshot. **There is no relevance change**, where game-arena makes a beaconed player always relevant: every player here already is, and a beacon turned off that set the flag back would take the player out of everybody's snapshot. `ScHud.blind_overlay` fades a near-black rect in over a quarter of a second under the HUD's numbers and **hides the tilt bar**, because the bar is the floor under their feet drawn as a number — a blind that left it would leave a player balancing by instrument. **The chat box moved to its own CanvasLayer (layer 2) for this**: it drew in the default canvas, under every CanvasLayer, so the first rendered blind covered the chat too — and a blinded player could not read the line saying an admin had done it. `ScBeacon` (by preload, no `class_name`) is a ring, a once-a-second ripple and a 30 m column drawn through everything except on your own beacon, placed by `ScClient.present_beacons` at the drawn position — the client and never the world, because the world also runs on a dedicated server. **The ping is synthesised in `ScBeacon`**, a falling sine on an `AudioStreamPlayer3D`: when it was written this game had no sound and no audio addon, and a dependency in a delivered pack for one tone would have been a bigger change than the tone. dot-audio is here now (see "Sound" below) and the ping deliberately stays where it is — see there for why. Both persist across a round (`ScServices.PERSIST_ON_RESPAWN`); `blind <p> <seconds>` is dot-moderation's `TIMED_TOGGLES`.

`headless_net` asserts the audience (the client's own player blinded, the stand-in's blind never sent to it, both beacons drawn) over a link dropping one snapshot in three, armed by dropping `to_owner_only()`, which two checks caught; `dedicated` drives both through the console, the timed lift and the persistence (armed by emptying `PERSIST_ON_RESPAWN`); `headless_run` asserts what the client draws — the blind covers the viewport (armed with a top-left, sizeless rect), the ping is once a second (armed by pinging every frame), no column on your own, no marker while out. `tools/shot.sh --view=beacon` and `--view=blind` render both.

`headless_net`'s `SECTIONS` was the same "name that occurs once" as `dedicated`'s below: declared as 14 and compared with nothing. It is compared now.

`dedicated`'s `SECTIONS` was declared as 6 and read by nothing while eight sections ran — the "name that occurs once" detector, on the suite itself. It is compared now, and is 9 with the live-tools section.

## Layout

```
game/
  sc_paths.gd       where this game's own files are, wherever it is mounted
  sc_config.gd      every number, in metres and seconds, layered like every DotConfig
  sc_textures.gd    the six prototype textures, by ROLE, and the grid that stands in
  sc_content.gd     the prop catalogue in four tiers, and the chopper. The design, as data
  sc_layouts.gd     eight arrangements of the field, as documents, and the jumps each means
  sc_specials.gd    nine things that go wrong, as multipliers
  sc_arena.gd       the sky, the floor, the tube and the corners. In code
  sc_platforms.gd   THE FILE. A slab on a pillar, as a spring this integrates
  sc_cannon.gd      what the tube throws, where it aims, and how long it stays
  sc_copter.gd      a fourth kind of vehicle chassis, because neither shipped one flies
  sc_player.gd      one person: movement, the carry, health, weapons
  sc_game.gd        the simulation: phases, loads, impacts, falls, the handover. Headless
  sc_hud.gd         four numbers, a tilt bar, a dot, an admin's blind, and who you are watching
  sc_spectate.gd    where somebody who is out looks: dot-spectate, authoritative or a mirror
  sc_audio.gd       what the game makes a noise about: a dot-audio catalogue and its stand-ins
  sc_progress.gd    what a player keeps: dot-stats numbers and dot-achievements rules over them
  sc_beacon.gd      an admin's beacon: a ring, a ripple, a column and a synthesised ping
  sc_client.gd      one local player, alone or against a server. First person and third
  sc_client_chat.gd the chat box and the microphone
  sc_services.gd    chat, voice and moderation. Seventy lines over dot-game's base
  sc_server.gd      what a DotServer loads as its game scene
  sc_module.gd      what a DotServer loads as its module. A hundred and forty, over dot-game
  sc.tscn           what you run
  net/              the wire: the codec, four behaviours, the link, and the bridge that is
                    the only file naming both halves
props/              eight bodies that build themselves from four exported numbers, and the
                    chopper, which is geometry
assets/kenney/      eight CC0 models and two atlases
assets/{blaster-kit,melee,arms}/  the weapon pack's own art, vendored
textures/prototype/ six CC0 prototype textures, one per role
scenes/             sc_server.tscn, which is all a deployed server instantiates
examples/           headless_run (236), dedicated (70), headless_net (197)
tools/              shot.gd/.tscn/.sh — render a frame and look at it; any --sc-* is config
                    net_shot.gd/.tscn — `shot.sh --view=walk`: a CONNECTED client running,
                    rendered and measured (key to motion, corrections, eye speed per frame)
                    audio_probe.gd/.sh — ask a real audio device whether a speaker moves
```

## Decision 1: a platform is not a rigid body, and it must not be

This is the decision the whole game rests on, so it is the first one.

A slab genuinely balanced on a thin cylinder in Godot's solver is a body in permanent marginal contact. It jitters at rest, what it does is decided by contact-point ordering, and it is **not reproducible across two machines** — which in a game where the platform under your feet is the entire first objective means a client and a server that disagree about whether you are standing on anything. dot-props reaches the same finding from the other end and refuses to predict a crate for it; a crate being a few centimetres out is a cosmetic cost, and a floor being a few centimetres out is a player falling through something their own machine says is holding them up.

So a platform is an `AnimatableBody3D` driven by a torsion spring `ScPlatforms` integrates: a lean, a lean velocity, a sink and a sink velocity. Four floats, a pure function of the loads on it, deterministic, and cheap enough that the server can simply tell every client what it decided rather than ask them to agree.

**Semi-implicit, and explicit Euler is wrong here in a way that takes a while to see.** Advancing the angle from the old velocity adds energy at every step, so a spring that should settle grows instead — a platform that should have stopped wobbling keeps going and eventually throws itself off its own pillar with nobody standing on it. zee-dot-weapons paid for exactly this in its recoil spring.

## Decision 2: shift is a brake

Every other 3D game in this family binds shift to a sprint. Here running is the default and shift is the slow walk, because a platform is destabilised in proportion to how hard the people on it are moving — so the only way to cross a platform somebody is already standing on the far side of is to slow down.

That is one line in `ScPlayer.tunables_for` (`can_sprint = false`, and shift added to the walk action) and one term in the load model (`platform_motion_gain`). It is also the only mechanic in the game that a player discovers by being punished for the thing every other game rewards.

## Decision 3: the tiers are the cannon's whole design

A crate wobbles a platform, a boulder tips it, a container takes a corner off it and a monolith deletes it with everybody standing on it. All four outcomes come out of two numbers on a `DotPropDef` — the mass and the size — through one model in `ScPlatforms`, rather than out of a rule per prop. That is what lets a server retune the feel of a round by editing a document, and what lets the suite assert the design instead of the code.

**The cannon aims, and the obvious cannon does not.** Firing straight up with a random lean is much worse to play against: half the shots go nowhere, the other half are unreadable, and a player learns nothing from watching one. This one picks a platform that is still standing, solves the arc that reaches it, and scatters the aim by a few metres — so every shot is a warning that can be read off the sky and missing is still possible.

## Decision 4: the map is a description, not a build

A round's field is an id, a handful of numbers and a list of cells. A client rebuilds the identical field from them, every platform comes out in the same order, and a snapshot then moves platform number seven without ever saying what a platform is.

**The cell list travels rather than the layout id alone**, and that is a decision about what "agree" means. A client deriving the field from a catalogue of its own would build the right field right up until its build was one layout behind the server's — and then its platform seven would be somewhere else and every snapshot after that would move the wrong floor, silently. Thirty-odd bytes once a round buys the whole class of bug.

## What a level is here, for the nightly quota

Decided 2026-09-23 so every run applies the quota the same way. **A level is a change to where a player can stand or go** — the platform field or the showdown — and it ships with its jumps declared, measured against the movement's reach, driven by a bot and rendered. In order of preference, because extending comes before adding:

1. **An existing layout document in `ScLayouts` rebuilt so it plays the way its own blurb says.** Eight layouts, most of them made of numbers nobody had asked a player to cross; that is where there is room to grow.
2. **A walkable extension of the showdown complex in `ScArena`** — a new piece of the sky a survivor can get to on foot.
3. **A ninth layout, only if it needs something the vocabulary lacks**: a new `Gaps` or `Bridges` shape, or a new number on `Layout` that travels on the wire (`row_pitch_scale` and `row_shift` are the two added for the chequerboard). A ninth row that only recombines existing enums and scales is a variant, not a level.

**Not a level**: a special round (it changes numbers, not where anybody stands), a layout's weight, a cvar default, a prop. Every level declares `Layout.jumps`, passes `headless_run`'s reach and throat sections, gets a section that drives a bot through the property it is about, and is rendered with `tools/shot.sh --view=jump --sc-layout-ids=<id>` (and `--view=field`).

## Reach: a jump here is measured, not sized by eye

`ScPlayer.jump_reach(config, rise)` is the clear air a running player crosses landing `rise` metres higher, and it is `tunables_for(config, active).jump_reach(rise)` — dot-player-controller's `DotFpsTunables.jump_reach`, the descending root times the run speed — so this game keeps no copy of the arithmetic or the constants (moved 2026-09-26, every number identical: 4.34 m flat, 4.04 m onto 0.3 m). **The rise is never zero on this map, and that is the part that is this game's own**: a runner leans the platform toward the edge they are running at, so the lip they leave from has dropped by the time they reach it — about 0.3 m mid-edge and 0.8 m at a corner, against a 1.15 m apex. The suite steps `ScPlatforms`' own model along the run to measure that dip for every route; it is most of the difference between a jump and a wall.

`Layout.jumps` declares which KINDS of jump a layout means (`ALONG_ROWS`, `ACROSS_HOLES`, `ACROSS_ROWS`, `DIAGONALS`), `ScLayouts.pairs()` turns the kinds into pairs off the cell list the field is built from, and `ScPlatforms.clear_air()` measures the air along the line a runner takes. The sweep is **both ways**: a declared jump has to be inside the reach, and an undeclared one has to be outside even a flat running jump, because "Nobody is crossing" and "Every platform stands alone" are promises too. Tightest declared jumps at the ordinary numbers: Two Islands' diagonals, 2.56 m of 2.94; the chequerboard's, 2.83 of 3.24; broadside, 3.41 of 3.95; everything else 1.8 or less.

The showdown is reached by teleport, not by a jump, so its question is whether a survivor can WALK from their pad along a catwalk onto the ring — which is driven, with two sides (square junctions) and three (oblique ones). A parked chopper comes to rest on whatever is under its pad, so every layout with one has to have a platform there. Measured 2026-09-23; the list below has what it found.

## Decision 5: no dot-spawn

Every other 3D game in this family uses it. A spawn point is a fixed place in the world, and **every place in this world is on something that tips, collapses, or is not there this round** — so a `DotSpawnPoint` would be a promise the map cannot keep. The game places its own players: a side to a platform, spread around its middle, facing inward, from the field it has just built.

`DotMatch.spawns_ref` is still set, to the match node itself, so that dot-match never walks the whole scene looking for points that do not exist. Unset it picks up another world's in a process holding a server and a client, and the outgoing map's for the frame after a round change; both are in this family's own bug list.

## The ring has cover, facing the pads (2026-09-26)

**The ring was the most exposed floor in the sky**, while being "the thing worth taking". A survivor who walked onto it stood in every pad's line of fire with nothing between, so the showdown was people holding their pads until the clock ran out. `ScArena.ring_cover()` puts one block per team on the ring, on the line from its middle to that team's catwalk, half-way in and square to it: 2.4 m wide and 1.1 m high (`RING_COVER_SIZE`), so a person crouched behind one is out of that pad's sight and a person standing is shot at over it. Derived from the same corner angles as the catwalks, so any team count gets one per pad.

**Facing the pads, and the first draft did not.** It put the blocks between the catwalks, and the pads stand on the catwalk lines, so every block was end-on to both neighbouring pads and covered nobody. A survivor coming off a catwalk has seven metres of ring before the block and walks round it. The showdown walk stops two metres inside the rim and never reaches one.

`headless_run`'s "the ring has cover, and it faces the pads" asks this with two sides and with three: one block per side, built and on the ring, and from every pad a ray to somebody crouched behind its block hits the block while a ray to somebody standing there hits nothing. Armed by not building the blocks (four checks fail). Rendered with `tools/shot.sh --view=ring` and `--view=showdown`.

## The flanks: the long way round (2026-09-29)

**With cover on the ring, a survivor who took it and crouched behind the block facing an enemy pad could only be reached by somebody walking the same catwalk into them.** `ScArena.flank_walks()` is one description of a second route: a perch (`PERCH_SIZE`, 8 m, the SAFE role) on the pads' own circle half-way round between every two pads, joined to both by a catwalk that never comes near the ring — 43.8 m from its middle at the nearest with two sides, against its corners at 20.4. The pads' kerb openings, the perches, the slabs and the suite all read the same list. With two sides each flank is 87.7 m from pad to perch, from the pad's very corner; with three, 62. A flank leaves a square pad at an angle, so its slab runs half its width into both ends (no notch of air beside the join) and sits `FLANK_DROP` (2 cm) under them, or the two coplanar tops fight over every pixel of the overlap.

**What it is for, with two sides: from either perch the ring's blocks are side-on**, so somebody crouched behind one, hidden from the pad it faces, is in plain sight. With three the perch is 60 degrees off the block and it still covers; that is measured, not promised.

`headless_run`'s "the flanks" section, with two sides and three: a perch per pair of pads and a catwalk to each (kerbed on four sides and two), the kerb open where every flank arrives at both ends (a ray at shin height from each pad's and perch's middle out past the edge), no flank near the ring, and a bot RUN from pad 0 through perch 0 to pad 1: 173.8 m of a 175.4 m route in 27.22 s against 27.40 at 6.40 m/s with two sides, 122.7 of 124.0 in 19.22 s with three, lowest point the 2 cm drop. Then the four lines from both perches to behind both blocks, clear. Armed three ways: the pads' flank openings uncut fails the kerb check (the RUN still passes, because dot-player-controller 2e6d930 throws a runner over a closed kerb, which is why the ray check exists); the slab 0.6 m down fails the drive and the pace (32.1 s, and stuck at the perch with three sides); the perches a quarter of the way round instead of half fails the ring clearance (23.7 m) and the sight lines (2 of 4). Rendered with `tools/shot.sh --view=flank` and `--view=showdown`.

## A catwalk is cut along both edges (2026-09-30)

**Until 2026-09-29 a catwalk was a rectangle measured along its middle**, as if it met the ring and its pad square on. With two or four sides it does; with three a catwalk leaves the square ring at an angle, and the slab ran up to 3.2 m on into the ring, coplanar with it, carrying its kerbs in as stubs on the ring's floor. `ScArena.catwalk(index)` is the description now: each long side ends where it leaves the ring's square (`_line_exit`) and where it meets the pad's, so the slab is a convex prism whose short ends lie along the two edges, and each kerb stops where the band under it meets either edge. `headless_run`'s "a catwalk meets the ring and its pad" reads the BUILT colliders with two, three and four sides: nothing inside the ring or the pad, and a ray 5 cm inside each edge lands on the catwalk right across its width. Armed by the first draft, which ended every side at `ring_half() + 0.3` (0.3 m of air on every side count, three sides still overlapping): 5 of 9 fail. Rendered with `tools/shot.sh --view=junction --sc-team-count=3`.

## Decision 6: the showdown is somewhere else

The corners started directly over the platform field, a few metres above the decks. That put the ring exactly where the cannon's tube is, where the cannon's arc passes, and where a chopper parks — and a machine spawned on its pad came up inside the underside of the ring and sat there pinned, holding perfectly level and refusing to climb, with every number about it correct.

The whole complex is a map's width away along -Z now. It is still in plain sight from every platform, which is the point: a player who can see where the round ends plays the first half differently.

## What running it found

Every one of these was found by running the game or by looking at a picture of it, and not one of them errored.

- **dot-match left two of the three offline stand-ins on no team, so a round ended one stand-in early.** The offline client puts every stand-in on team 2 before the local player joins team 1, and dot-match's `max_difference` defaults to 1 and refuses any join that puts a side two ahead — a rule `force_balance = false` does not reach. `sides` had all three on team 2; dot-match knew about one, and its elimination rule counts survivors off its own teams. `max_difference` is 0 now, since `sides` is what decides a team, and a refused join logs at ERROR instead of being discarded into `_seated`. `headless_run`'s "dot-match puts everybody where the game did" fails without it, naming bot1 and bot2. mg-buses-from-hell had the same line wrong.

- **The platform normal had the wrong sign, so every platform leaned away from whatever was standing on it.** `normal()` returned `(-sin(lean.x), 1, -sin(lean.y))`, which is what it looks like it should be and is backwards: a plane through the pivot with normal `(sin t, cos t, 0)` puts a point at `+x` BELOW the pivot. Every other symptom was correct — it tipped, it collapsed at the right angle, it carried people — in the wrong direction. The suite caught it only because the check was written to measure the SURFACE rather than the state.

- **The bridge held a dozen freed nodes, once a tick, for ever.** A platform's replication behaviour is a child of the platform's own body, so clearing the field frees the behaviours with it — and the bridge's table of replicated bodies was only cleaned up on the REBUILD, which happens after. The dedicated run printed *"Trying to assign invalid previously freed instance"* twenty-three times before anybody noticed what it was. There is a `world_clearing` signal now, and a validity guard in the tick loop as well, because anything that frees a body frees its behaviour.

- **Nobody could be shot.** Players were registered with dot-combat by `DotHealth` and had no `DotHitboxSet` at all, so every bullet in the showdown passed through everybody — and there is no error for it, because a trace that finds nothing is a legitimate answer. The manager's own boot warning about a missing trace backend is what led to it; `combat.trace` was unset too, so shots also went through the arena.

- **A teleport set the yaw and the motor took it straight back.** The motor reads its view from the COMMAND, not from the state, and repeats the last command when it is handed none — so a survivor placed in their corner facing inward was looking due north one tick later. Every position was correct and every facing was wrong. `place_at` applies a command carrying the new angle now.

- **Lag compensation was on with nothing wired to it**, which dot-combat reports at boot and then resolves every shot against the present anyway — a flag reported as enabled with nothing behind it. It is wired now: dot-net already records the history, so the bridge hands over a rewind and a restore and that is the whole of it. The shooter is deliberately not excluded from the rewind, because `resolve_shot` fixes the shot's origin before it rewinds anything.

- **The map came back white.** At a sun energy of 1.05, an ambient of 0.42 and a filmic curve, every surface was within a few percent of white and the prototype grid — the one thing a player reads a tilt off — was simply gone. This game renders under `gl_compatibility` because the browser is the client shell's target, and a scene lit for Forward+ is blown out there with nothing reporting it.

- **The floor was four hundred metres of bright red.** It was sized to reach under the showdown as well as the field, and painted with the hazard role on the reasoning that it is the one surface nobody survives. It filled ninety percent of every frame and reduced the platforms a player actually has to read to pale specks. The thing that says "do not go there" is the drop.

- **A lone player could not tip anything.** At a load gain of 1.0 one person standing on the very edge of a platform leans it 1.1 degrees against a collapse angle of sixteen, and one running across it 3.3 — so the walk key did nothing anybody could feel and the first objective was standing still for two minutes. The equilibrium is `offset * kilos * gain / (inertia * stiffness)`, which is four numbers and was never solved until a screenshot made it obvious. At 1.8 a lone runner leans it six degrees and three of them on one edge take it over.

- **A player could not see the edge they were about to walk off.** Every platform is at the same height, so from eye level the neighbouring ones are edge-on — and with under a metre between them the whole field reads as one continuous floor stretching to the horizon. The grid does not help: it is the same grid on both platforms and it runs straight across the join. There is a band in the cannon's colour around every platform now, mesh only, and it is the single largest readability change in the game. The first attempt at it was invisible because the rim was positioned relative to the slab's middle and the pivot is the SURFACE — and the screenshot that was supposed to prove it looked identical to the one before it, which is its own small lesson about what a picture proves.

- **A player who joined in the middle of a round was never placed**, so they were left where a `CharacterBody3D` starts — the origin, which in this map is forty metres below the platforms and inside the floor that kills you. They died on their first tick, every time. On a two-team server that also ended the round, because a side with nobody alive is an elimination — which re-laid the field and freed every platform body from inside the netcode's own loop over replicated entities. The loopback suite found it as a flood of *"previously freed instance"*, three layers from the cause.

- **A round re-laying the field freed nodes inside somebody else's iteration.** The first behaviour through a tick is what runs the whole world, so a round that ends mid-tick destroys entities that `DotNetManager.server_tick` is part-way through walking. `ScPlatforms.clear` and `ScArena._clear` take their children out of the tree at once and free them at the end of the frame, which is neither `free()` nor `queue_free()` alone: the removal is what stops two fields existing at one height, and the deferral is what stops the destruction landing mid-loop.

- **A client rebuilding its field never unregistered the old one.** The server has `world_clearing` for this; a client is told rather than asked, so `_apply_layout` had no equivalent and left a dozen identities in the registry pointing at freed nodes.

- **The health number was drawn underneath the chat box.** Both anchor bottom-left. Invisible to every headless assertion, because a headless viewport is 64 × 64 and nothing in one can overlap anything.

- **A seat made the floor survivable.** The fall check skipped riders, because a rider's own position stops moving while they are carried — so a pilot who put the chopper down on the floor sat there out of the cannon's reach, and one who flew it off the edge of the map fell for the rest of the round, alive, and was handed a weapon in the corners either way. A rider is measured by the machine now, and a machine within two metres of the kill height has reached the floor: a parked one's origin rests 0.9 m above it, so a check at the kill height alone never fires.

- **Every round leaked a lag-compensation track per platform.** The round begins inside `DotNetManager.server_tick`, which records history for the identity list it took before the old field was let go of — re-creating a track for each id the registry had just told it to forget. Twelve per round, for the life of the server, and nothing reads them. The bridge forgets them again once the manager's tick returns; the dedicated suite counts orphaned tracks. The ten `!is_inside_tree()` engine errors at round one were the same stale list; dot-net fixed them, and `dedicated`'s real-server round asserts the engine reports no error at all (0 on 2026-09-24).

- **The chequerboard had no jumps on it at all.** Its blurb is "Every jump is a diagonal", and a chequerboard's diagonals run from one ROW to the other — and the rows were 13.5 m of air apart on every layout. So it was five islands, 14.6 m apart along every diagonal against a running jump of 3.9, and a 0.88 column scale under a comment saying it "widened" the diagonals narrowed a spacing no diagonal crosses. The rows are pulled in to 0.525 of the pitch now and the field is moved half a row over (see the next entry), so each diagonal is 2.8 m of air and the next platform along a row is 12.3 m; `headless_run` drives a runner along all four diagonals and then straight along a row, which is a fall.

- **Every cannon shot on The Spine went up into a bridge.** The tube stands in the middle of the field with its muzzle three metres under the decks, and on five columns and two rows the middle column's bridge is directly on top of it — forty shots in forty hit its underside and never cleared the decks, on a layout drawn one round in nine. No check fired a shot on any layout but the first. The middle bridge is not built now (`_has_bridge`), `ScArena.THROAT_CLEARANCE` is the 2.5 m a tumbling monolith sweeps, and the throat section measures every layout against it and then fires eight all-tier shots at each. Pulling the chequerboard's rows together put its middle platform 1.05 m from the same line and one shot in twenty into its underside, which is why that field is moved half a row over: the tube stands in the hole where (2,1) would be.

- **A survivor could not walk off their own corner.** The catwalks were given kerbs on their long sides only, so that a junction would not be a step — and the pad's and the ring's own kerbs ran straight across those same junctions from the other side. dot-player-controller's step-up does not take a 0.34 m kerb 0.6 m deep at a walk or a run, whatever `step_height` says, so a runner stopped dead at their pad's edge and again at the ring's. "A pad is edged on four sides and a catwalk on two" counted the kerbs and passed. `_build_kerb` cuts an opening wherever a catwalk's strip crosses an edge, square on or oblique; the check counts SIDES now, and the showdown walk is what fails with the openings taken out. **The step was fixed in dot-player-controller on 2026-09-24 (2e6d930)** and the openings stay, because a junction with no step is still the better junction; the showdown walk also closes the pad's kerb across its catwalk and walks over it with the brake held (0.34 m, climbed at 2.7 m/s). Measured while arming it: the step now climbs a 0.7 m kerb at a walk against a `step_height` of 0.45, and refuses 1.0 — the addon's, and in the Queue.

- **The camera moved only on a tick.** It hangs off the player's node, which the tick writes, so at 64 ticks against 144 frames 160 frames in 288 did not move at all while the player ran. `_process` draws the rig from `DotFpsController.render_state` now (per-frame speed variation 112% to 3%, measured), and `place_at` goes through `teleport` so the handover does not sweep the view across the map for a frame.

- **The Spine's steady ground was the least steady thing on the map.** Its blurb is "the walkways are the steady ground", and a bridge was built as a platform with the pillar left out: the same torsion spring, pivoting about its own middle in mid-air. A bridge is 12.9 m long against a platform's 10.5, so one runner at its end leaned it 9.7 degrees where the same runner at a platform's edge leaned the platform 7.9; two runners at one end took the bridge down while the platform beside it held at 15.7; and because it leaned about its own middle rather than following the lips, it met them with up to 0.85 m of step under a runner. `_build_pillar`'s comment said a bridge "is held at both ends by the platforms it joins", and nothing held it. **A bridge rests on its two lips now** (`ScPlatforms._rest_bridges`): its pitch is the line between the two lips' heights, its roll is theirs, a load or a blow on it is shared between the two platforms by where along it it lands, and it falls (`WHY_UNSUPPORTED`) when either of them does. One runner at its end tilts it 3.0 degrees and nothing at its middle; `headless_run`'s Spine section drives a runner across one (2.6 degrees at worst, no step at either lip) and fails five ways with the old spring put back. It is every layout's bridges, not only The Spine's — every bridge in the catalogue joins two platforms — and the wire is unchanged, because a client adopts a bridge's lean and sink like any deck's.

- **The shot that ended a showdown was counted in no round.** dot-match's `report_kill` can end the round synchronously — the last person on a side going is an elimination — and ending it drops the phase to IDLE and files the round. `_on_player_died` reported to dot-match first and to `ScProgress` second, so the winning kill of every showdown was counted in no phase and missing from its shooter's best round; `headless_run` found it as a showdown kill of zero on a round that had plainly been won with one. Spectating and progress are told first now, and the comment says why.

- **Slopes becoming walkable did not move the slide angle** (dot-player-controller 803308f, 2026-09-24). Held at a fixed lean, a player stands still at 13.5 degrees and walks up it at 2.3 m/s; at 15 a player standing still slides 3 m in a second — which is `max_slope_angle` 14 against a collapse at 16, as designed. **But a player who pushes uphill at 15 climbs it at 1.7 m/s**, on the addon's steep-surface air control (the surf behaviour), so the "floor throws people before it goes" only throws the ones who are not trying; and a player who LANDS moving uphill on a lean from about 12.3 degrees up stays airborne, gliding at air speed, for over a second. Both are in the Queue as the addon's; `headless_run` asserts the three that are this game's design.

- **A connected client predicted nobody, and every check said it agreed with the server.** `ScNetBridge._apply_join` mirrored every player with owner 0 — this client's own included — so `is_owner` was false for the local player, `registry.predicted()` was empty and `client_tick` simulated nobody: the player moved when a snapshot came back, a round trip behind the keys. "A client moves itself and the server agrees" passed throughout, because a client adopting every snapshot also agrees with the server, and its correction rate was 0.00 because the predictor never ran. **And it is what made the camera lurch**: the rig is drawn from `DotFpsController.render_state`, a blend between the controller's last two ticks, and a controller that never ticks has a previous tick frozen wherever the player was last teleported — so every frame was drawn somewhere between the round-start spawn and the snapshot. Measured with `tools/shot.sh --view=walk` (a server and a connected client in one process, 144 frames against 64 ticks), before and after: median eye speed per frame while the server has the player at 6.4 m/s, **60.9 m/s (p90 199.8, max 1313.5) against 6.0 (p90 6.2, max 6.3)**; key to motion 1 to 3 ticks on a zero-latency loopback (a round trip on a real link) against 0; 0 replays against 227. mg-buses-from-hell had the same line and found it the same day; the fix is theirs — `_mirror_owner` gives the mirror whose session HELLO named this client's local peer id, and `_claim_local_player` claims one that arrived before HELLO — rather than game-arena's owner peer in JOIN, because `is_owner` compares against this registry's own local peer, so that is the only right value whatever the server calls the connection, and **the wire does not change**: a published pack's server half talks to a new client and the other way round. `headless_net`'s "the local player is predicted, and nobody else is" asserts the mechanism instead of the agreement — owned, in `predicted()` and alone there, a key moving the player in the tick it is pressed before the server has simulated it, and a server-side `place_at` corrected and converged on — and fails five ways with the old line. Its last check waits two seconds for the floor to settle before asking for a quiet thirty ticks: the first version measured straight after the move, and a platform swinging to a new lean under a predicted player is a one-centimetre correction one run in two.

- **Nobody died of falling, anywhere, ever — and the middle of every platform was collapse-proof.** The floor's top is the kill height and the fall check was `y <= kill_height`; the motor rests a capsule a skin width above what it stands on, so a player who fell forty metres landed at 1.51 m against a kill height of 1.5 and stood there for the rest of the round. Every fall in every suite was `place_at` five metres UNDER the floor and one step, which a real fall never does. And a player within about 1.5 m of a platform's middle never got that far: the platform's collider goes the moment it comes off its pillar, and they dropped 0.57 m onto the bare PILLAR's top — 2.7 m across, out of the cannon's reach because it aims at standing platforms — alive at the end of the clock and so handed a weapon at the showdown. Measured on all eight layouts, seven offsets each, collapsed by lean and 400 ticks later: all 56 alive — 16 on a pillar at 39.4 m, 38 on the floor at 1.51, and two on `islands` back on a standing deck, which was not chased. The progress section had already written it down as "a platform off its pillar leaves the pillar, which can catch somebody" and worked round it. **Fixed as the design says**: a person on foot within `ScGame.FLOOR_REACH` (0.5 m) of the kill height has reached the floor, and pillars are on their own collision layer, `pillar`, solid to props and choppers and never to a person — the bare pillar stays as the marker `pillar_falls_with_platform` keeps it for, and a collapse takes the floor away with whoever is on it. After: 56 of 56 fall and die. A faller over a pillar drops down through the inside of the column, which a watcher can see; a column that caught them is the bug. `headless_run`'s "a platform off its pillar takes everybody on it, and the floor is fatal" drops three people from one really collapsed platform (on the axis, inside the pillar's radius, outside it) and walks one off a standing platform's edge, and waits; armed: the pillar back on `world` fails three checks (two alive on the pillar at 39.40), `FLOOR_REACH` at 0 fails four (all alive at 1.51).

- **Two Islands was four.** Its blurb is "Two islands and a lot of air between them. Nobody is crossing", and its rows were the usual 13.5 m of air apart with no bridge — so each end of each row was two platforms nobody could leave, four islands of two, and two sides started on two of them and never met. Measured with `ScLayouts.islands()`, which is new: what a player can get to, as a number per cell, off the built field — bridges, and the jumps a layout DECLARES, which the reach section already holds to a running jump in both directions. The rows are pulled in to 0.51 of the pitch and the columns to 1.08, so each end is one island of four crossed every way (1.8 m of air along a row, 1.7 m across, 2.56 m on a diagonal against 2.94 off a corner), and between them is the missing middle column, 14.1 m that nothing reaches, with the tube standing in it 7 m from any edge. **And the sides are dealt one to an island**: `_place_players` spreads sides by index in the field's row order, which on a field of islands put both sides at the two ends of the first column — one island — so a side is not started on ground another side can already reach while there is ground no side has. A field that is one piece never takes that branch, so every other layout starts exactly where it did; Hollow Centre, whose two strips are also islands, now starts its two sides one on each. `headless_run`'s Two Islands section counts the islands, starts two sides, drives a runner round one island along, across, along and on a diagonal (53.1 m covered of a 54.2 m route, top speed 6.40 of 6.40 m/s) and then at the other island, which is a fall. Armed: the columns at 1.2 fail the reach section and the diagonal; the spawn rule off fails the sides check ((0,0) and (0,1)); the brake held through the jumps fails the run (top speed 2.73). Hollow Centre's own `Gaps.HOLLOW` comment says a five-column field "loses its centre one" and the code takes three; not touched.

## What DELIVERING it found

These are separate from the list above because none of them can happen until the game is a pack: three suites, five renders and 280 checks all pass on a game that will not run when it is mounted. Publishing it and booting a server is its own step, rendering the delivered map is another, and running stand-ins against each other for twenty rounds is a third; between them they found nine things, including one that made the whole second half of the game not work.

- **Every path the publisher had already rewritten was rebased a second time.** `ScPropBody` loads its model from an exported `model_path`, and a publisher rewrites every `res://` string inside a `.tscn` onto the mount prefix — so the value arrives absolute and `rebase()` prefixed it again, producing `res://dot_cloud/tmc/smash/0.1.0/dot_cloud/tmc/smash/0.1.0/assets/kenney/car/debris-tire.glb`. It is long enough that the doubling reads as noise. This is the seventh form of the family's one delivery bug and it is written up in dot-server-deploy's own notes; `rebase()` returns a path already under the root unchanged.

- **And the check for it passed with the bug put back.** Built in, `root()` is `res://` and every `res://` path is already under it, so every property of `rebase()` that matters in a pack is a tautology here. The idempotence was asserted, the fix was reverted, and the suite reported 101 passed and 0 failed. `ScPaths.rebase_onto(path, root)` exists so the suite can hand it a real mount prefix, and `rebase()` is one line over it. **Arming a guard means checking it fails, and this one is the reason that rule is in the family's notes.**

- **The combat manager set itself up twice**, because `DotCombatManager._ready` calls `setup()` and `_build_combat` called it again after `add_child`. The tell was a delivered log with every line `setup()` emits printed twice in a row.

- **Lag compensation reported as unwired on a server where it works.** dot-combat defaults the flag on and warns as it comes up if no rewind function is there; the bridge wires one thirty lines later. The world builds with the flag OFF and `ScNetBridge` turns it on in the same breath as the two callables, so the boot line and the behaviour agree. The netcode suite now asserts all three together.

- **The showdown's pads had no edge, and `_pad` said in its own name that they did.** A render of the corners from a player's height showed three flat shapes against a flat sky with nothing to mark where any of them stopped — the same readability problem the platforms had, on the half of the map where being wrong is permanent. `CORNER_LIP` had a doc comment explaining why the lip is low and is not cover, `_pad` was described as "one flat surface with a kerb around it", and no line anywhere built one. A value documented in two places and produced nowhere is as invisible to a suite as one produced and consumed by nothing.

  The catwalks get the band on their two LONG sides only. A kerb across the short ends is a third of a metre of step at the junction a player is running through, and a body catching on it would have read as the movement code being wrong. **And the pad's and the ring's kerbs are open where a catwalk arrives, which they were not until 2026-09-23** — the same step, from the other side; see "A survivor could not walk off their own corner" above.

- **Nobody could shoot anybody, and 280 checks said the weapons worked.** Every shot in the showdown left the world origin pointing due north, whatever the player was doing, because `ZeeWeaponRig` resolved its carrier inside `_resolve_presentation()` — behind that function's `role == SERVER` early return. The view model and the world model belong there; the player does not, because it is where the muzzle position and the aim direction come from. Fixed in zee-dot-weapons, where it affected every server using the pack.

  The half of it that was this game's: `ScPlayer` had no `component()` method, so `DotWeaponPlayerBridge` failed all three of its lookups and fell back to the body transform — the right position and an identity basis, because the yaw lives in the controller's state and never in the node. So even with the carrier resolved, every shot left the player's feet pointing north. `component()` is four lines and is the seam the bridge documents.

  **And friendly fire was on in a game whose rules say it is off.** `DotDamageResolver._same_team` takes a `team_of` [Callable] and returns false when it has none, which is right for a free-for-all and silently wrong for every team game that forgets it. The rule was evaluated, the answer was "not team mates", and the shot landed. There is no number anywhere that is wrong.

- **A bot showdown produced the same winner every round, twelve times out of twelve.** The corners are symmetric, the arrival slots are symmetric and the bot brain has no state, so a fight between stand-ins was a pure function of an arrangement that the round seed does not change — and the same bot took the only kill in every round. An empty server filling itself with stand-ins is this game's normal state, so that is what most people would have seen first.

  The fix is one drawn value: an aim error per bot per round, from the game's own reproducible stream. **The first version of it did nothing at all**, because it drew on the entity id alone and an entity id is the same every round — twelve rounds came out byte-identical to twelve rounds with no jitter. `stream_for` was doing exactly what it promises; what was missing was anything that varied. The round number is mixed into the subject now.

- **dot-match warned once per player per round, for ever.** `_begin_round` enqueues everybody and drains the queue regardless of `respawn_disabled`, so this game — which places its own players and deliberately has no `DotSpawnPoint` anywhere — got "no usable spawn point at all" four times at every round start. Fixed in dot-match rather than here: `choose_spawn` returns null when there are no points at all, because an empty list is a game that computes its own positions and `refresh_spawns` has already warned once if that was an accident. The selector's warning still fires for its real meaning, which is that it was given points and could not use one.

## The netcode

`game/net/` and `game/sc_module.gd`. What is worth having here is the shape.

**A player's own feet are the only predicted thing in the game** — and until 2026-09-25 they were not predicted either; see "A connected client predicted nobody" above. The platforms, the props and the choppers are all server-authoritative, and so is a pilot: a chopper's mirror is owner 0 on every client, and `ScPlayerNet` applies a rider's command without simulating the controller. The platforms are the interesting case, because they are the floor — see Decision 1. **A predicted player on a floor that moves is corrected now and then by a centimetre**: the client draws the lean from snapshots it runs `INPUT_LEAD` ticks ahead of, so running across a platform that is leaning under you is corrected on about a fifth of snapshots (`--view=walk`: 36 to 61 corrections in 227 replays, worst 1.9 cm, no snaps). That is the floor being the server's, as Decision 1 says it must be, and it is under what a player can see.

**A platform replicates in four numbers, and the state is not interpolated.** The lean moves continuously and a client between two snapshots should be between two leans; a platform that has come off its pillar takes its collider away on the tick the client is told, not smoothly over the next three. Half way between standing and gone is not a thing a floor can be.

**The clock carries what a client cannot count.** A client runs no platform model, so counting the platforms that are still up would count whatever it last heard — and that number is the most important one on this game's HUD, because it is what tells a player whether there is anywhere left to go.

**The weapons replicate as a counter, never as an event per shot.** An RPC per shot needs a reliable channel for something worthless if it arrives late, costs a packet per shot per watcher, and desynchronises from the state it belongs with — so a watcher sees the muzzle flash of a weapon the same snapshot says has been holstered. A four-bit counter inside the snapshot cannot do any of those: a watcher who missed a snapshot sees it jump by two and plays one flash instead of two, which is the correct amount of wrong. The magazine and the reserve are owner-only, because exact ammunition is information an opponent should not have.

**`headless_net` runs two BUILDS, not one** (2026-09-26). The server and the client each register an optional message type the other has never heard of before the seal, and every section after "two builds with different message types share the wire" plays over that: the tables cross as the join happens, each end skips the other's newer message without disturbing the next, and a client missing this game's required types (or requiring one this server lacks) is refused with dot-net's sentence. Armed by making the server's extra type required, which fails the schema comparison at once. It found nothing in the game, which is the point: the game's two types are required, everything newer can be optional, and a published pack's server half now talks to a client built from a different dot-net.

**A client disconnected mid-round freed its bodies under the bridge**, and a queued `PROP_GONE` then cast a freed object (`_apply_prop_gone`), as did `_forget_platforms`: three `SCRIPT ERROR`s on a run that exited 0. Found by dot-server-deploy's `smash_client`, whose last section is the first thing to disconnect a client out of the middle of a round. Both check `is_instance_valid` before the cast now.

**`examples/headless_net.tscn` is the real path minus the socket.** Two worlds, two managers, two bridges and two links with the RPC replaced by a callable — so the encoders, the seal, the snapshot build, the prediction and the reconciliation all run. The client is deliberately given a different tick rate and a different field than the server, because one process has one engine rate and one default configuration: two halves that agree by construction make every assertion that they agree pass for the wrong reason. Four of the findings above came from it, and it cannot see Godot's own RPC routing — that is what `dedicated.tscn` and a real client are for.

**The snapshot rate is thirty, against the twenty mg-buses-from-hell uses.** Almost nothing here is predicted and the one thing a player has to read continuously is the lean of the floor they are standing on, which arrives only in a snapshot. At twenty, a platform's tilt updates in visible steps — and a step in the surface under your feet reads as the game stuttering.

## The chopper is a fourth chassis

`DotVehicleHover` returns early when its ground rays find nothing, which is the hovercraft being right and is exactly the state a helicopter spends its life in. `DotVehicleWheeled` needs wheels on a surface. So `ScCopter` is loaded through `DotVehicleDef.chassis_script_path`, which is the extension point dot-vehicle documents for a fourth kind, and nothing in that addon is forked or knows what a helicopter is.

**Three controls fit in a `DotVehicleCommand` and the fourth does not.** The collective is the throttle, the pedals are the steer, the rotor brake is the brake — and the cyclic goes in `DotVehicleInstance.meta`, because widening the command would be a breaking change across every game in the family for a field only an aircraft has.

**It holds itself up at exactly neutral, and that is what makes the control readable.** A machine whose neutral is a slow sink is one a player is fighting the whole time they are trying to aim at something. It does not arrest a climb, which is what the ceiling is for.

## Decision 7: no `class_name`, anywhere in this repository

Every script here is reached by a relative `preload`, every subclass by a relative `extends`, and every `res://` string this game writes about its own files goes through `ScPaths.rebase()`. That is not a style: **a mounted dot-cloud pack's `class_name` globals are not registered in the host**, so a delivered game that used one would mount, load its scenes, and have every script in it dead with nothing reporting a thing. **A path is rebased where it is DEFINED, not where it is used:** `static var CRATE_SCENE := ScPaths.rebase("res://…")` rather than a `const` wrapped at every call site. Both are correct today; the second is one new call site away from a prop that does not spawn in a delivered round, and `dot-server-deploy/tools/check.sh` counted all of them (31 across this game and its sibling) because it cannot follow a `const` to its uses. headless_run's delivery section scans every shipped script for a bare `"res://…"` naming one of this game's own directories and fails naming the line; it was armed by putting `sc_content.gd`'s CRATE_SCENE back to a bare `const`.

`dot-server-deploy/tools/check.sh` refuses a new one in any game repository, which is what keeps it that way.

## Decision 8: the world sets its own gravity, and the renderer is the one players use

Two things that live in `project.godot` do not travel with a delivered pack.

- **`physics/3d/default_gravity` is left at Godot's 9.8 here**, deliberately, and `ScConfig.gravity` is the number the game is tuned against. `ScGame._apply_gravity` writes it onto the world's own physics SPACE — the space rather than the setting, because a server and a client in one process are two worlds and a global would be one of them deciding for the other. It is also what makes the low-gravity special one line.
- **The client shell renders with `gl_compatibility`, because the browser is its target.** This project says so too, and its lighting was tuned by rendering under it.

## Being out: dot-spectate

**Until 2026-09-25 a player who fell spent the rest of the round looking at the floor of the map from inside it.** The camera hangs off the player's node and a faller's body is at the kill height, forty metres under the round that decides whether their side wins. This is last-team-standing, so the people who are out are exactly the people with the most reason to watch — and in the showdown, the people with the most reason to cheat by watching.

`ScSpectate` wraps a `DotSpectatorManager` and is built by `ScGame` on both ends. **On a server it decides; on a connected client it is a mirror that is told.** Every view change — a death, the hand-over after the death camera, a target leaving, a step through the list — becomes one `SPECTATE` event to that player's peer alone (a camera is private, and a stand-in's peer is zero, so `_tell` sends it nowhere). The client computes the camera itself from the players its world already draws, so the wire carries a decision per event and never a transform per frame. A step or the camera key is `Ask.SPECTATE`, answered from the server's own `targets_for`, and a refusal comes back as a notice rather than a key that silently did nothing.

- **The death position travels in this game's own event, because dot-spectate's does not.** `DotSpectatorView.to_wire` carries a mode, a target, a free position, a fixed index, a deadline and a killer, and no death position — so a mirror built from it draws every death camera at the world origin, which here is inside the cannon. `ScEvents.write_spectate` carries it; `headless_net` asserts the client's death camera is over the drop. **Fixed in dot-spectate on 2026-09-25** (`"d"` on the wire); this event stays, because it is bit-packed and session-keyed and dot-spectate's wire is neither.
- **A faller's death camera is not where they died.** A fall is recorded at the kill height, the one place nothing is worth seeing from, so `on_died` moves it back up over the point they went down and looks straight down the drop (`DROP_CAM_RISE`). Armed: without it the camera is at y -1.5.
- **"Own side" by default (`sc_spectate_camera`, `ScConfig.spectate_camera`).** The survival phase is harmless to watch, but the showdown is a team fight in the open and a dead player on voice with a camera on the other corner is a free scout. dot-spectate then forces first person, because a chase camera sees round corners. `0` allows anybody and the chase camera, `2` nobody.
- **The server's own choice goes to a team-mate first.** dot-spectate picks the first allowed name in key order, which under "anybody" is a stranger. `_prefer_side` moves an automatic hand-over or retarget to the first living team-mate; a viewer stepping through the list themselves is left where they asked. Armed: without it the retarget lands on the other side's `c`.
- **Nobody left on your side is a fixed camera, and there are two.** One over the field and one over the corners, both built from the decks actually laid out (the chequerboard's field is moved half a row over), and `camera_for` picks by phase — a fact a client already has, so it is not sent. One camera over the field would spend the showdown pointed at where the round had just left.
- **No delay, because it would hide nothing.** dot-spectate's delay exists because a live spectator is an intelligence feed — but every player here is always relevant, so every client already receives every position live. `delay_ticks` is 0, and a mirror, which records no history, never needs one.
- **The client moves its camera off the player's node while they watch** (a global transform on a camera under the chase arm is undone by the arm) and hands it back through `_place_camera` when a round starts. The watched player's body is not drawn around a first-person camera (`present_frame`'s `watched`), and the view model is hidden, or the spectator watches through somebody else's eyes holding their own gun. Out, left and right click step through the list and F5 swaps first person and behind.
- **Counted before dot-match hears of the death.** `report_kill` can end the round synchronously; see "What running it found".

`headless_run` drives the whole policy on an authoritative world (16 checks); `headless_net` asserts what crosses and what the client draws with it; `dedicated` asserts the cvar reaches the running policy; `tools/shot.sh --view=spectate` renders both fallbacks.

## Sound: dot-audio

**The game made no sound at all, and here that is not polish.** The cannon is behind you as often as in front of you, and the only warning of a monolith that works without looking up is a bang from the middle of the map; the second is the platform under you creaking before it goes, which the tilt bar tells only somebody reading it. `ScAudio` is the family's shape: `sound_catalogue()` is every decision — positional or flat, cull distance, concurrency, priority — as a document naming `.ogg` paths nobody has produced (under `ScPaths.rebase("res://audio")`, so a delivered pack's paths follow the mount), and `sound_recipes()` says which `DotAudioSynth` voice stands in for each until they are. `DotAudioSinkGodot` reads the file before the stand-in, so dropping one in switches that id over.

- **The distances are the map's, not a corridor shooter's.** The corners are 133 m from the tube, so the cannon and a collapse carry 260 m. Armed: at 90 m the showdown hears no cannon.
- **The cannon's bang is a prop that ARRIVED at the muzzle.** A client learns about a prop when it arrives, and it arrives the same way whether it was just fired or was already in the air when the client joined — which would be a volley of bangs on every join. Within `MUZZLE_REACH` of `ScArena.muzzle()` it was fired this tick. `ScNetBridge.prop_arrived` is the client's source; offline it is `props.spawned`.
- **A landing is an event (`IMPACT`), because a client cannot see one.** It runs no platform model and its props are frozen mirrors; the lean the landing causes arrives in the snapshot like any other.
- **The creak is derived on the client and is not sent.** Whether a lean is past 70% of the collapse angle is a function of two numbers every client already has thirty times a second. With hysteresis — it may creak again only after settling below 50% — or a lean on the threshold creaks on every snapshot. Armed: without it, 30 creaks in 30 frames.
- **Weapons by KIND of use, not by weapon.** The snapshot's `net_fire_kind` is three bits; five kinds are the distinction a player acts on, and twenty-seven weapons would be twenty-seven files nobody has made. Your own shots come from your own rig's `used` signal (a round trip sooner than the snapshot); everybody else's from `ScNetBridge.weapon_used_by`, which relays each player behaviour's `weapon_used`, or offline from each rig as it is armed.
- **The ears are wherever the eyes are**, spectator camera included, so somebody who is out hears what the team-mate they are watching hears.
- **The beacon's ping stays in `ScBeacon`.** It is its own `AudioStreamPlayer3D`, `headless_run` pins it to once a second, and moving it is a change to a tested behaviour with nothing to gain but tidiness. `beacon` is the id it should move to when real audio ships.
- **Client only.** A server never builds one; a headless client gets dot-audio's null sink, which is the real manager recording instead of playing, and that is what the suite asserts against. **Whether a speaker moves is `tools/audio_probe.sh`**, the audio half of `tools/shot.sh`: under xvfb it gets a real driver, plays the cannon, the creak, the flat "you are out" and a shot through the manager, and asks `is_playing` rather than "was there a handle" (all four sounding on ALSA, 2026-09-25). Its first version quit with a voice still sounding and the engine reported the stream and its playback as leaked; it drains the mixer for ten frames first now.

## What a player keeps: dot-stats and dot-achievements

`ScProgress` declares ten numbers once — rounds played, survived (still up when the clock ran out), won, showdowns won (your side won and you were still standing in the corners), showdown kills, best showdown (a BEST), deaths, falls, platforms tipped (a collapse by LEAN with you on it: somebody's doing, not the cannon's) and props dodged (a landing on your own platform that only leaned it and missed you by more than the hurt radius). dot-stats reports them as deltas when an operator turns `report_progress` on. Eight achievements are rules over them through `DotAchievementStatsLink`, which is the differencer between a session and a lifetime — wiring `recorded` into `record` would add the running total on every reading (armed: three dodges then read 1+2+3). Two are secret, because they are earned by the mistake the game is about.

- **Stand-ins are never counted.** An empty server is a server full of them, and an achievement a bot can earn is noise in every log. **A player is begun on their first number, not on join**, because a world adds a player before the bridge or the client marks them a stand-in, so a join-time check would see every bot as a person. `dedicated` asserts a round of stand-ins files nothing for anybody.
- **Authoritative worlds only**: a server, and an offline client (where the world counts for the player at the keyboard and says what they earned in the chat box). A connected client's world decides nothing. On a server an unlock is a notice to that one peer.
- **Memory by default** (`progress_directory`), which is dot-achievements' own default and its reason: a server that silently started writing a file per player is one nobody notices until the disk is full. **Reporting is off** (`report_progress`): it needs an integration credential this game does not configure.
- **`dedicated` printed one WRN it had not printed before, and it was dot-stats'.** `WRN stats.report a reading names a stat that will not be reported stat=sc.deaths why=unpublished` is `DotStatsTracker.end()` queueing a leaver's delta into the reporter even with `report_to_backbone` off (`dot_stats_tracker.gd` `end` → `_checkpoint` → `reporter.queue`), and the reporter warning, once per stat, that an unpublished stat will not be sent — on a server that sends nothing. Publishing `sc.deaths` to silence it would be changing a decision to hide a log line; it is in dot-stats' queue instead. **Fixed in dot-stats on 2026-09-25** (with reporting off the tracker never touches the reporter), and `dedicated` prints no such line now.
- **Keys are the world's player ids**, `u<session>` on a server, which dot-stats accepts and which can never carry an account id. With no identity layer a key does not outlive a connection, so lifetime progress is per connection until there is one — the day there is, the scoped key it resolves is what `record` should be handed.

## Things deliberately not here

- **dot-settings.** Every other game has a settings document with sensitivity, field of view and volume in it, and it is refused here for now because **this client has nowhere to put one**: there is no menu, no pause screen and no dot-ui screen of any kind — the HUD is four numbers and a bar. A settings document with no screen is a JSON file a player edits by hand, and this client already reads one (`user://cfg/smash-copter.json`, through `ScConfig.load_layered`); a second would be two files of player-editable numbers with different rules for which wins, and dot-settings' whole value — a bounded document a screen is generated from, with scopes a server may clamp — is the screen. The day a menu exists, the first three settings are the master volume (dot-audio's mixer is already there), the sensitivity (`DotFpsTunables.mouse_sensitivity`, which the sampler already reads) and the field of view, and `apply_all()` goes with them — because a value loaded from disk has not "changed", and a layer that only listens for changes applies nothing it loaded.

## The art, and the one thing to know about vendoring it

Six prototype textures by role, eight models from two kits, and the weapon pack's own art. All CC0.

**The two `Textures/colormap.png` are different files with the same name**, so each kit is in its own folder. Flattening them paints the survival props in the car kit's palette, which is a plausible-looking wrong answer no assertion would ever catch.

**The models are loaded by PATH rather than instanced as an `ext_resource`**, which is a delivery decision. A `.tscn` records an external resource as an absolute path plus a UID and inside a mounted pack neither resolves; mg-buses-from-hell shipped a round where every crate's mesh loaded and every crate's texture did not, which is a game that plays perfectly and appears to have shipped without art. `ScPropBody` loads through `rebase()` and puts the atlas on by hand where one is missing — which in a build does exactly nothing.

## No message preloads itself

`sc_event.gd` and `sc_request.gd` each began by preloading themselves, for a typed `of()` factory. mg-buses-from-hell measured that line (8ed866c) as enough to leak the whole script graph at exit on Godot 4.7.2: a script that `extends DotNetMessage` and preloads ITSELF, first loaded by a module inside a running `DotServer` — which is how every deployed server loads a game. Both are built with `new(kind, body)` now, an `_init` whose arguments default because dot-net's registry decodes with a bare `new()`.

`dedicated`'s last section, **exiting clean**, reads every `DotNetMessage` script under `game/` as text and fails on a self-preload. It is on the source deliberately: the leak is printed by the engine after `quit()`, where no assertion can reach.

**Here it was the whole leak.** `dedicated` exited with 180 ObjectDB instances, 116 resources, two VariantPools pages and thirteen dummy material, shader and texture RIDs still alive; with the two lines gone it exits with no warning at all (2026-09-23).

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/headless_run.tscn   # 31 sections, 236 checks
godot --headless --path . res://examples/dedicated.tscn      # 10 sections, 70 checks
godot --headless --path . res://examples/headless_net.tscn   # 20 sections, 197 checks
tools/shot.sh --view=field
tools/shot.sh --view=lean
tools/shot.sh --view=copter
tools/shot.sh --view=showdown
tools/shot.sh --view=ring                           # the ring from a pad at eye height: its cover
tools/shot.sh --view=flank                          # a perch on the flank, its two catwalks, the ring side-on
tools/shot.sh --view=junction --sc-team-count=3     # an oblique catwalk meeting the ring, from above
tools/shot.sh --view=jump --sc-layout-ids=checker   # the jump a layout means, from behind
tools/shot.sh --view=bridge --sc-layout-ids=spine   # a bridge weighed down at one end, from beside it
tools/shot.sh --view=field --sc-layout-ids=islands  # two islands of four, the tube in the hole between
tools/shot.sh --view=beacon                         # an admin's beacon, from across the field
tools/shot.sh --view=blind                          # a blinded player's own screen
tools/shot.sh --view=spectate                       # out, with nobody on your side left: the overview
tools/shot.sh --view=spectate --sc-spectate-camera=0   # out, through a stand-in's eyes
tools/shot.sh --view=walk                           # a connected client runs: key to motion 0 ticks, eye ~6 m/s
tools/audio_probe.sh                                # the sound half: exit 0 means a speaker moved
```

All three suites count sections **and** a total, and the total is the one that catches what the section counter cannot: a runtime error inside a section aborts that function and the section counter is already satisfied, because the section announced itself on the way in. Every guard was armed — the total raised by one and the run re-run — and every one fired.

**The render is not optional.** Four of the entries above were found by looking at a picture and are invisible to every assertion in this repository. `tools/shot.sh` is not `--headless`: Godot's headless display driver does no rendering at all, so a capture under it is a black PNG, which is worse than no screenshot because it looks like one.

**And neither suite reaches the deployment**, which is where five of mg-buses-from-hell's bugs came from. That needs the real thing:

```bash
# in dot-server-deploy
godot --headless --path ../mg-smash-copter --import   # form five: a pack cannot import itself
./server pack smash --source games/mg-smash-copter
./server --game smash
# then connect the client shell to 127.0.0.1:6070
```

## Still to do

In the order they are worth doing.

1. **Connect a real client shell to a delivered server.** The pack is published, signed and mounted, and a server runs whole rounds out of it with a clean log — but every player in those rounds is a bot, so Godot's own RPC routing over a real socket is still the one layer nothing here has exercised. It is where five of mg-buses-from-hell's bugs came from.
2. **A world model in a watcher's hands.** The weapon state replicates and `ZeeWeaponNet.apply` already takes a null model; what is missing is a hand mount on `ScFigure`, the Kenney body a client draws for everybody else.
3. **An identity layer**, if this game ever wants profiles and avatars. dot-game reports the gap at boot and carries on, which is a server where everybody is a guest — and, since 2026-09-25, a server where achievement progress lasts one connection, because `ScProgress` keys by session.
4. **A menu, and dot-settings with it.** See "Things deliberately not here": the refusal is about having no screen, not about the settings.
