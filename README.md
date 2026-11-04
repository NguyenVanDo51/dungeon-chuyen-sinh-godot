# Dungeon Chuyển Sinh — bản Godot (thử nghiệm)

Port từ `../dungeon-chuyen-sinh` (TS + three.js) sang Godot 4.7, GDScript.
Phạm vi: **chế độ Sinh tồn đầy đủ**, 1 nhân vật, 4 vũ khí.

## Chạy
- Cài Godot: `brew install --cask godot`
- Chơi: `godot --path ~/personal/dungeon-chuyen-sinh-godot`
- Mở editor: `godot -e --path ~/personal/dungeon-chuyen-sinh-godot`

## Có gì
- Nhân vật: Thạch Kiên (Kiếm sĩ): 130 máu, giảm 20% sát thương nhận, sát thương ×0.85, nội tại Hút Máu, kỹ năng Thánh Nộ (`Space`, boss khựng 1.5 s).
- Vũ khí: Thánh Kiếm (riêng), Cầu Lửa, Lôi Ấn, Vòng Băng; mỗi cái có kỹ năng ẩn (cấp 5 + chỉ số đi kèm).
- 6 chỉ số, 6 ô, khoá ngẫu nhiên 1–2 món mỗi ván.
- Map Hầm Mộ, 3 vùng quái, quái mạnh theo thời gian, tinh anh, 4 vật phẩm, 4 loại nhiệm vụ (2/ván lúc 1:30, 4:00).
- Phút 8: Lich, 9000 máu, 6 đòn, cuồng nộ sau 2 phút. Hạ Lich = thắng.
- Bỏ: Cung thủ, vàng / cửa hàng / lưu, Dungeon.

Phím: `WASD`/mũi tên di chuyển · `Space` kỹ năng · `1 2 3` chọn thẻ · `Esc` tạm dừng · `Enter` bắt đầu / chơi lại.

## Kiến trúc
- `scripts/core`, `scripts/data`, `scripts/game`: luật chơi thuần (không Node), port 1-1 từ `src/` TS. `World.tick(dt, move, skill)`.
- `scripts/render`, `scripts/ui`: chỉ đọc `World` + `world.events` để vẽ. Quái = MultiMesh, tư thế chạy nướng sẵn từ GLB.
- `sim/`: bot + sim không cửa sổ.

## Sim (không cửa sổ)
- `godot --headless --path . -s sim/sim.gd -- seeds=10 quests=skip|do|both skill=1 verbose=1 only=1,5`
- `./sim/parallel.sh 50 8`: 50 seed chia 8 tiến trình (~6 phút trên M5).

## Test phím thật
- `godot --path . -- keytest god give=holySword:4,might:1`: bơm phím Enter / W / D / Space / Esc / 1, in `KEYTEST PASS|FAIL` (12 mục).

## Cờ debug (sau `--`)
`seed=123` · `god` · `boss` (bắt đầu 7:58) · `enemies=300` · `give=fireball:5,haste:1` · `quest=bounce|hold|crystal|thief` · `hp=3` · `fps` (in FPS mỗi 5 s) · `bot` (tự chơi) · `autostart` · `shots=DIR shot_at=5,30 quit_at=40` · `shot_mode=levelUp|end`

Ví dụ: `godot --path . -- bot god enemies=300 fps give=holySword:5,might:1,fireball:5,haste:1,thunderSeal:5,frostRing:5,area:1`

## Đo đạc (2026-11-04, MacBook M5, cửa sổ 1600×900, vsync 60 Hz)
- 300 quái + 4 kỹ năng ẩn: trung bình 60 fps, ~150–370 draw call. Frame tụt chỉ lúc khởi động và lúc lưu ảnh chụp.
- Trận boss: trung bình 60 fps.

Sim 50 seed, bot né quái, cùng bộ vũ khí rút gọn:

| | TS gốc | Godot |
|---|---|---|
| Bỏ nhiệm vụ | 33/50 thắng | 35/50 |
| Làm nhiệm vụ | 36/50 | 33/50 |

- Ván đứng yên seed 1, 2 khớp từng con số với TS (thời gian chết, cấp, số quái, cấp theo phút, 6 ô).
- Ván bot: 3/8 seed khớp y hệt; các seed khác lệch dần do Godot `Vector2` là float32, JS là float64.
- Số trên đo trước khi port Thánh Nộ làm boss khựng (thay đổi mới trên `main` TS); bot sim mặc định không bấm kỹ năng nên số không đổi.

Credits: xem `CREDITS.md` (KayKit, CC0).
