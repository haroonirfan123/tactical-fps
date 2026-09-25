# 3v3 Tactical FPS

An original 3v3 tactical first-person shooter built in Godot.

> **Status: Chapter 2 — Core Architecture.**
> The project structure and the game state machine exist and run. There is no
> player, weapon or HUD yet. See [Roadmap](#roadmap) for what comes next.

---

## Requirements

| Item       | Value                             | Why                                        |
| ---------- | --------------------------------- | ------------------------------------------ |
| Engine     | **Godot 4.7.2-stable**            | Confirm with your installed version        |
| Renderer   | Forward+                          | Best lighting/shadows for a tactical FPS   |
| Physics    | Jolt Physics                      | Deterministic, fast, FPS-oriented          |

These three are already configured in `project.godot`. Do not switch renderer or
physics engine later — it invalidates baked lighting and physics tuning.

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
│   └── weapons/           # Weapon stat tables
│
├── scenes/                # .tscn files, mirrored from scripts/
│   ├── core/              # Boot, main menu, settings, loading screen
│   ├── game/              # Match scene, round flow, spawn logic
│   │                      #   + placeholder_environment.tscn (temporary)
│   ├── player/            # Player, camera, weapon holder
│   ├── weapons/           # Weapon scenes
│   └── ui/                # HUD, scoreboard, menus
│
├── scripts/               # All .gd files
│   ├── core/              # Cross-cutting: EventBus, GameConfig, boot screen
│   ├── game/              # GameManager, GameState, MatchState, phases
│   │   └── states/        # One file per phase - see Architecture
│   ├── network/           # Multiplayer / netcode
│   ├── player/            # Player controller, camera, movement
│   ├── ui/                # HUD and menu logic
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
| `PlayerState` | `RefCounted` | Yes | Health, team, alive, K/D/A |
| `MatchState` | `RefCounted` | Yes | Round number, scores, winner |
| `Team` | `RefCounted` | No | The `Side` enum and helpers |

`WeaponData` is a `Resource` because its values are authored in the Inspector
and saved to disk, and one instance is shared by every player using that
weapon. The other three are `RefCounted` because they are live state that
changes as the game runs, and each needs its own instance.

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

---

## Running the project

The main scene is `scenes/core/main.tscn`, so **F5** runs the game. It boots
into the main menu, where you can host or join a session. **Host game** on one
instance and **Join game** on a second to see the network layer work.

From the lobby, the dev harness appears. It shows the current phase and offers
a button for every legal next phase, so you can walk the whole match flow by
hand without waiting on timers.

Behind the harness is a grey-box arena — a walled floor, a large apron of
surrounding ground, some cover, a sky and a fixed overview camera. It exists
purely to prove the project renders, lights and simulates. There is no player
in it; nothing moves. Chapter 7 replaces it with the real map.

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

### A note on the dev harness and the grey box

`scenes/core/main.tscn` is the permanent root: screens are swapped in and out
as its children, never by replacing it. Routing has to outlive whatever it
routes to — a router that swapped itself out would leave nothing to handle the
next phase change.

Its panel is a development harness, not a menu. It exists so the state machine
can be driven before there is a player or a HUD. Chapter 8 replaces it; nothing
should come to depend on it.

`scenes/game/placeholder_environment.tscn` is the grey box behind it, and is
equally disposable — Chapter 7 replaces it. It is a separate scene rather than
part of `main.tscn` so that replacing the map is deleting one file, not
unpicking nodes out of the router.

Within that scene the split is deliberate:

- **Authored in the `.tscn`** — sky, sun, camera, floor, walls. These are things
  you want to click and adjust in the Inspector.
- **Generated in the script** — the eight cover blocks. They are near-identical,
  and a loop is a better home for them than a dozen copy-pasted nodes that all
  have to be deleted again in Chapter 7.

Two things are easy to get wrong in a placeholder and are worth doing properly
now rather than rediscovering in Chapter 3:

- **Every visible box has a matching `CollisionShape3D` sized separately from
  its `BoxMesh`.** Editing the mesh to look right should never silently change
  what a player can walk into.
- **Both spawn points already exist as `Marker3D`s** (`AlphaSpawn`, `BravoSpawn`),
  so Chapter 4 can assign teams without this scene having to change.

---

## Roadmap

Each chapter builds on the last. This foundation is Chapter 1.

- [x] **Ch. 1 — Foundation:** project structure, conventions, version control
- [x] **Ch. 2 — Core architecture:** phase state machine, autoloads, data
      classes, boot scene
- [ ] **Ch. 3 — Weapons & combat:** firing, ballistics, damage, hit feedback
- [ ] **Ch. 4 — Multiplayer:** player replication, teams, lobby, sync
- [ ] **Ch. 5 — Round system:** buy phase, live round, score, win conditions
- [ ] **Ch. 6 — Abilities:** original agent abilities and gadgets
- [ ] **Ch. 7 — Map & level design:** original map, layout, spawns, cover
- [ ] **Ch. 8 — UI, art & audio:** HUD, menus, identity, VFX, sound
- [ ] **Ch. 9 — Testing & ship:** optimisation, balance, final export build

### Carried forward from Chapter 2

Deliberately left out, so later chapters do not have to unpick them:

- **No player controller, camera or input actions.** Chapter 3's job.
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

### Originality note

Everything user-facing will be original work: the game title, agent and ability
names, weapon names, map names, level layouts, art direction, and UI. The genre
is *tactical FPS*; the content is ours. Naming and visual identity are handled in
Chapters 6 and 8 — until then, `3v3 Tactical FPS` is a working title only.
