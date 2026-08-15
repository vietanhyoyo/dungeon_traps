# Dungeon Traps - Tài Liệu Dự Án

Cập nhật: 2026-07-07

## Tổng Quan

`dungeon_traps` là một game platformer 2D làm bằng Godot 4.6. Người chơi điều khiển nhân vật pixel-art đi qua bản đồ dungeon, né bẫy lửa, mở cửa sang level tiếp theo và bị reset khi game over.

Dự án hiện có hai nhánh gameplay:

- Luồng chính đang chạy: `res://nodes/scenes/level_1.tscn` -> `res://nodes/scenes/level_2.tscn`, dùng nhân vật `asura.tscn`, bẫy lửa, đuốc, ánh sáng và `GameState`.
- Scene tutorial/legacy: `res://nodes/game.tscn`, hiện đã dùng lại `asura.tscn`, coin, slime, platform, score label và `GameManager`.

## Công Nghệ

- Engine: Godot 4.6
- Ngôn ngữ script: GDScript
- Render: Forward Plus
- Physics 3D engine: Jolt Physics, nhưng gameplay hiện tại là 2D
- Pixel art: texture filter mặc định của canvas đang tắt để giữ nét pixel
- Export đã cấu hình: Web, Android, macOS

## Cách Chạy

Mở bằng Godot editor:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/Shared/dev_projects/my_project/dungeon_traps
```

Kiểm tra load project nhanh bằng headless:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/Shared/dev_projects/my_project/dungeon_traps --quit
```

Chạy bản Web đã export:

- Mở `index.html`.
- Nút Play Game chuyển đến `export_html/GodotGame.html`.

Lưu ý: thư mục `export_html/` là output export. Sau khi đổi gameplay, cần export lại từ Godot nếu muốn bản Web phản ánh thay đổi mới.

## Cấu Hình Chính

File: `res://project.godot`

- `run/main_scene`: trỏ bằng UID đến `res://nodes/scenes/level_1.tscn`.
- Autoload:
  - `Music`: `res://nodes/music.tscn`
  - `GameState`: `res://scripts/game_state.gd`
- Input actions:
  - `jump`: ↑
  - `move_left`: Left Arrow, A
  - `move_right`: Right Arrow, D
  - `attack`: C
  - `slide`: X

## Gameplay Hiện Tại

Người chơi bắt đầu ở `level_1`, đi qua dungeon, tránh các `Fire` trap và chạm `Door` để sang `level_2`.

Luồng chết/game over:

1. Player chạm `Fire`.
2. `fire_trap.gd` gọi `/root/GameState.trigger_game_over(body)`.
3. `GameState` chuyển state sang `GAME_OVER`, gọi `player.die()` nếu player có method này.
4. Overlay `GAME OVER` xuất hiện, dùng font pixel `PixelOperator8-Bold.ttf`.
5. Sau 5 giây, scene reload về `res://nodes/scenes/level_1.tscn`.

Luồng chuyển level:

1. Player chạm vùng mở cửa `OpenArea`.
2. `door.gd` play animation `open`.
3. Khi player vào `PassArea` và cửa đã mở, door đổi scene theo `next_scene_path`.
4. `level_1` cấu hình `next_scene_path = "res://nodes/scenes/level_2.tscn"`.
5. Door ở `level_2` hiện chưa có `next_scene_path`, nên chưa đi tiếp level khác.

## Cấu Trúc Thư Mục Hiện Tại

```text
res://
  assets/
    fonts/
    music/
    sounds/
    sprites/
      shinn_asura/
      traps/
  docs/
    PROJECT.md
    ARCHITECTURE.md
  export_html/
  nodes/
    characters/
    effects/
    enemies/
    items/
    scenes/
    traps/
    door.tscn
    game.tscn
    killzone.tscn
    music.tscn
    platform.tscn
    tile_map_32.tscn
    torch.tscn
  scripts/
    actors/
    ui/
  project.godot
  export_presets.cfg
  index.html
```

## Scene Chính

