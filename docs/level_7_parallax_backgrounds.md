# Background nhiều layer ở Level 7

Tài liệu này mô tả cách các lớp parallax của Level 7 được tổ chức, fit theo camera và lặp ảnh. Scene cấu hình nằm ở [`nodes/scenes/level_7.tscn`](../nodes/scenes/level_7.tscn); script fit ảnh nằm ở [`scripts/parallax_background_fit.gd`](../scripts/parallax_background_fit.gd).

## Cấu trúc scene

Các layer được gom dưới `ParallaxList` để dễ tìm và quản lý. Mỗi layer là một `Parallax2D` có một `Sprite2D` làm con trực tiếp:

```text
Level7
├── TileMap32
├── ParallaxList
│   ├── ParallaxBackground   (layer 1, phía trước)
│   │   └── BackgroundImage
│   ├── ParallaxBackground2  (layer 2)
│   │   └── BackgroundImage2
│   ├── ParallaxBackground3  (layer 3)
│   │   └── BackgroundImage3
│   └── ParallaxBackground4  (layer 4, phía sau)
│       └── BackgroundImage4
└── Asura / Camera2D / các node gameplay khác
```

Tên `ParallaxBackground` của layer 1 được giữ từ cấu hình cũ; loại node thực tế của nó vẫn là `Parallax2D`.

## Cấu hình hiện tại

Các giá trị `x` và `y` trong `scroll_scale` điều khiển mức dịch chuyển ngang và dọc theo camera. Giá trị càng lớn thì lớp càng dịch chuyển nhiều khi camera di chuyển; `1` tương ứng với chuyển động camera đầy đủ.

| Thứ tự từ trước ra sau | Ảnh | Node | `z_index` | `scroll_scale` (x, y) | Kích thước ảnh gốc |
| --- | --- | --- | --- | --- | --- |
| 1 | `bg-1-layer-1.png` | `ParallaxBackground` | -1 | (0.9, 0.9) | 1590 × 624 |
| 2 | `bg-1-layer-2.png` | `ParallaxBackground2` | -2 | (0.5, 0.9) | 1590 × 624 |
| 3 | `bg-1-layer-3.png` | `ParallaxBackground3` | -3 | (0.4, 0.9) | 790 × 182 |
| 4 | `bg-1-layer-4.png` | `ParallaxBackground4` | -4 | (0.25, 0.9) | 790 × 180 |

Layer 1 cuộn ngang gần theo camera nhất; các layer phía sau cuộn chậm hơn để tạo cảm giác chiều sâu. Cả bốn layer dùng `y = 0.9` để có cùng mức dịch chuyển dọc. `z_index` nhỏ hơn sẽ được vẽ phía sau; các giá trị âm giữ nền sau tilemap và nhân vật.

## Fit chiều cao camera và repeat

Mỗi `Sprite2D` gắn `parallax_background_fit.gd`. Script đọc chiều cao vùng nhìn hiện tại của camera, rồi chọn một **tỉ lệ đồng nhất** đủ để ảnh phủ từ mép trên đến mép dưới camera. Tỉ lệ này giữ nguyên tỉ lệ khung hình ảnh, không kéo giãn riêng theo chiều dọc. Nếu camera zoom hoặc kích thước viewport thay đổi, script tính lại trong lúc chạy.

Sau khi tính tỉ lệ, script cập nhật `repeat_size` theo kích thước ảnh đã scale. `Parallax2D` đang dùng `repeat_times = 3` và lặp theo cả hai trục, nên layer có thể cuộn ngang và dọc. Trường `repeat_size` lưu sẵn trong scene là giá trị ban đầu; script sẽ điều chỉnh nó khi chạy để khớp với ảnh đã fit.

Để repeat không lộ đường nối, mép trái/phải và mép trên/dưới của ảnh nguồn cần nối liền nhau. Nếu ảnh không thiết kế để lặp theo một trục, có thể thấy đường ráp khi camera cuộn theo trục đó.

## Thêm một layer

1. Đặt ảnh PNG trong `assets/sprites/` và để Godot import ảnh.
2. Trong `level_7.tscn`, thêm ảnh làm external texture resource.
3. Tạo một `Parallax2D` làm con của `ParallaxList`. Đặt `z_index`, `scroll_scale`, và `repeat_times = 3` theo vị trí cùng độ sâu mong muốn.
4. Tạo một `Sprite2D` làm **con trực tiếp** của `Parallax2D`, gán texture mới và đặt `centered = false`.
5. Gắn `scripts/parallax_background_fit.gd` vào `Sprite2D`. Script cần `Parallax2D` là parent trực tiếp để cập nhật `repeat_size`.
6. Giữ scale của sprite đồng nhất. Script lấy scale ban đầu làm mức tối thiểu rồi tăng đều hai chiều nếu cần phủ chiều cao camera.

Nếu chèn layer vào giữa danh sách, hãy đổi `z_index` của các layer phía sau để thứ tự trước/sau không bị đảo. Ví dụ, chèn layer mới ở vị trí 3 thì có thể đặt nó là `-3`, chuyển layer cũ 3 thành `-4` và layer cũ 4 thành `-5`.

## Chỉnh chuyển động

- Muốn một layer cuộn ngang nhiều hơn theo camera: tăng thành phần `x` của `scroll_scale`.
- Muốn layer cuộn ngang chậm hơn: giảm thành phần `x`.
- Chỉnh `y` riêng nếu cần thay đổi chuyển động dọc. Hiện tại các layer đều dùng `0.9`.
- Thay đổi `z_index` để đưa layer ra trước hoặc lùi ra sau; số nhỏ hơn nằm phía sau.
- Giữ `repeat_times` đủ lớn để các bản lặp phủ được vùng nhìn trong khi camera di chuyển.

Các `scroll_scale` hiện tại được đặt trực tiếp trên từng `Parallax2D` trong scene; chỉnh các giá trị này để thay đổi riêng từng lớp mà không cần sửa script fit ảnh.
