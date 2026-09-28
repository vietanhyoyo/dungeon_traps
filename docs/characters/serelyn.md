# Serelyn

Tài liệu này mô tả hội thoại, hành vi khi được điều khiển và phần triển khai
riêng của Serelyn.

## Tuyển Thành Viên Và Hội Thoại

Trong `level_6.tscn`, Serelyn xuất hiện dưới dạng NPC gần điểm bắt đầu và scene
có `DialogueLayer`. Asura đến gần rồi nhấn E để mở hội thoại gồm ba câu. Game
tạm dừng khi hội thoại đang mở. Nhấn Esc để ẩn khung thoại và tiếp tục chơi;
nhấn E gần Serelyn để mở lại từ câu hiện tại.

Sau câu cuối, `GameState.recruit_party_member("serelyn")` lưu Serelyn vào đội
trong `user://save_game.json`. Khi quay lại level 6, trạng thái đã lưu khiến
Serelyn không còn xuất hiện dưới dạng NPC và không thể mở hội thoại lần nữa.

Sau hội thoại, `scripts/level_6_controller.gd` nhận phím Z để chuyển giữa Asura
và Serelyn. Nhân vật được chọn xuất hiện tại vị trí nhân vật hiện tại, căn theo
đáy capsule. Camera và `PointLight2D` đi theo nhân vật mới; nhân vật còn lại bị
ẩn và tắt va chạm. Mỗi lần chuyển có vòng sáng màu riêng và khóa Z đến khi hiệu
ứng kết thúc. `ui/character_hud.tscn` hiển thị portrait cắt từ ảnh idle và làm
sáng viền của nhân vật đang được điều khiển.

## Di Chuyển Và Tấn Công

Serelyn là `CharacterBody2D` với `AnimatedSprite2D`. Các animation gồm idle (5
khung), run (6 khung), `jump_up`, `jump_down`, `hust` và `death`. Khi được điều
khiển, cô di chuyển trái/phải và nhảy bằng action `jump`.

Action `slide` làm Serelyn lướt theo hướng đang nhìn trong 0,4 giây, trên mặt
đất hoặc trên không. Lượt lướt trên không chỉ dùng được một lần mỗi khi rời mặt
đất. Khi lướt, capsule va chạm được hạ thấp và phát animation `slide` hoặc
`slide-air`; lướt trên mặt đất còn tạo bụi. Khi rơi đủ nhanh để tiếp đất,
Serelyn cũng tạo bụi tiếp đất như Asura.

Nhấn C để phát `attack` trên mặt đất hoặc `jump_attack` khi đang ở trên không.
Khi animation kết thúc, Serelyn bắn `characters/serelyn_arrow.tscn` theo hướng
đang nhìn. Tên bay ngang, có đèn xanh lá và kiểm tra va chạm với địa hình cũng
như enemy.

## Ngắm Và Bắn Tên

Khi tấn công, Serelyn chọn enemy gần nhất đang trong camera, ở cùng phía với
hướng nhìn, trong tầm bắn và có đường bay không bị vật cản. Tia ngắm thử nhiều
điểm trên hitbox enemy. `SlimeGunner` có thêm vùng trúng tên ở phần thân trên,
cho phép bắn khi phần đó lộ ra khỏi mép sàn. Serelyn kiểm tra tầm nhìn từ vị trí
sinh tên tương ứng với animation tấn công rồi giữ mục tiêu đó đến lúc bắn. Chỉ
cần một điểm trên hitbox nằm trong camera thì enemy có thể được chọn.

Góc bắn lên tối đa là 60 độ, còn góc bắn xuống tối đa 15 độ. Với mục tiêu cao
hơn Serelyn tối đa 15 độ, cô dùng animation `attack_high`; mục tiêu cao hơn nữa
dùng `attack_high2`. Vị trí sinh tên được nâng lên để khớp với tay và dây cung
trong hai animation này. Nếu enemy ở thấp hơn, cô dùng `attack_low` và hạ thấp
vị trí sinh tên.

Tên làm vỡ thùng gỗ thuộc group `breakable`. Thùng sắt chặn tên nhưng không bị
phá. Khi trúng enemy trong camera, tên tạo cùng `effects/hit_effect.tscn` với
đòn chém của Asura rồi gọi `die()` của enemy. Phím Z bị khóa khi đang hội thoại,
tạm dừng hoặc game over.

## Chịu Đòn, Chết Và Kỹ Năng Chung

Sau khi bị trúng đòn, Serelyn mất quyền điều khiển trong 0,4 giây và giữ
animation `hust` trước khi `GameState` chuyển cô sang trạng thái chết. Sau đó cô
phát `death`, bật lên rồi rơi theo trọng lực như Asura. Collision layer/mask và
`CollisionShape2D` được tắt trong lúc game over.

Serelyn dùng chung kỹ năng `wall_double_jump` với Asura. Cô chỉ nhảy tường khi
`GameState.has_skill(Skills.WALL_DOUBLE_JUMP)` trả về true. Bám sang mặt tường
mới hoặc chạm đất sẽ hồi một cú nhảy tường. Cú nhảy gán `JUMP_VELOCITY` vào
`velocity.y`, và tạo bụi gần mặt tường.

Bảng pause cập nhật thông tin theo nhân vật đang được điều khiển. Khi chọn
Serelyn, bảng hiển thị portrait, tên, class và mô tả đòn đánh của cô.
