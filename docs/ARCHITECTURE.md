# Dungeon Traps - Project Architecture

Updated: 2026-08-10

This document describes the actual architecture and runtime behavior of the project.

## Core Principles

- Level scenes only hold placement, never logic.
- Trap/door/torch/player are self-contained reusable scenes that only know their own behavior.
- `GameState` is the single autoload that owns the death flow and restart.
- Every hazard goes through the same entry point: `GameState.trigger_game_over(body)`.
- Per-level configuration is passed via `@export`, never hard-coded in scripts.

## Runtime Diagram

```mermaid
flowchart TD
  Project["project.godot"] --> Main["nodes/scenes/level_1.tscn"]
  Project --> Music["Autoload: Music (nodes/music.tscn)"]
  Project --> GameState["Autoload: GameState (scripts/game_state.gd)"]

  Main --> Asura["characters/asura.tscn"]
  Main --> Door["door.tscn"]
  Main --> Fire["traps/fire_trap.tscn"]
  Main --> Thorn["traps/thorn.tscn"]
  Main --> Torch["torch.tscn"]
  Main --> TileMap["TileMap / TileMap32"]

  Asura --> AsuraController["scripts/actors/asura_controller.gd"]
  Asura --> Dust["effects/landing_dust.tscn"]
  Fire --> FireScript["scripts/fire_trap.gd"]
  Thorn --> ThornScript["scripts/thorn_trap.gd"]
  Door --> DoorScript["scripts/door.gd"]

  FireScript --> GameOver["GameState.trigger_game_over(player)"]
  ThornScript --> GameOver
  KillzoneScript["scripts/killzone.gd"] --> GameOver

  GameOver --> Die["player.die()"]
  GameOver --> Sound["game_over.mp3 (SFX bus)"]
  GameOver --> Overlay["GAME OVER overlay + 5s countdown"]
  Overlay --> Reload["change_scene_to_file(current scene)"]

  DoorScript --> Level2["nodes/scenes/level_2.tscn"]
```

## Layers Of Responsibility

### Project Config

`project.godot` defines the main scene, input map, autoloads, global groups and render defaults. It holds no gameplay logic.

- Main scene: `nodes/scenes/level_1.tscn` (referenced by UID `uid://l1dhtqji1d6x`).
- Autoload `Music`: scene `nodes/music.tscn`, an `AudioStreamPlayer2D` autoplaying `background_music.mp3` on the `Music` bus.
- Autoload `GameState`: `scripts/game_state.gd`.
- Global group: `player`.
- Input actions: `move_left` (A/←), `move_right` (D/→), `jump` (↑), `attack` (C), `slide` (X).

`default_bus_layout.tres` defines the `Music` bus (-6 dB) and the `SFX` bus (0 dB), both routed to `Master`.

### Level Scenes

`nodes/scenes/level_1.tscn` (root `Level1`) and `nodes/scenes/level_2.tscn` (root `Level2`).

A level contains:

- The player instance, with its camera and `PointLight2D` parented under it.
- TileMap/background.
- Trap, door and torch instances, grouped under the `FireList`, `ThornList` and `TorchList` nodes.
- Instance-specific configuration such as `Door.next_scene_path`.

Neither level has a script attached to its root node. Levels hold no death/restart logic, no movement logic, and no global state.

### Reusable Gameplay Scenes

| Scene | Owning logic |
| --- | --- |
| `characters/asura.tscn` | `scripts/actors/asura_controller.gd` |
| `traps/fire_trap.tscn` | `scripts/fire_trap.gd` |
| `traps/thorn.tscn` | `scripts/thorn_trap.gd` |
| `door.tscn` | `scripts/door.gd` |
| `killzone.tscn` | `scripts/killzone.gd` |
| `torch.tscn` | Animation + `PointLight2D` in the scene, no script |
| `effects/landing_dust.tscn` | `scripts/landing_dust.gd` |
| `enemies/slime.tscn` | `scripts/slime.gd` (only used by the legacy `game.tscn`) |
| `items/coin.tscn` | `scripts/coin.gd` (only used by the legacy `game.tscn`) |
| `platform.tscn`, `tile_map_32.tscn` | No script |

A reusable scene that needs to change global state calls an autoload or emits a signal; it never changes the scene itself.

### Scripts

Scripts live under `res://scripts/`, with `actors/` and `ui/` subgroups; the smaller gameplay scripts are currently flat in `scripts/`.

Files currently not referenced by any scene: `scripts/level_1_controller.gd` and `scripts/level_2_controller.gd` (both only `extends Node2D`), and `nodes/traps/gai.tscn` (the old thorn scene, still wired to `fire_trap.gd`, superseded by `traps/thorn.tscn`).

### Assets

`assets/` holds passive data only — textures, sounds, music, fonts. No gameplay scripts.

Sounds actually referenced by scenes: `running.mp3` and `sword_attack.mp3` (Asura), `fireball_whoosh.mp3` (fire trap), `coin.wav` (legacy coin), `game_over.mp3` (preloaded by `GameState`). The remaining files in `assets/sounds/` are unreferenced.

## Main Flows

### Player Movement

`asura.tscn` is a `CharacterBody2D` in the `player` group, on layer 2 with mask 1, driven by `scripts/actors/asura_controller.gd`.