| Scene | Vai trò |
| --- | --- |
| `res://nodes/scenes/level_1.tscn` | Main scene hiện tại, có Asura, camera, ánh sáng, tilemap, cửa sang level 2, fire traps, torches |
| `res://nodes/scenes/level_2.tscn` | Level thứ hai, layout dài hơn, có nhiều torches và fire traps |
| `res://nodes/characters/asura.tscn` | Nhân vật chính, gắn script `asura_controller.gd`, thuộc group `player`, collision layer 2 |
| `res://nodes/traps/fire_trap.tscn` | Bẫy lửa, phát sáng, gây game over qua `GameState` |
| `res://nodes/door.tscn` | Cửa mở bằng animation và đổi scene |
| `res://nodes/torch.tscn` | Đuốc trang trí, có animation flicker và PointLight2D |
| `res://nodes/music.tscn` | Autoload music, autoplay nhạc nền |
| `res://nodes/game.tscn` | Scene legacy/tutorial có Asura, coins, slime, moving platforms |

## Script Chính

| Script | Vai trò |
| --- | --- |
| `res://scripts/game_state.gd` | Autoload quản lý state `PLAYING/GAME_OVER`, death flow, countdown restart |
| `res://scripts/actors/asura_controller.gd` | Controller của `asura.tscn`: di chuyển, nhảy, lướt, attack, landing dust, die |
| `res://scripts/fire_trap.gd` | Gọi `GameState.trigger_game_over()` khi player chạm lửa |
| `res://scripts/door.gd` | Mở cửa, theo dõi player trong pass area, đổi scene |
| `res://scripts/landing_dust.gd` | Particle tự phát và tự xóa |
| `res://scripts/slime.gd` | Enemy đi qua lại bằng raycast trái/phải |
| `res://scripts/coin.gd` | Coin legacy: tăng score qua `%GameManager`, play animation pickup |
| `res://scripts/killzone.gd` | Gọi `GameState.trigger_game_over()` khi player rơi vào killzone |
| `res://scripts/ui/game_manager.gd` | Score manager legacy của `nodes/game.tscn` |

## Asset Và License

Asset nằm trong `res://assets/`.

- Fonts: `PixelOperator8.ttf`, `PixelOperator8-Bold.ttf`
- Music: `time_for_adventure.mp3`
- Sounds: coin, jump, hurt, tap, power up, explosion
- Sprites: slime, coin, door, torch, tileset, fire, Shinn Asura

Theo `assets/LICENSE & CREDITS.txt`, các asset trong pack được ghi là CC0, có credit cho analogStudios_, RottingPixels, Brackeys, Asbjorn/Sofia Thirslund và font Pixel Operator của Jayvee Enaguas / HarvettFox96.

## Ghi Chú Kỹ Thuật

- Main scene hiện không dùng `nodes/game.tscn`; scene này nên được xem là tutorial/legacy cho tới khi quyết định giữ hay bỏ.
- Controller của Asura đã được đổi thành `res://scripts/actors/asura_controller.gd`.
- `level_2.tscn` đã đổi root node thành `Level2`.
- `killzone.gd` và `fire_trap.gd` đều dùng chung death flow qua `GameState`.
- `asura.tscn` đã chuẩn hóa collision layer 2, collision mask 1. Player knight cũ đã được xóa.
- UID warning của các resource cũ đã được dọn bằng path reference rõ ràng. Headless load hiện chỉ còn warning cleanup `ObjectDB instances leaked/resource still in use` khi Godot thoát.

## Quy Ước Khi Phát Triển Tiếp

- Scene đặt trong `nodes/` hoặc `scenes/` cần nhất quán theo một convention, tránh vừa gọi `nodes` vừa gọi `scenes` lẫn lộn.
- Script gameplay nên nằm trong `res://scripts/`, không để script dưới `assets/sprites/`.
- Player/hazard/item nên giao tiếp qua group, signal hoặc autoload rõ ràng, hạn chế hard-code node path trừ khi scene đó sở hữu node trực tiếp.
- Khi move/rename `.tscn`, `.gd`, asset hoặc folder trong Godot project, nên dùng FileSystem dock của Godot editor hoặc kiểm tra lại UID/path bằng headless load sau khi move.
- Mọi level mới nên có root node đúng tên level, camera thuộc player, door cấu hình `next_scene_path`, và hazards dùng chung `GameState`.
