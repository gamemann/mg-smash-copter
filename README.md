# mg-smash-copter

Two to six teams stand on platforms balanced on single pillars, forty metres up, while a cannon in the middle throws things at them. Whoever is still up when the clock runs out is thrown into a corner of the sky with a weapon they did not choose, and the last team standing wins.

It is a first- and third-person multiplayer minigame built on the `dot-*` addon family: [dot-props](../dot-props) for everything the cannon throws, [dot-vehicle](../dot-vehicle) for the chopper, [dot-combat](../dot-combat) for health and hit registration, [dot-match](../dot-match) for the round and the sides, [dot-player-controller](../dot-player-controller) for the movement, [dot-net](../dot-net) for the replication, [dot-game](../dot-game) for the server wiring and [zee-dot-weapons](../zee-dot-weapons) for the twenty-seven weapons the second half is fought with.

## Running it

```bash
godot --path .                                                # play it, alone, against stand-ins
godot --headless --path . res://examples/headless_run.tscn    # the simulation, 95 checks
godot --headless --path . res://examples/dedicated.tscn       # as a real server, 43 checks
godot --headless --path . res://examples/headless_net.tscn     # over the wire, 122 checks
tools/shot.sh --view=field                                    # render a frame and look at it
```

The same client plays alone and plays online: with no server link in the registry it runs the world itself, and with one it predicts its own movement and draws everything else from what the server sends. There is no separate single-player build to keep in step.

## A round is two games

**The first two minutes are about footing.** Nobody can hurt anybody. Every platform is a 10.5 metre square balanced on a pillar 1.35 metres across, so it leans toward whatever is standing on it — and a platform past sixteen degrees comes off its pillar and takes everybody on it down forty metres to the floor.

**The last ninety seconds are a fight.** The survivors are teleported to corner pads in the sky, handed weapons drawn at random from the pack, and given four seconds before anybody can shoot. The corners are joined to a ring in the middle by catwalks, so holding your pad is safe and winning is not.

| Key | |
| --- | --- |
| **Shift** | walk. Running is the default and running is what tips a platform |
| **Space / Ctrl** | jump and crouch — and, in the chopper, up and down |
| **E** | get into, or out of, whatever is next to you |
| **F5** | swap between first and third person |
| **1–5** | weapon slots, in the showdown |
| **Y / U / V** | say something, say it to your side, hold to talk |

## Shift is a brake

This is the one control the map is built around, and it is the opposite of every other game in this family. Running is the default speed. A platform is destabilised in proportion to how hard the people on it are moving, so a running player leans it about three times as far as a standing one — which means the only way to cross a platform somebody is already standing on the far side of is to slow down. The key everybody already holds to go faster is the one that saves you.

## What the cannon throws

Eight props in four tiers, and the tier is the whole design. The tiers unlock over the round, so the opening is survivable and the last thirty seconds are not.

| Tier | | What it does to a platform |
| --- | --- | --- |
| 1 | Crate, tyre, cone | Wobbles it. Survivable by standing still, which is what it teaches |
| 2 | Barrel, boulder | Tips it. A barrel also goes off, and is the only thing in the first half that throws a player upward |
| 3 | Container, slab | Takes a corner off it, and adds to the damage the next one lands on |
| 4 | Monolith | Deletes it, with everybody on it, whatever its health |

The cannon **aims**. It picks a platform that is still standing, solves the arc that reaches it, and scatters the aim by a few metres — so every shot is a warning a player can read off the sky, and missing is still possible.

## Special rounds

A third of rounds start with one, and one can also arrive part way through a round that looked ordinary. Each is a set of multipliers over numbers the game already has, so a special that halves the gravity slows the props, softens the platforms and lengthens the jumps without one line of code mentioning any of the three.

`barrage` · `heavy` · `feather` (low gravity) · `slick` (ice) · `gale` (wind) · `quake` · `jelly` (loose pins) · `downpour` · `rush`

Two can overlap and they multiply, which is a legitimate and very funny thing to be in the middle of.

## Layouts

The field is re-rolled at the start of every round: eight arrangements of the same platforms, from the full grid down to two islands with nothing between them. Two of them park a chopper.

