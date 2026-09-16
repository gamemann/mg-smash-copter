# mg-smash-copter

Stand on a platform balanced on one pillar while a cannon throws things at it. Whoever is still up when the clock stops finishes the round in the sky with a weapon they did not choose.

Read the family-wide conventions in [`../../CLAUDE.md`](../../CLAUDE.md) first, and each addon's own `CLAUDE.md` before working in it. This file is only about what this game decides.

## What this game is, versus the other six

game-arena is a deathmatch, game-g2gfast is a timer server, game-playground is a sandbox, game-hungario is an eating game, game-simple-lobby is a lobby and mg-buses-from-hell is asymmetric. This is the first one whose **primary antagonist is the floor**, and everything below comes from that.

Nothing can hurt anybody for the first two thirds of a round. There is no weapon, no objective to capture and nobody to shoot. The entire first phase is a question about where to stand on something that leans toward you, and the only inputs a player has are where they are and how fast they are moving. Then the clock runs out and it becomes an ordinary team fight — between exactly the people who were good at the first half.

Neither half would be much on its own. What makes the second one work is that the people in it earned their place by not falling over.

## Layout

```
game/
  sc_paths.gd       where this game's own files are, wherever it is mounted
  sc_config.gd      every number, in metres and seconds, layered like every DotConfig
  sc_textures.gd    the six prototype textures, by ROLE, and the grid that stands in
  sc_content.gd     the prop catalogue in four tiers, and the chopper. The design, as data
  sc_layouts.gd     eight arrangements of the field, as documents
  sc_specials.gd    nine things that go wrong, as multipliers
  sc_arena.gd       the sky, the floor, the tube and the corners. In code
  sc_platforms.gd   THE FILE. A slab on a pillar, as a spring this integrates
  sc_cannon.gd      what the tube throws, where it aims, and how long it stays
  sc_copter.gd      a fourth kind of vehicle chassis, because neither shipped one flies
  sc_player.gd      one person: movement, the carry, health, weapons
  sc_game.gd        the simulation: phases, loads, impacts, falls, the handover. Headless
  sc_hud.gd         four numbers, a tilt bar and a dot
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
examples/           headless_run (106), dedicated (43), headless_net (134)
tools/              shot.gd/.tscn/.sh — render a frame and look at it
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

A round's field is an id, six numbers and a list of cells. A client rebuilds the identical field from them, every platform comes out in the same order, and a snapshot then moves platform number seven without ever saying what a platform is.

**The cell list travels rather than the layout id alone**, and that is a decision about what "agree" means. A client deriving the field from a catalogue of its own would build the right field right up until its build was one layout behind the server's — and then its platform seven would be somewhere else and every snapshot after that would move the wrong floor, silently. Thirty-odd bytes once a round buys the whole class of bug.

## Decision 5: no dot-spawn

Every other 3D game in this family uses it. A spawn point is a fixed place in the world, and **every place in this world is on something that tips, collapses, or is not there this round** — so a `DotSpawnPoint` would be a promise the map cannot keep. The game places its own players: a side to a platform, spread around its middle, facing inward, from the field it has just built.

`DotMatch.spawns_ref` is still set, to the match node itself, so that dot-match never walks the whole scene looking for points that do not exist. Unset it picks up another world's in a process holding a server and a client, and the outgoing map's for the frame after a round change; both are in this family's own bug list.

## Decision 6: the showdown is somewhere else

The corners started directly over the platform field, a few metres above the decks. That put the ring exactly where the cannon's tube is, where the cannon's arc passes, and where a chopper parks — and a machine spawned on its pad came up inside the underside of the ring and sat there pinned, holding perfectly level and refusing to climb, with every number about it correct.

The whole complex is a map's width away along -Z now. It is still in plain sight from every platform, which is the point: a player who can see where the round ends plays the first half differently.

## What running it found

Every one of these was found by running the game or by looking at a picture of it, and not one of them errored.

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

## What DELIVERING it found

These are separate from the list above because none of them can happen until the game is a pack: three suites, five renders and 280 checks all pass on a game that will not run when it is mounted. Publishing it and booting a server is its own step, and rendering the delivered map is another; between them they found six things.

- **Every path the publisher had already rewritten was rebased a second time.** `ScPropBody` loads its model from an exported `model_path`, and a publisher rewrites every `res://` string inside a `.tscn` onto the mount prefix — so the value arrives absolute and `rebase()` prefixed it again, producing `res://dot_cloud/tmc/smash/0.1.0/dot_cloud/tmc/smash/0.1.0/assets/kenney/car/debris-tire.glb`. It is long enough that the doubling reads as noise. This is the seventh form of the family's one delivery bug and it is written up in dot-server-deploy's own notes; `rebase()` returns a path already under the root unchanged.

