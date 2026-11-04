# Dungeon Chuyển Sinh — bản Godot

Port đầy đủ `../dungeon-chuyen-sinh` (TS + three.js) sang Godot 4.7, GDScript.
Gốc so sánh: TS commit `16a1087` (2026-11-04).

## Chạy
- Cài Godot: `brew install --cask godot`
- Chơi: `godot --path ~/personal/dungeon-chuyen-sinh-godot`
- Mở editor: `godot -e --path ~/personal/dungeon-chuyen-sinh-godot`

## Có gì (= bản TS)
- 2 chế độ: **Sinh tồn** (map Hầm Mộ, Lich lúc 8:00) · **Dungeon** Hầm Mộ 2 tầng (quái có hạn theo vùng, vào sâu mạnh hơn, phòng boss khoá cửa, hết 6:30 bị kéo vào phòng boss).
- 2 nhân vật: Thạch Kiên (Kiếm sĩ, Thánh Nộ) · Lam Vũ (Cung thủ, Lăn Né, Chân Nhẹ).
- 8 vũ khí + 6 chỉ số, mỗi vũ khí 1 kỹ năng ẩn; 4 loại nhiệm vụ; 4 vật phẩm.
- Vàng, cửa hàng (mua nhân vật, 6 nâng cấp vĩnh viễn), lưu tiến trình `user://meta.json`.

Phím: `WASD`/mũi tên di chuyển · `Space` kỹ năng · `1 2 3` chọn thẻ · `Esc` tạm dừng / quay lại · `Enter` chọn / bắt đầu.

## Thay đổi nội dung (không đụng code)
| Muốn đổi | Sửa ở |
|---|---|
| Toàn bộ "look" (model nhân vật, quái, boss, tile dungeon, màu hiệu ứng) | `content/styles/<tên>.tres` — mở bằng editor (Inspector) hoặc sửa text. Thêm style = copy 1 file .tres |
| Style đang dùng | Project Settings `game/style` (mặc định `quaternius.tres` = KayKit + 3 quái Quaternius; `kaykit.tres` = y bản TS), hoặc chạy `-- style=kaykit` |
| Layout map | `content/maps/<id>.txt` (`#` tường `.` sàn `o` cột `S` xuất phát `D` cửa `B` boss `b` phòng boss) |
| Vùng quái / nhiệm vụ / điểm rune / bảng độ sâu của map | `scripts/data/maps.gd` |
| Dungeon (danh sách tầng, độ khó, vàng, giới hạn giờ) | `scripts/data/dungeons.gd` |
| Chỉ số nhân vật, kỹ năng, nội tại | `scripts/data/characters.gd` |
| Chỉ số quái | `scripts/data/monsters.gd` (map gọi quái bằng id) |
| Boss + đòn đánh | `scripts/data/bosses.gd` |
| Vũ khí (số) | `scripts/data/items.gd`; logic 1 file/vũ khí `scripts/game/weapons/*.gd`, đăng ký ở `scripts/game/weapons.gd` |
| Cân bằng chung, vàng, nhiệm vụ, vật phẩm | `scripts/data/data.gd` |

Style gồm: `HeroSkin` (model, clip idle/run/attack, node ẩn, chiều cao, màu x-ray) · `MonsterSkin` (model + clip chạy, chiều cao, tốc độ anim, màu nhuộm / phát sáng; `slime` = dựng bằng code) · `BossSkin` · `ThemeSkin` (tile sàn/tường/cột/đuốc/cửa, ánh sáng, sương, màu rune) · `FxSkin` (bảng màu hiệu ứng, model kiếm bay). Định nghĩa: `scripts/style/*.gd`.

Thêm quái mới: 1 dòng `monsters.gd` + 1 `MonsterSkin` trong mỗi style + thêm id vào `zone_types` của map. Quái không có skin trong style thì không vẽ (logic vẫn chạy).

## Kiến trúc
- `scripts/core`, `scripts/data`, `scripts/game`: luật chơi thuần (không Node), port 1-1 từ `src/` TS. `World.new({seed, map, rules, character, locked})`, `World.tick(dt, mx, mz, skill)`.
- Tính toán logic bằng float64 (`Vec.hypot`, `Collision.rx/rz`, `FlowField.ox/oz`); Godot `Vector2` là float32 nên không dùng trong logic.
- `scripts/render`, `scripts/ui`: chỉ đọc `World` + `world.events`. Quái = MultiMesh, animation nướng thành flipbook ~30 fps lúc load.
- `sim/`: bot + sim không cửa sổ.

## Khớp với bản TS (đo 2026-11-04)
Sim TS (`16a1087`) vs sim Godot, cùng seed, bot né quái + làm nhiệm vụ, in thời gian / cấp / số quái / nhiệm vụ / cấp theo phút / 6 ô / thời gian boss:
| | Ván giống hệt |
|---|---|
| Sinh tồn (2 nhân vật × 3 đứng yên + 6 bot) | 18/18 |
| Dungeon tầng 1 | 14/14 |
| Dungeon tầng 2 | 14/14 |

Trận boss khớp tới 12 chữ số thập phân vị trí người chơi mỗi tick.
Hiệu năng (MacBook M5, 1600×900, vsync 60): 300 quái + cả 8 kỹ năng ẩn: trung bình 60 fps, 330–490 draw call (1 lần tụt ~8 fps lúc mở kỹ năng ẩn). Dungeon: 60 fps.

Khác bản TS: thanh máu boss chia cho máu lúc xuất hiện (TS chia 9000 nên ở Dungeon thanh đầy tới khi boss mất ~50% máu).

## Sim (không cửa sổ)
- `godot --headless --path . -s sim/sim.gd -- seeds=20 char=knight|archer quests=skip|do skill=1 mode=dungeon floor=1|2 diff=1.3 boss_diff=1.5 verbose=1 only=1,5`
- `./sim/parallel.sh 50 8`: 50 seed chia 8 tiến trình.

## Test phím thật
- `godot --path . -- keytest fresh god give=holySword:4,might:1`: bơm phím Enter / 1 2 / W / D / Space / Esc, in `KEYTEST PASS|FAIL`.

## Cờ debug (sau `--`)
`seed=123` · `char=archer` · `mode=dungeon floor=2` · `style=quaternius` · `fresh` (bỏ qua file lưu) · `unlock` (mở mọi tầng / nhân vật) · `god` · `boss` (2 s trước boss) · `enemies=300` · `give=fireball:5,haste:1` · `hidden=all` · `lock=fireball,haste` · `quest=bounce|hold|crystal|thief` · `hp=3` · `fps` · `bot` · `autostart` · `shots=DIR shot_at=5,30 quit_at=40` · `shot_mode=levelUp|end` · `showcase` (xem dàn quái) · `cam=30 pitch=55`

Xuất bản (export): thêm `*.txt` vào "Filters to export non-resource files" để map đi kèm.

Credits: `CREDITS.md` (KayKit, Quaternius — CC0).