`full` · `checker` · `islands` · `spine` · `airfield` · `gauntlet` · `broadside` · `hollow`

A layout is six numbers and a list of cells, so the whole map travels to a client in about thirty bytes and both ends build the identical field in the identical order.

## The chopper

Two seats. The pilot flies it with the keys they already walk with — jump climbs, crouch descends, A and D are the pedals, W and S are the cyclic — and the left trigger **drops a crate** on whatever is underneath. The passenger can shoot.

It is not either of the two chassis dot-vehicle ships: a wheeled one needs wheels on the ground and a hovercraft refuses to thrust when there is nothing under it, which is exactly the state a helicopter spends its life in. `ScCopter` is a fourth kind, loaded through the addon's own extension point, and nothing in dot-vehicle knows what a helicopter is.

## Configuring a server

Every number is a cvar or an environment variable, layered `defaults < JSON < environment < command line` like everything else in this family. Two dozen of them are live and write through to the running world, because finding a server's numbers means moving one between rounds with people watching.

```
sc_survival_seconds 150     // longer first half
sc_teams 4                  // four sides, four corners
sc_stiffness 4.0            // wobblier platforms
sc_motion_gain 3.0          // running matters more
sc_cannon_interval 1.2      // a busier sky
sc_cannon_max_tier 2        // nothing that deletes a platform outright
sc_special_chance 60        // most rounds are strange
sc_chopper 0                // no chopper on any layout
sc_min_players 6            // keep six in the round with stand-ins
```

`sc_status`, `sc_net`, `sc_layouts` and `sc_specials` say what the server is doing. An empty server fills itself with stand-ins, because a round needs two sides to exist at all and one person alone would otherwise watch a round start and end several times a second.

## Playing it against a server

It is a dedicated-server game, delivered the way every other game in this family is: published as a signed content pack and downloaded by the client shell on connect, so a new version needs no new client build.

```bash
# in dot-server-deploy
godot --headless --path ../mg-smash-copter --import
./server pack smash --source games/mg-smash-copter
./server --game smash
# then connect the client shell to 127.0.0.1:6070
```

### What replicates, and what does not

| | |
| --- | --- |
| A player's own movement | **Predicted**, and corrected. The only thing in the game that is |
| Everybody else's movement | Replicated and interpolated |
| **The platforms** | Four numbers each — two angles, a height and a state — decided entirely by the server. A platform is the FLOOR, and a floor that two machines disagreed about is a player falling through something their own machine says is holding them up |
| Props and choppers | Server-authoritative, never predicted. Two rigid-body solvers diverge within a second |
| The pilot | Not predicted either: while somebody is flying, their controller has no answer to predict |
| How many platforms are left | An event twice a second. A client runs no platform model, so it cannot count them — and that number is the most important one on the HUD |

## The art

Every surface is [Kenney's](https://kenney.nl) **Prototype Textures**, six files, one per role — the deck, the pillar, the cannon, the corners, the hazard and the pads. Everything the cannon throws is from the Survival and Car kits. The weapons are the pack's own. All of it is **CC0**, which asks for nothing and permits everything; each kit's licence ships beside the files it covers.

The chopper is geometry, because there is no helicopter in any of the kits and a machine that looked like a van would have been worse.

The map itself is built in code. A grid of squares on pillars, a cylinder in the middle and a ring of pads in the sky is not something worth authoring in a scene file, and a map that is a description rather than a build is a map a client can be told about in one message.

## What does not work yet

- **Weapons are not replicated.** The server decides every shot, health and deaths reach every client, and the HUD is told what each survivor drew — but a watcher does not see somebody else's gun in their hands, and the local view model is drawn from the client's own rig rather than from the server's state. `ZeeWeaponNet` is the seam and it is four fields.
- **Lag compensation is off**, and it says so in `sc_module.gd`. dot-combat wants a rewind and a restore callable; this game has not written the history of hitbox transforms they need. Everything resolves against the present.
- **No profiles and no avatars.** dot-game reports the missing identity layer and carries on, which is a server where everybody is a guest.