- **And the check for it passed with the bug put back.** Built in, `root()` is `res://` and every `res://` path is already under it, so every property of `rebase()` that matters in a pack is a tautology here. The idempotence was asserted, the fix was reverted, and the suite reported 101 passed and 0 failed. `ScPaths.rebase_onto(path, root)` exists so the suite can hand it a real mount prefix, and `rebase()` is one line over it. **Arming a guard means checking it fails, and this one is the reason that rule is in the family's notes.**

- **The combat manager set itself up twice**, because `DotCombatManager._ready` calls `setup()` and `_build_combat` called it again after `add_child`. The tell was a delivered log with every line `setup()` emits printed twice in a row.

- **Lag compensation reported as unwired on a server where it works.** dot-combat defaults the flag on and warns as it comes up if no rewind function is there; the bridge wires one thirty lines later. The world builds with the flag OFF and `ScNetBridge` turns it on in the same breath as the two callables, so the boot line and the behaviour agree. The netcode suite now asserts all three together.

- **The showdown's pads had no edge, and `_pad` said in its own name that they did.** A render of the corners from a player's height showed three flat shapes against a flat sky with nothing to mark where any of them stopped — the same readability problem the platforms had, on the half of the map where being wrong is permanent. `CORNER_LIP` had a doc comment explaining why the lip is low and is not cover, `_pad` was described as "one flat surface with a kerb around it", and no line anywhere built one. A value documented in two places and produced nowhere is as invisible to a suite as one produced and consumed by nothing.

  The catwalks get the band on their two LONG sides only. A kerb across the short ends is a third of a metre of step at the junction a player is running through, and a body catching on it would have read as the movement code being wrong.

- **dot-match warned once per player per round, for ever.** `_begin_round` enqueues everybody and drains the queue regardless of `respawn_disabled`, so this game — which places its own players and deliberately has no `DotSpawnPoint` anywhere — got "no usable spawn point at all" four times at every round start. Fixed in dot-match rather than here: `choose_spawn` returns null when there are no points at all, because an empty list is a game that computes its own positions and `refresh_spawns` has already warned once if that was an accident. The selector's warning still fires for its real meaning, which is that it was given points and could not use one.

## The netcode

`game/net/` and `game/sc_module.gd`. What is worth having here is the shape.

**A player's own feet are the only predicted thing in the game.** The platforms, the props and the choppers are all server-authoritative. The platforms are the interesting case, because they are the floor — see Decision 1.

**A platform replicates in four numbers, and the state is not interpolated.** The lean moves continuously and a client between two snapshots should be between two leans; a platform that has come off its pillar takes its collider away on the tick the client is told, not smoothly over the next three. Half way between standing and gone is not a thing a floor can be.

**The clock carries what a client cannot count.** A client runs no platform model, so counting the platforms that are still up would count whatever it last heard — and that number is the most important one on this game's HUD, because it is what tells a player whether there is anywhere left to go.

**The weapons replicate as a counter, never as an event per shot.** An RPC per shot needs a reliable channel for something worthless if it arrives late, costs a packet per shot per watcher, and desynchronises from the state it belongs with — so a watcher sees the muzzle flash of a weapon the same snapshot says has been holstered. A four-bit counter inside the snapshot cannot do any of those: a watcher who missed a snapshot sees it jump by two and plays one flash instead of two, which is the correct amount of wrong. The magazine and the reserve are owner-only, because exact ammunition is information an opponent should not have.

**`examples/headless_net.tscn` is the real path minus the socket.** Two worlds, two managers, two bridges and two links with the RPC replaced by a callable — so the encoders, the seal, the snapshot build, the prediction and the reconciliation all run. The client is deliberately given a different tick rate and a different field than the server, because one process has one engine rate and one default configuration: two halves that agree by construction make every assertion that they agree pass for the wrong reason. Four of the findings above came from it, and it cannot see Godot's own RPC routing — that is what `dedicated.tscn` and a real client are for.

