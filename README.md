# 3v3 Tactical FPS

An original 3v3 tactical first-person shooter built in Godot.

> **Status: Chapter 1 — Project Foundation.**
> This repository currently contains only the project structure and conventions.
> No gameplay systems exist yet. See [Roadmap](#roadmap) for what comes next.

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
│
├── scenes/                # .tscn files, mirrored from scripts/
│   ├── core/              # Boot, main menu, settings, loading screen
│   ├── game/              # Match scene, round flow, spawn logic
│   ├── player/            # Player, camera, weapon holder
│   ├── weapons/           # Weapon scenes
│   └── ui/                # HUD, scoreboard, menus
│
├── scripts/               # All .gd files
│   ├── core/              # Engine-wide singletons and helpers
│   ├── game/              # Match, round, score, win conditions
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

**Extending built-in types.** Avoid `extends CharacterBody3D` scattered across
files. Write one base class per area (e.g. `scripts/player/player_body.gd`) and
extend that. It keeps shared behaviour in one place.

---

## Running the project

There is **no main scene set yet** — this is expected at this stage. One will be
added in Chapter 2 when there is something to launch. Until then, open a scene
from the FileSystem dock and press **F6** to run that scene directly.

---

## Roadmap

Each chapter builds on the last. This foundation is Chapter 1.

- [x] **Ch. 1 — Foundation:** project structure, conventions, version control
- [ ] **Ch. 2 — Player controller:** movement, camera, collision, main scene
- [ ] **Ch. 3 — Weapons & combat:** firing, ballistics, damage, hit feedback
- [ ] **Ch. 4 — Multiplayer:** 3v3 networking, teams, lobby, sync
- [ ] **Ch. 5 — Round system:** buy phase, live round, score, win conditions
- [ ] **Ch. 6 — Abilities:** original agent abilities and gadgets
- [ ] **Ch. 7 — Map & level design:** original map, layout, spawns, cover
- [ ] **Ch. 8 — UI, art & audio:** HUD, menus, identity, VFX, sound
- [ ] **Ch. 9 — Testing & ship:** optimisation, balance, final export build

### Originality note

Everything user-facing will be original work: the game title, agent and ability
names, weapon names, map names, level layouts, art direction, and UI. The genre
is *tactical FPS*; the content is ours. Naming and visual identity are handled in
Chapters 6 and 8 — until then, `3v3 Tactical FPS` is a working title only.
