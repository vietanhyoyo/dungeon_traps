# Dungeon Traps

Game platformer 2D pixel-art làm bằng **Godot 4.6** (GDScript). Người chơi điều khiển nhân vật Asura đi qua các dungeon tối, né bẫy lửa và bẫy gai rơi, tìm cửa để sang level tiếp theo. Chạm bẫy hoặc rơi xuống killzone thì game over và level tự restart sau 5 giây.

Cập nhật: 2026-08-10

## Nội Dung

- [Yêu Cầu](#yêu-cầu)
- [Chạy Dự Án](#chạy-dự-án)
- [Điều Khiển](#điều-khiển)
- [Gameplay](#gameplay)
- [Cấu Trúc Thư Mục](#cấu-trúc-thư-mục)
- [Scene Và Script Chính](#scene-và-script-chính)
- [Cấu Hình Dự Án](#cấu-hình-dự-án)
- [Export](#export)
- [Thêm Nội Dung Mới](#thêm-nội-dung-mới)
- [Tài Liệu Chi Tiết](#tài-liệu-chi-tiết)
- [Asset Và License](#asset-và-license)

## Yêu Cầu

- Godot 4.6 (Forward Plus renderer).
- Không có dependency ngoài, không cần build step.

## Chạy Dự Án

Mở project bằng Godot editor:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/vhec/Documents/godot_projects/d-games
```

Chạy game trực tiếp:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/vhec/Documents/godot_projects/d-games
```

Kiểm tra project load sạch (không mở cửa sổ game):

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/vhec/Documents/godot_projects/d-games --quit
```

Chơi bản Web đã export sẵn: mở `index.html` rồi bấm **Play Game** (trang này trỏ tới `export_html/GodotGame.html`). Bản Web cần chạy qua HTTP server, không mở bằng `file://`:

```bash
python3 -m http.server 8000
```

## Điều Khiển

| Hành động | Phím |
| --- | --- |
| Sang trái | `A` hoặc `←` |
| Sang phải | `D` hoặc `→` |
| Nhảy | `Space` |
| Tấn công | `C` |

## Gameplay

Main scene là `nodes/scenes/level_1.tscn`. Người chơi đi từ đầu map tới cửa cuối level, cửa mở animation rồi chuyển sang `level_2.tscn`.

**Bẫy lửa (`fire_trap.tscn`)** — ẩn cho tới khi player đi vào `TriggerArea`, sau đó hiện sprite lửa, phát sound và bật vùng gây sát thương.

**Bẫy gai (`thorn.tscn`)** — treo trên trần; khi player đi vào vùng trigger thì gai rơi xuống, dùng raycast dò sàn để dừng đúng mặt đất.

**Killzone (`killzone.tscn`)** — vùng dưới đáy map, chạm là chết.

**Luồng game over** — mọi hazard đều gọi chung `GameState.trigger_game_over(player)`:

1. `GameState` chuyển sang state `GAME_OVER` và ghi nhớ scene hiện tại.
2. Phát `game_over.mp3` trên bus `SFX`.
3. Gọi `player.die()` — Asura tắt collision, văng lên rồi rơi xuống, play animation `death`.
4. Overlay `GAME OVER / Restarting in N` hiện lên bằng font pixel.
5. Sau 5 giây, reload lại **chính level đang chơi** (không phải luôn về level 1).

## Cấu Trúc Thư Mục

```text
res://
  assets/            # Dữ liệu thụ động: sprite, sound, music, font
    fonts/
    music/
    sounds/
    sprites/
      shinn_asura/   # Sprite sheet nhân vật chính
      traps/
  docs/
    PROJECT.md
    ARCHITECTURE.md
  export_html/       # Output export Web (không sửa tay)
  nodes/             # Toàn bộ scene .tscn
    characters/
    effects/
    enemies/
    items/
    scenes/          # Level scenes
    traps/
    door.tscn
    game.tscn        # Scene tutorial/legacy
    killzone.tscn
    music.tscn
    platform.tscn
    tile_map_32.tscn
    torch.tscn
  scripts/           # Toàn bộ GDScript
    actors/
    ui/
  index.html         # Trang launcher cho bản Web
  project.godot
  export_presets.cfg
```

## Scene Và Script Chính

| Scene | Vai trò |
| --- | --- |
| `nodes/scenes/level_1.tscn` | Main scene: Asura, camera, ánh sáng, tilemap, fire traps, thorn traps, torches, door sang level 2 |
| `nodes/scenes/level_2.tscn` | Level 2, layout dài hơn, nhiều fire/thorn trap và torch |
| `nodes/characters/asura.tscn` | Nhân vật chính, `CharacterBody2D`, group `player`, layer 2 |
| `nodes/traps/fire_trap.tscn` | Bẫy lửa kích hoạt theo trigger |
| `nodes/traps/thorn.tscn` | Bẫy gai rơi từ trần |
| `nodes/door.tscn` | Cửa mở bằng animation, chuyển scene theo `next_scene_path` |
| `nodes/killzone.tscn` | Vùng chết dưới đáy map |
| `nodes/torch.tscn` | Đuốc trang trí, animation flicker + `PointLight2D` |
| `nodes/music.tscn` | Autoload nhạc nền |
| `nodes/effects/landing_dust.tscn` | Particle bụi khi tiếp đất |
| `nodes/game.tscn` | Scene tutorial/legacy: coin, slime, platform, score label |

| Script | Vai trò |
| --- | --- |
| `scripts/game_state.gd` | Autoload `GameState`: state `PLAYING/GAME_OVER`, overlay, countdown restart |
| `scripts/actors/asura_controller.gd` | Di chuyển, nhảy, attack, landing dust, `die()` |
| `scripts/fire_trap.gd` | Trigger hiện lửa, gọi `GameState.trigger_game_over()` |
| `scripts/thorn_trap.gd` | Gai rơi, raycast dò sàn, gọi `GameState.trigger_game_over()` |
| `scripts/door.gd` | Mở cửa và chuyển scene |
| `scripts/killzone.gd` | Gọi `GameState.trigger_game_over()` |
| `scripts/landing_dust.gd` | Particle tự phát và tự xóa sau 0.5s |
| `scripts/slime.gd` | Enemy legacy đi qua lại bằng raycast |
| `scripts/coin.gd` | Coin legacy: cộng điểm qua `%GameManager` |
| `scripts/ui/game_manager.gd` | Score manager legacy của `nodes/game.tscn` |

## Cấu Hình Dự Án

File `project.godot`:

- `run/main_scene`: `nodes/scenes/level_1.tscn` (trỏ bằng UID).
- Autoload: `Music` (`nodes/music.tscn`), `GameState` (`scripts/game_state.gd`).
- Global group: `player`.
- Input actions: `move_left`, `move_right`, `jump`, `attack`.
- `textures/canvas_textures/default_texture_filter=0` để giữ nét pixel art.
- Stretch mode: `canvas_items`.

Audio bus (`default_bus_layout.tres`): `Master` → `Music` (-6 dB) và `SFX` (0 dB). Nhạc nền đi bus `Music`, mọi SFX đi bus `SFX`.

Collision layer đang dùng: layer 1 = world/tilemap, layer 2 = player. Hazard và item chỉ mask layer 2 và luôn kiểm tra `body.is_in_group("player")`.

## Export

`export_presets.cfg` có sẵn 3 preset:

| Preset | Output |
| --- | --- |
| Web | `export_html/GodotGame.html` |
| Android | chưa đặt `export_path` |
| macOS | `../../GodotGame.dmg` |

Export Web từ CLI:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/vhec/Documents/godot_projects/d-games --export-release "Web" export_html/GodotGame.html
```

Thư mục `export_html/` là output build — sau khi đổi gameplay cần export lại thì bản Web mới phản ánh thay đổi.

## Thêm Nội Dung Mới

**Level mới**: tạo scene trong `nodes/scenes/`, đặt root node đúng tên (`Level3`), instance `asura.tscn` có camera con, đặt tilemap ở collision layer world, instance trap từ scene có sẵn, và set `next_scene_path` cho door cuối level.

**Trap mới**: dùng `Area2D`, mask layer player, kiểm tra `body.is_in_group("player")`, gọi `GameState.trigger_game_over(body)` — không tự `change_scene_to_file()` trong script trap.

**Nhân vật mới**: root là `CharacterBody2D`, thuộc group `player`, có method `die()` (đây là contract `GameState` dựa vào), collision layer 2.

Xem checklist đầy đủ trong [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Tài Liệu Chi Tiết

- [docs/PROJECT.md](docs/PROJECT.md) — tổng quan dự án, cấu hình, luồng gameplay.
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — kiến trúc, ranh giới trách nhiệm, quy ước và định hướng refactor.

## Asset Và License

Asset nằm trong `assets/`. Theo `assets/LICENSE & CREDITS.txt`, các asset trong pack được ghi là CC0, credit cho analogStudios_, RottingPixels, Brackeys, Asbjorn/Sofia Thirslund; font Pixel Operator của Jayvee Enaguas / HarvettFox96.
