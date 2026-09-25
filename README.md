# 3v3 Tactical FPS

An original 3v3 tactical first-person shooter built in Godot.

> **Status: Chapter 2 complete.**
> The project structure, phase state machine, data resources, boot scene and
> debug overlay exist from Chapter 1. Chapter 2 adds a reusable first-person
> `Player` with full movement, mouse look, crouch, jump, step-up and slope
> handling, and the game boots straight into a test environment to exercise it.
> There is no weapon, combat or HUD yet. See [Roadmap](#roadmap) for what comes
> next.

---

## Requirements

| Item       | Value                             | Why                                        |
| ---------- | --------------------------------- | ------------------------------------------ |
| Engine     | **Godot 4.7.2-stable**            | Confirm with your installed version        |
| Renderer   | Forward+                          | Best lighting/shadows for a tactical FPS   |
| Physics    | Jolt Physics                      | Deterministic, fast, FPS-oriented          |

These three are already configured in `project.godot`. Do not switch renderer or
physics engine later — it invalidates baked lighting and physics tuning.

> **On the engine version.** The brief specified Godot 4.5; the editor installed
> here is 4.7.2, so that is what everything was built and verified against. The
> code sticks to APIs that already existed in 4.5 — `Node`, `Resource`,
> `ENetMultiplayerPeer`, `@export`, typed signals, `DirAccess`, `CanvasLayer`,
> `CapsuleShape3D`, `test_move`, `move_and_slide` — and deliberately uses no
> 4.6/4.7-only feature, so the sources should open in 4.5. That has **not** been
> proven by running 4.5, so if 4.5 is a hard requirement, open the project in 4.5
> once and re-run the movement checks before building on top of it.

---

## Project structure

Three top-level rules:

1. **Code goes in `scripts/`.**
2. **Scenes go in `scenes/`.**
3. **Everything else (art, audio, data) goes in `assets/`.**

```
res://
├── project.godot          # Engine configuration — edit via the Editor UI
├── icon.svg               # Window icon
│
├── data/                  # Designer-editable .tres data (see below)
│   ├── match_rules.tres   # Rounds, phase lengths, players per team
│   └── weapons/           # Weapon stat tables
│
├── scenes/                # .tscn files, mirrored from scripts/
│   ├── core/              # Boot, main menu, settings, loading screen
│   ├── game/              # Match scene, round flow, spawn logic
│   │   ├── playtest.tscn  # Ch. 2 — boots into this
│   │   └── placeholder_environment.tscn (temporary)
│   ├── player/            # Player, camera, weapon holder
│   │   └── player.tscn    # Ch. 2 — the reusable first-person body
│   ├── weapons/           # Weapon scenes
│   └── ui/                # HUD, scoreboard, menus
│                      #   + dev_overlay.tscn (temporary, see Debug overlay)
│
├── scripts/               # All .gd files
│   ├── core/              # Cross-cutting: EventBus, GameConfig, boot screen
│   ├── game/              # GameManager, GameState, MatchState, MatchRules
│   │   │   └── states/    # One file per phase - see Architecture
│   │   └── playtest.gd    # Ch. 2 — spawns the player into the test arena
│   ├── network/           # Multiplayer / netcode
│   ├── player/            # Player controller, camera, movement
│   │   └── player.gd      # Ch. 2 — the whole controller
│   ├── ui/                # HUD and menu logic
│   │   └── dev_overlay.gd # Debug readout (temporary)
│   └── weapons/           # Weapon behaviour, ballistics, damage
│
└── assets/                # All non-code content
    ├── audio/             # SFX, music, ambience
    ├── characters/        # Player models, textures, rigs
    ├── effects/           # Particles, VFX, decals
    ├── maps/              # Map scenes and map-specific assets
    ├── materials/         # Shared .tres materials and shaders
    ├── ui/                # UI themes, icons, fonts
    └── weapons/           # Weapon models, textures, sounds
```

### About the `.gitkeep` files

Most of these folders are currently empty. Git does not track empty folders, so
each one contains an empty `.gitkeep` file to keep it alive. **Ignore them** —
delete them as soon as you add a real file to that folder. They are not part of
the game.

---

## Conventions

Keep these consistent so the project stays readable.

**Scene and script pairs.** A script lives in `scripts/<area>/` and its scene in
`scenes/<area>/`, sharing a name:

```
scripts/player/player_controller.gd   <->   scenes/player/player_controller.tscn
```

**Naming.**

| Thing                | Style                        | Example                        |
| -------------------- | ---------------------------- | ------------------------------ |
| Files                | `snake_case.gd` / `.tscn`    | `weapon_pistol.tscn`           |
| Classes               | `PascalCase` (`class_name`)  | `class_name WeaponController`  |
| Functions & variables | `snake_case`                 | `func take_damage(amount)`     |
| Private members       | leading underscore            | `var _health := 100`           |
| Constants & enums     | `SCREAMING_SNAKE_CASE`       | `const MAX_HEALTH := 100`      |
| Signals               | `snake_case`, past tense     | `signal player_died`           |
| Booleans              | `is_` / `has_` prefix        | `var is_alive := true`         |

**`data/` vs `assets/`.** `data/` holds small, hand-editable `.tres` resource
files that designers tweak — weapon stat tables, ability definitions, map
metadata. Anything large or binary belongs in `assets/`.

### The data types

Four data classes, split by *when they change* rather than by what they hold.
That distinction is the whole design:

| Class | Base | Changes at runtime? | Holds |
| --- | --- | --- | --- |
| `WeaponData` | `Resource` | No — authored, saved as `.tres` | Damage, fire rate, magazine, price |
| `MatchRules` | `Resource` | No — authored, saved as `.tres` | Round length, rounds to win, team size |
| `PlayerState` | `RefCounted` | Yes | Health, team, alive, K/D/A |
| `MatchState` | `RefCounted` | Yes | Round number, scores, winner |
| `Team` | `RefCounted` | No | The `Side` enum and helpers |

`WeaponData` and `MatchRules` are `Resource`s because their values are authored
in the Inspector, saved to disk, and shared. The other three are `RefCounted`
because they are live state that changes as the game runs, and each needs its
own instance.

**Tunables live in `data/`, not in code.** Phase lengths, rounds-to-win and
players-per-team are all fields on `MatchRules` in
`data/match_rules.tres`. Retuning a match is a data edit. "3v3" in particular
is stated exactly once — `NetworkManager.get_max_players()` derives the
session cap from `players_per_team`, so the two can never drift apart.

**`load()` is cached — weapon stats are shared, not copied.** Every player
holding the same weapon gets the *same* `WeaponData` object. Writing
`weapon.damage = 50` at runtime would buff everyone using it. Per-player state
that genuinely changes (rounds left, trigger held, recoil) belongs in a
separate runtime object in Chapter 3, not on `WeaponData`.

```gdscript
var halberd := load("res://data/weapons/halberd.tres") as WeaponData
print(halberd.display_name, " ", halberd.damage_at_distance(distance))
```

**Extending built-in types.** Avoid `extends CharacterBody3D` scattered across
files. Write one base class per area (e.g. `scripts/player/player_body.gd`) and
extend that. It keeps shared behaviour in one place.

`Player` currently extends `CharacterBody3D` directly, which is the one place
this rule is bent: there is exactly one body type, so a base class would be a
file containing nothing but a class declaration. If Chapter 3 adds a second kind
of body — a turret, a vehicle, a death ragdoll — that is when
`scripts/player/player_body.gd` starts earning its keep, and `Player` should be
re-parented onto it then rather than before.

---

## Running the project

The main scene is `scenes/core/main.tscn`, so **F5** runs the game. As of
Chapter 2 it boots **straight into the playtest arena** with a player already
spawned and the mouse already captured — there is no menu in the way yet. Set
`Main.BOOT_INTO_PLAYTEST` to `false` in `scripts/core/main.gd` to get the
Chapter 1 main menu back.

| Key                | Action                                       |
| ------------------ | -------------------------------------------- |
| `W` `A` `S` `D`    | Move, relative to where you are looking      |
| `Shift` (hold)     | Sprint                                       |
| `Ctrl` or `C`      | Crouch (hold)                                |
| `Space`            | Jump                                         |
| `Mouse`            | Look                                         |
| `Escape`           | Release the mouse (click the window to recapture) |

Every binding is an action in the Input Map, not a raw keycode in the script,
so all of them are remappable in one place.

The test arena is the Chapter 1 grey box plus three things a movement controller
has to be tested on and that a flat floor cannot catch: a **15° ramp**, a
**4-step staircase** (0.3 m rises), and a **low overhang** with 1.2 m of
clearance that a crouched player fits under and a standing one does not. Walk
into each to confirm the controller behaves; all three are generated by
`placeholder_environment.gd` and are deleted along with the rest of the
placeholder in Chapter 7.

Once you leave the title screen, the **debug overlay** appears down the right
side. It shows the current game state, which screen is routed in, the live
match rules, the score, whether networking is active, the frame rate, the
player's position and speed, and the player's movement state. It also offers a
button for every legal next phase, so you can walk the whole match flow by hand
without waiting on timers.

**There is still no playable game here.** You can walk, look, crouch and jump,
but there is no weapon, no combat, no HUD and no networking of the player — all
of that starts in Chapter 3.

---

## The player controller

`scenes/player/player.tscn` is one self-contained, reusable scene. Instantiate
it as many times as you like; nothing about it is unique or global.

```
Player (CharacterBody3D)   collision_layer 2, collision_mask 1
├── Collision (CollisionShape3D)   capsule; height and Y follow the stance
│   └── BodyMesh (MeshInstance3D)  hidden by default; visualises the collider
└── Head (Node3D)                 Y = eye height
    └── Camera3D                  fov 90, near 0.05
```

**Yaw is on the body, pitch is on the head.** That split is deliberate: the
body's basis stays yaw-only, so a player looking up at the sky cannot tilt
their own collision capsule, and movement stays on the horizontal plane no
matter what the camera is doing.

**Crouch resizes the collider, it does not scale the node.** Scaling would
scale the collision radius and the camera along with the height, and would
make the player fit through gaps that a real body should not. A single
`_stance` value between `0` and `1` drives the capsule height, its `Y`, the
camera height and the reported state together, so they cannot drift apart.
Standing up is refused by a real overlap test when there is a ceiling in the
way.

**Movement is velocity-based and relative to facing**, with separate
walk/sprint/crouch speeds and separate ground and air rates:

| Export                    | Default | Notes                                      |
| ------------------------- | ------- | ------------------------------------------ |
| `walk_speed`              | 5.0     | m/s                                        |
| `sprint_speed`            | 8.0     | Hold Shift. No stamina, by design          |
| `crouch_speed`            | 2.6     | Crouch wins over sprint if both are held   |
| `ground_acceleration`     | 55.0    | m/s² toward the target speed               |
| `ground_deceleration`     | 70.0    | Stops quickly; no ice                       |
| `air_control`             | 0.22    | Fraction of ground accel usable airborne  |
| `air_deceleration`        | 2.0     | Low, so air momentum is mostly preserved   |
| `gravity`                 | 18.0    | m/s²                                       |
| `jump_velocity`           | 5.5     | m/s                                        |
| `terminal_fall_speed`     | 40.0    | Clamp so long falls stay sane              |
| `coyote_time`             | 0.12    | Grace period just after walking off a ledge|
| `step_height`             | 0.4     | Tallest ledge walked up without jumping    |
| `stand_height`            | 1.8     | Capsule height when standing               |
| `crouch_height`           | 1.1     | Capsule height when crouched               |
| `body_radius`             | 0.35    | Capsule radius                             |
| `stand_eye_height`        | 1.62    | Camera height standing                     |
| `crouch_eye_height`       | 0.95    | Camera height crouched                     |
| `stance_change_speed`     | 9.0     | How fast the crouch transition eases        |
| `pitch_limit_degrees`     | 89.0    | Stops the camera flipping at the poles      |
| `sensitivity_scale`       | 0.003   | Multiplies `GameConfig.mouse_sensitivity`   |
| `input_enabled`           | `true`  | The multiplayer seam — see below             |
| `capture_mouse_on_ready`  | `true`  | Set `false` for a remote player              |

None of these are Valorant's numbers; they are tuned for a deliberate,
weighty feel with no sliding and no air-strafing. Change any of them in the
Inspector on the scene instance and the controller uses it — nothing is
hard-coded in the script.

`GameConfig` already owned `mouse_sensitivity`, `invert_mouse_y` and
`field_of_view` from Chapter 1, so the player does not re-declare them. It
adds only `sensitivity_scale` as a per-player multiplier, which leaves the
global preference and the per-player scale as two separate things that can be
retuned independently.

### The multiplayer seam

This is the part Chapter 4 should not have to redesign.

- `set_input_enabled(false)` stops the player reading input **and releases the
  mouse**, while gravity and collision keep running normally. That single flag
  turns the same scene into a remote, server-driven player.
- The player owns its own `PlayerState`. There is no global player variable, no
  movement singleton, and `GameManager` does not know the player exists.
- **No team is hard-coded anywhere.** Nothing in the controller refers to a
  side, a roster or a spawn.
- `teleport_to(point, facing_yaw)` clears velocity and the coyote timer, so a
  respawn never inherits the momentum of whatever killed the player.

Replication, authority and interpolation are all still Chapter 4's work.

---

## Architecture

### The four autoloads

Only genuinely global, single-instance things are autoloads. Everything else
is an object owned by something else — that is what keeps the list this short.

| Autoload          | Owns                                                        |
| ----------------- | ----------------------------------------------------------- |
| `GameManager`     | The phase the game is in, and the `MatchState` for it        |
| `NetworkManager`  | The `ENetMultiplayerPeer` and all connection state           |
| `GameConfig`      | Player preferences, saved to `user://settings.cfg`           |
| `EventBus`        | Signals that more than one unrelated system needs            |

**Not autoloads, on purpose:**

- `MatchState` — there is only one match, so `GameManager` owns it. A singleton
  would give the game a second, competing way to ask "what's the score?".
- `PlayerState` — every player needs their own. A singleton is wrong by
  definition; each player node owns one.
- The phase states — only one is alive at a time, and `GameManager` owns it.

### The phase state machine

`GameManager` answers exactly one question: *what phase are we in?*

```
MAIN_MENU → LOBBY → WARMUP → ROUND_START → ROUND_ACTIVE
                             ↑                 │
                             └──── ROUND_END ←─┘
                                  │
                                  └──→ MATCH_END → (LOBBY | MAIN_MENU)
```

Each phase is a small class in `scripts/game/states/` extending `GameState`,
with `enter()`, `update()` and `exit()` hooks. `GameManager` holds no
`if phase == ...` branches, so adding a phase is a new file plus two entries —
not an edit to a conditional six other systems have to be read alongside.

Legal moves are declared in one table, `GameManager.ALLOWED_TRANSITIONS`, and
anything not in it is refused with a warning. That is what stops a round from
starting twice or combat beginning mid-buy-phase.

```gdscript
if GameManager.is_in(GamePhase.Phase.ROUND_ACTIVE):
    spawn_the_players()

GameManager.state_changed.connect(_on_phase_changed)
```

### Adding a phase

1. Create a script in `res://scripts/game/states/` extending `GameState`.
2. Override the hooks you need.
3. Add the value to `GamePhase.Phase`.
4. Register the script in `GameManager.STATE_SCRIPTS` and its moves in
   `GameManager.ALLOWED_TRANSITIONS`.

### Communication

Use `EventBus` for things several unrelated systems need to hear about, so
they do not each need a reference to whatever raised the event. If exactly one
system cares, that system should just call the other one directly. `EventBus`
is not a dumping ground — if you add a signal nobody listens to, delete it.

### The debug overlay and the grey box

`scenes/core/main.tscn` is the permanent root: screens are swapped in and out
as its children, never by replacing it. Routing has to outlive whatever it
routes to — a router that swapped itself out would leave nothing to handle the
next phase change.

`scenes/ui/dev_overlay.tscn` is the debug overlay shown once you leave the
title screen. It reports the current game state, the scene currently routed
to, whether networking is active, the live match rules, the score, the frame
rate and the player's position and movement state, plus buttons that force the
state machine into any legal phase.

**It is disposable, and deliberately isolated so that removing it is trivial.**
Either set `Main.DEV_OVERLAY_ENABLED` to `false`, or delete the two
`dev_overlay` files and the four lines in `main.gd` that reference them. Nothing
in the permanent router depends on it, and nothing outside its own script should
ever come to depend on it. The player controller does not reference the overlay
in either direction. Chapter 8 replaces it with a real HUD.

`scenes/game/playtest.tscn` is what the game routes to while in a match phase.
It instances the placeholder environment, spawns the Player at `AlphaSpawn`,
turns off the placeholder's overview camera, and exposes the player as an
`@export` so later chapters can reach it. It is a separate scene from
`main.tscn` so the router survives whatever it routes to.

`scenes/game/placeholder_environment.tscn` is the grey box behind it, and is
equally disposable — Chapter 7 replaces it. It is a separate scene rather than
part of `main.tscn` so that replacing the map is deleting one file, not
unpicking nodes out of the router.

Within that scene the split is deliberate:

- **Authored in the `.tscn`** — sky, sun, camera, apron, floor, walls. These are
  things you want to click and adjust in the Inspector.
- **Generated in the script** — the eight cover blocks, plus the Chapter 2 ramp,
  staircase and overhang. They are near-identical, and a loop is a better home
  for them than a dozen copy-pasted nodes that all have to be deleted again in
  Chapter 7.

Two things are easy to get wrong in a placeholder and are worth doing properly
now rather than rediscovering in Chapter 3:

- **Every visible box has a matching `CollisionShape3D` sized separately from
  its `BoxMesh`.** Editing the mesh to look right should never silently change
  what a player can walk into.
- **Both spawn points already exist as `Marker3D`s** (`AlphaSpawn`, `BravoSpawn`),
  so Chapter 4 can assign teams without this scene having to change.

The floor's top surface sits at exactly `y = 0`, which is where the player
controller expects solid ground. The ramp's low end is seated so that its top
surface is also flush with `y = 0`, for the same reason.

---

## Roadmap

Each chapter builds on the last.

- [x] **Ch. 1 — Foundation & Project Architecture:** project structure, conventions,
      version control, phase state machine, autoloads, data resources, boot
      scene, debug overlay
- [x] **Ch. 2 — FPS Player Controller:** input map, movement, camera, jumping,
      sprinting, crouching
- [ ] **Ch. 3 — Weapons & Combat:** guns, shooting, damage, health, headshots,
      reloads
- [ ] **Ch. 4 — 3v3 Multiplayer:** networking, players, synchronization, teams
- [ ] **Ch. 5 — Tactical Round System:** rounds, objectives, timers, victory
      conditions
- [ ] **Ch. 6 — Unique Game Mechanics:** original abilities/gadgets that make
      the game stand out
- [ ] **Ch. 7 — Map & Level Design:** the actual 3v3 map, sites, cover, spawns,
      layout
- [ ] **Ch. 8 — UI & Presentation:** HUD, menus, scoreboard, buy screen, round
      UI
- [ ] **Ch. 9 — Art, Audio & Polish:** models, VFX, sounds, animations, visual
      identity
- [ ] **Ch. 10 — Testing, Optimization & Final Build:** multiplayer testing,
      bug fixing, optimization, packaging/submission

### Carried forward from Chapter 1

Deliberately left out, so later chapters do not have to unpick them:

- **No replication.** `NetworkManager` covers session setup and peer
  bookkeeping only — no player spawning, ownership or authority. Chapter 4's
  job, and a clean gap is much easier to fill than half-built replication.
- **No team assignment.** It belongs with the roster in Chapter 4, not bolted
  onto connection setup now.
- **No combat.** `ROUND_ACTIVE` owns the round clock and is the only place a
  round can end; nothing decides who won yet.
- **Plain default-controls UI.** Presentation is Chapter 8's job.
- **No runtime weapon object.** `WeaponData` holds a weapon's stats and nothing
  else. Firing, recoil, reload progress and ammo in the magazine are Chapter
  3's job, and they live in a separate per-player object — not on `WeaponData`,
  which is shared and must stay read-only.
- **Three weapons, no roster.** `data/weapons/` holds a sidearm, an SMG and a
  rifle as working examples of the `WeaponData` format. The real weapon list
  and the buy menu that selects from it are Chapter 5's job.

### Carried forward from Chapter 2

Also deliberately left out:

- **No weapon holder, viewmodel or camera shake.** The player has no
  `WeaponMount` child yet. Chapter 3 adds it, and it should attach under `Head`
  so the weapon follows the camera automatically.
- **No health, damage or death.** The controller has no concept of being hit.
  `PlayerState` exists and is owned by the player, ready for health and alive /
  dead flags, but nothing writes to it yet. The `MovementState.DEAD` enum value
  exists for the same reason.
- **No replication or interpolation.** The `input_enabled` seam is the hook, but
  no snapshots are sent and no remote player is smoothed. Chapter 4's work.
- **No respawn path.** `teleport_to()` exists and is tested, but nothing calls
  it except the tests. Chapter 4 owns when a respawn happens.
- **No collider with the world.** The player capsule is a plain `CapsuleShape3D`
  and only collides with layer 1. It passes through other players. Chapter 4
  decides the player-collision layer and whether players block each other.
- **The game boots into the playtest, not the menu.** `Main.BOOT_INTO_PLAYTEST`
  is `true`. Flip it to `false` once there is a menu worth landing on.

### Originality note

Everything user-facing will be original work: the game title, agent and ability
names, weapon names, map names, level layouts, art direction, and UI. The genre
is *tactical FPS*; the content is ours. Naming and visual identity are handled in
Chapters 6 and 8 — until then, `3v3 Tactical FPS` is a working title only.
