# 3v3 Tactical FPS

An original 3v3 tactical first-person shooter built in Godot.

> **Status: Chapter 1 complete.**
> The project structure, phase state machine, data resources, boot scene and
> debug overlay all exist, run, and pass a full validation pass. There is no
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

> **On the engine version.** The brief specified Godot 4.5; the editor installed
> here is 4.7.2, so that is what everything was built and verified against. The
> code sticks to APIs that already existed in 4.5 — `Node`, `Resource`,
> `ENetMultiplayerPeer`, `@export`, typed signals, `DirAccess`, `CanvasLayer` —
> and deliberately uses no 4.6/4.7-only feature, so the sources should open in
> 4.5. That has **not** been proven by running 4.5, so if 4.5 is a hard
> requirement, open the project in 4.5 once before starting Chapter 2.

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
│   │                      #   + placeholder_environment.tscn (temporary)
│   ├── player/            # Player, camera, weapon holder
│   ├── weapons/           # Weapon scenes
│   └── ui/                # HUD, scoreboard, menus
│                      #   + dev_overlay.tscn (temporary, see Debug overlay)
│
├── scripts/               # All .gd files
│   ├── core/              # Cross-cutting: EventBus, GameConfig, boot screen
│   ├── game/              # GameManager, GameState, MatchState, MatchRules
│   │   └── states/        # One file per phase - see Architecture
│   ├── network/           # Multiplayer / netcode
│   ├── player/            # Player controller, camera, movement
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

---

## Running the project

The main scene is `scenes/core/main.tscn`, so **F5** runs the game. It boots
into the main menu, where you can host or join a session. **Host game** on one
instance and **Join game** on a second to see the network layer work.

Once you leave the title screen, the **debug overlay** appears down the right
side. It shows the current game state, which screen is currently routed in, the
live match rules, the score, and whether networking is active. It also offers a
button for every legal next phase, so you can walk the whole match flow by hand
without waiting on timers.

Behind the overlay is a grey-box arena — a walled floor, a large apron of
surrounding ground, some cover, a sky and a fixed overview camera. It exists
purely to prove the project renders, lights and simulates. There is no player
in it; nothing moves. Chapter 7 replaces it with the real map.

**There is still no playable game here.** No controller, no input actions, no
weapons, no combat — all of that starts in Chapter 2. What works today is the
foundation: the phase machine, the routing, the data, the network session.

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
to, whether networking is active, the live match rules and the score, plus
buttons that force the state machine into any legal phase.

**It is disposable, and deliberately isolated so that removing it is trivial.**
Either set `Main.DEV_OVERLAY_ENABLED` to `false`, or delete the two
`dev_overlay` files and the four lines in `main.gd` that reference them. Nothing
in the permanent router depends on it, and nothing outside its own script should
ever come to depend on it. Chapter 8 replaces it with a real HUD.

`scenes/game/placeholder_environment.tscn` is the grey box behind it, and is
equally disposable — Chapter 7 replaces it. It is a separate scene rather than
part of `main.tscn` so that replacing the map is deleting one file, not
unpicking nodes out of the router.

Within that scene the split is deliberate:

- **Authored in the `.tscn`** — sky, sun, camera, apron, floor, walls. These are
  things you want to click and adjust in the Inspector.
- **Generated in the script** — the eight cover blocks. They are near-identical,
  and a loop is a better home for them than a dozen copy-pasted nodes that all
  have to be deleted again in Chapter 7.

Two things are easy to get wrong in a placeholder and are worth doing properly
now rather than rediscovering in Chapter 2:

- **Every visible box has a matching `CollisionShape3D` sized separately from
  its `BoxMesh`.** Editing the mesh to look right should never silently change
  what a player can walk into.
- **Both spawn points already exist as `Marker3D`s** (`AlphaSpawn`, `BravoSpawn`),
  so Chapter 4 can assign teams without this scene having to change.

The floor's top surface sits at exactly `y = 0`, which is where Chapter 2's
player controller is written to expect solid ground.

---

## Roadmap

Each chapter builds on the last.

- [x] **Ch. 1 — Foundation:** project structure, conventions, version control,
      phase state machine, autoloads, data resources, boot scene, debug overlay
- [ ] **Ch. 2 — Player controller & input:** input map, movement, camera, collision
- [ ] **Ch. 3 — Weapons & combat:** firing, ballistics, damage, hit feedback
- [ ] **Ch. 4 — Multiplayer:** player replication, teams, lobby, sync
- [ ] **Ch. 5 — Round system:** buy phase, live round, score, win conditions
- [ ] **Ch. 6 — Abilities:** original agent abilities and gadgets
- [ ] **Ch. 7 — Map & level design:** original map, layout, spawns, cover
- [ ] **Ch. 8 — UI, art & audio:** HUD, menus, identity, VFX, sound
- [ ] **Ch. 9 — Testing & ship:** optimisation, balance, final export build

### Carried forward from Chapter 1

Deliberately left out, so later chapters do not have to unpick them:

- **No player controller, camera or input actions.** Chapter 2's job — the next
  thing to build. The grey box already has real collision and a floor whose top
  surface sits at exactly `y = 0`, so there is something to walk on and into.
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