The script handles gravity, jumping, left/right movement, ground/air sliding, sprite flipping, attacks (alternating `attack`/`attack2`, always `attack2` while airborne), the idle/run/jump_up/jump_down/slide/death animations, landing dust when fall speed exceeds `LANDING_DUST_MIN_SPEED`, and `die()`.

Things to be aware of:

- During an attack, `velocity.x` is forced to 0.
- On death the script does not use `move_and_slide()`; it applies gravity and adds the result straight to `position`, producing the pop-up-then-fall effect.
- `die()` clears the collision layer/mask and disables the `CollisionShape2D`.
- `die()` is the contract `GameState` relies on — a player character must implement it.

### Game Over

`fire_trap.gd`, `thorn_trap.gd` and `killzone.gd` all share one death flow:

```text
Hazard body_entered
  -> if the body is in the player group
  -> /root/GameState.trigger_game_over(body)
  -> state = GAME_OVER, remember the current scene
  -> play game_over.mp3 (SFX bus)
  -> player.die()
  -> CanvasLayer overlay at layer 100 + 5 second countdown
  -> change_scene_to_file(current scene)
  -> reset_to_playing()
```

`GameState` runs with `PROCESS_MODE_ALWAYS` and restarts the **scene currently being played** (`_get_current_scene_path()`) rather than always level 1; `DEFAULT_RESTART_SCENE_PATH` is only a fallback. Hazards never reload the scene themselves.

### Fire Trap

The fire trap has two areas: `TriggerArea` (mask 2) and the damage area on the root `Area2D` itself (mask 2).

```text
_ready: sprite hidden, damage shape disabled
TriggerArea.body_entered (player)
  -> disable the trigger's monitoring
  -> show the sprite, play AppearSound
  -> enable the damage shape and monitoring
body_entered (player) -> GameState.trigger_game_over()
```

### Thorn Trap

`traps/thorn.tscn` is a `Node2D` containing `Hazard` (an Area2D) and `TriggerArea`.

```text
_ready: physics process disabled
TriggerArea.body_entered (player) -> _is_falling = true, enable physics process
_physics_process: raycast downward from 3 points (-half_width, 0, +half_width)
  -> on hitting the floor, snap to the floor surface and stop
  -> or stop after falling past max_fall_distance
Hazard.body_entered (player) -> GameState.trigger_game_over()
```

Exported parameters: `fall_speed`, `max_fall_distance`, `floor_collision_mask`, `thorn_half_width`, `thorn_half_height`, `floor_probe_margin`. The script halts itself when `GameState.is_game_over()`.

### Door / Level Transition

`door.gd` uses two Area2Ds:

- `OpenArea`: entering it plays the `open` animation.
- `PassArea`: entering it once the door is open changes the scene after a 0.3s delay.

`next_scene_path` is an `@export`, configured per level instance.

- `level_1` points to `res://nodes/scenes/level_2.tscn`.
- `level_2` has no `next_scene_path` configured, so the final door currently leads nowhere.
- An empty `next_scene_path` means the door does not change scenes.

### Lighting

The project does not use `CanvasModulate`. Darkness is faked by lowering each object's `modulate`, then `PointLight2D` adds brightness back on top.

| Node | modulate |
| --- | --- |
| `TileMap` in `level_1` | 0.733 |
| `Asura` instance in a level | 0.545 |
| `torch.tscn` root | 0.439 |
| `fire_trap.tscn/AnimatedSprite2D` | 0.431 |
| `thorn.tscn/Hazard/Sprite2D` | 0.431 |

Light sources: a `PointLight2D` under `Asura` in each level, one under the fire trap's `AnimatedSprite2D`, and one under the torch root.

New gameplay sprites must lower their `modulate` in line with the table above; otherwise they stay at full brightness and appear unaffected by the lights.

### Music

`Music` is the autoload scene `nodes/music.tscn`, whose root `AudioStreamPlayer2D` autoplays `background_music.mp3` on the `Music` bus. Every other sound effect goes through the `SFX` bus.

## Collision And Groups

| Scene | Layer | Mask |
| --- | --- | --- |
| `asura.tscn` | 2 | 1 |
| `fire_trap.tscn` root | 0 | 2 |
| `fire_trap.tscn` `TriggerArea` | 0 | 2 |
| `thorn.tscn` `Hazard` | 0 | 2 |
| `thorn.tscn` `TriggerArea` | 0 | 2 |
| `door.tscn` `OpenArea` / `PassArea` | 0 | 3 |
| `killzone.tscn` | 0 | 2 |
| `items/coin.tscn` | 0 | 2 |

Layer meanings:

| Layer | Meaning |
| --- | --- |
| 1 | World / TileMap / Platform |
| 2 | Player |

Conventions:

- Player scenes sit on layer 2 and belong to the `player` group.
- Hazards confirm the player via `body.is_in_group("player")` and mask only layer 2.
- Items mask only layer 2.
- Enemies and hazards never depend on the player being on layer 1.

`door.tscn` currently uses mask 3 (catching both layer 1 and 2), the only remaining deviation from this convention.

## Responsibility Boundaries

- A level only places objects and configures instances.
- The player only manages its own input, movement, animation and death state.
- A trap only detects collisions and reports to the game state.
- A door only handles opening and scene transitions.
- `GameState` only manages global state, the game over overlay and restarting.
- The assets folder only holds visual/audio/font data.