**The snapshot rate is thirty, against the twenty game-buses-from-hell uses.** Almost nothing here is predicted and the one thing a player has to read continuously is the lean of the floor they are standing on, which arrives only in a snapshot. At twenty, a platform's tilt updates in visible steps — and a step in the surface under your feet reads as the game stuttering.

## The chopper is a fourth chassis

`DotVehicleHover` returns early when its ground rays find nothing, which is the hovercraft being right and is exactly the state a helicopter spends its life in. `DotVehicleWheeled` needs wheels on a surface. So `ScCopter` is loaded through `DotVehicleDef.chassis_script_path`, which is the extension point dot-vehicle documents for a fourth kind, and nothing in that addon is forked or knows what a helicopter is.

**Three controls fit in a `DotVehicleCommand` and the fourth does not.** The collective is the throttle, the pedals are the steer, the rotor brake is the brake — and the cyclic goes in `DotVehicleInstance.meta`, because widening the command would be a breaking change across every game in the family for a field only an aircraft has.

**It holds itself up at exactly neutral, and that is what makes the control readable.** A machine whose neutral is a slow sink is one a player is fighting the whole time they are trying to aim at something. It does not arrest a climb, which is what the ceiling is for.

## Decision 7: no `class_name`, anywhere in this repository

Every script here is reached by a relative `preload`, every subclass by a relative `extends`, and every `res://` string this game writes about its own files goes through `ScPaths.rebase()`. That is not a style: **a mounted dot-cloud pack's `class_name` globals are not registered in the host**, so a delivered game that used one would mount, load its scenes, and have every script in it dead with nothing reporting a thing.

`dot-server-deploy/tools/check.sh` refuses a new one in any game repository, which is what keeps it that way.

## Decision 8: the world sets its own gravity, and the renderer is the one players use

Two things that live in `project.godot` do not travel with a delivered pack.

- **`physics/3d/default_gravity` is left at Godot's 9.8 here**, deliberately, and `ScConfig.gravity` is the number the game is tuned against. `ScGame._apply_gravity` writes it onto the world's own physics SPACE — the space rather than the setting, because a server and a client in one process are two worlds and a global would be one of them deciding for the other. It is also what makes the low-gravity special one line.
- **The client shell renders with `gl_compatibility`, because the browser is its target.** This project says so too, and its lighting was tuned by rendering under it.

## The art, and the one thing to know about vendoring it

Six prototype textures by role, eight models from two kits, and the weapon pack's own art. All CC0.

**The two `Textures/colormap.png` are different files with the same name**, so each kit is in its own folder. Flattening them paints the survival props in the car kit's palette, which is a plausible-looking wrong answer no assertion would ever catch.

**The models are loaded by PATH rather than instanced as an `ext_resource`**, which is a delivery decision. A `.tscn` records an external resource as an absolute path plus a UID and inside a mounted pack neither resolves; game-buses-from-hell shipped a round where every crate's mesh loaded and every crate's texture did not, which is a game that plays perfectly and appears to have shipped without art. `ScPropBody` loads through `rebase()` and puts the atlas on by hand where one is missing — which in a build does exactly nothing.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' -not -path './addons/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
godot --headless --path . res://examples/headless_run.tscn   # 14 sections, 106 checks
godot --headless --path . res://examples/dedicated.tscn      # 7 sections, 43 checks
godot --headless --path . res://examples/headless_net.tscn   # 14 sections, 134 checks
tools/shot.sh --view=field
tools/shot.sh --view=lean
tools/shot.sh --view=copter
tools/shot.sh --view=showdown
```

All three suites count sections **and** a total, and the total is the one that catches what the section counter cannot: a runtime error inside a section aborts that function and the section counter is already satisfied, because the section announced itself on the way in. Every guard was armed — the total raised by one and the run re-run — and every one fired.

**The render is not optional.** Four of the entries above were found by looking at a picture and are invisible to every assertion in this repository. `tools/shot.sh` is not `--headless`: Godot's headless display driver does no rendering at all, so a capture under it is a black PNG, which is worse than no screenshot because it looks like one.

**And neither suite reaches the deployment**, which is where five of game-buses-from-hell's bugs came from. That needs the real thing:

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
2. **A world model in a watcher's hands.** The weapon state replicates and `ZeeWeaponNet.apply` already takes a null model; what is missing is a character with a hand mount, and this game draws players as capsules.
3. **An identity layer**, if this game ever wants profiles and avatars. dot-game reports the gap at boot and carries on, which is a server where everybody is a guest.
