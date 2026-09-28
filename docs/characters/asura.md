# Asura

Tài liệu này mô tả hành vi hiện tại và phần triển khai riêng của Asura.

## Scene Và Controller

`characters/asura.tscn` là `CharacterBody2D`, thuộc group `player`, ở collision
layer 2 với mask 1. Hành vi được điều khiển bởi
`scripts/actors/asura_controller.gd`.

Controller xử lý trọng lực, nhảy, di chuyển trái/phải, lật sprite, lướt trên mặt
đất và trên không, tấn công, bụi tiếp đất và trạng thái chết. Các animation gồm
`idle`, `run`, `jump_up`, `jump_down`, `slide` và `death`. Lướt trên không chỉ
dùng được một lần mỗi khi rời mặt đất và hồi lại khi chạm đất. Bụi tiếp đất được
tạo khi tốc độ rơi vượt `LANDING_DUST_MIN_SPEED`.

Đòn đánh trên mặt đất luân phiên giữa `attack` và `attack2`. Khi ở trên không,
Asura dùng `jump_attack`, hoặc `jump_attack2` sau khi mở kỹ năng
`spin_jump_attack`. Trong lúc tấn công, `velocity.x` bị ép về 0.

## Spin Jump Attack

Rương trong `level_3` trao kỹ năng `spin_jump_attack`. Khi chưa mở kỹ năng, đòn
đánh trên không là `jump_attack` (3 khung, `JumpShape` 52x78). Khi đã mở,
`get_jump_attack_anim()` chọn `jump_attack2` (4 khung, 110x110), còn
`get_attack_shape()` ánh xạ đòn này sang `SpinShape` (84x96 tại `(14, -3)`).
Hitbox vươn ra sau lưng lẫn phía trước, theo đường kiếm quét trọn một vòng.

Cú lộn chỉ dùng được một lần mỗi khi Asura rời mặt đất. `spin_attack_used` hồi
lại khi chạm đất, cùng lúc với `air_slide_used` và `wall_jump_used`. Nhảy tường
không hồi lượt lộn. Khi chưa mở kỹ năng, `jump_attack` cũ vẫn có thể dùng liên
tiếp giữa không trung.

`jump_attack2` chạy ở tốc độ animation `16.0` (một vòng lộn mất 0,25 giây), so
với `10.0` của `jump_attack`. Asura đứng yên theo phương ngang trong lúc tấn
công, nên animation ngắn hơn giúp nhân vật không bị treo lâu giữa không trung.

## Wall Double Jump

Asura nhảy tường khi `GameState.has_skill(Skills.WALL_DOUBLE_JUMP)` trả về true.
Mỗi lần bám vào một mặt tường mới sẽ hồi một cú nhảy tường; chạm đất cũng hồi
lại lượt. Nhờ vậy Asura có thể nối các cú nhảy giữa nhiều mặt tường nhưng không
thể nhảy liên tục trên cùng một mặt tường.

`WALL_JUMP_VELOCITY` bằng `JUMP_VELOCITY`; cú nhảy tường gán đè `velocity.y`
thay vì cộng dồn nên đạt độ cao bằng cú nhảy thường. Khi đạp tường,
`spawn_wall_dust()` tạo `effects/landing_dust.tscn` gần mặt tường. Bụi được đặt
lệch theo `WALL_DUST_REACH` và dùng `flip_h` để thổi ra xa tường.

## Chết

Khi chết, controller áp dụng trọng lực trực tiếp vào `position` thay vì gọi
`move_and_slide()`, tạo hiệu ứng bật lên rồi rơi xuống. Controller xóa collision
layer/mask và tắt `CollisionShape2D`. `die()` là giao diện mà `GameState` gọi
trong luồng game over chung.
