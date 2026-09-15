---
title: Lab Section 21 — Shared Pool Tuning + Session Cursors + Result Cache
course: 03-performance-tuning
source: The-Oracle-Database-Performance-Tuning-Course/labs/section_21/README.md
---

# Lab Section 21 — Shared Pool Tuning + Session Cursors + Result Cache

> Nguồn: Practice 20 + 21 + 22 (Ahmed Baraka) gộp thành 1 lab · Guide: [section_all/section_21_shared_pool_senior_guide... (xem section_all/)](../../section_all/)
> Chạy từ thư mục này (`labs/section_21/`). Quy ước chung: [labs/README.md](../readme.md)
> ⚠️ **Chưa kiểm chứng trên VM** — buổi chạy đầu tiên điền số thật vào mục "Số đo".

**Câu hỏi lab trả lời:** shared pool "ốm" trông thế nào qua time model/advisory; sau khi diệt hard parse (lab 20) thì tối ưu tiếp soft parse bằng session cursor cache ra sao; và khi nào trả thẳng KẾT QUẢ bằng Result Cache?

## Chạy lab

```powershell
sqlplus system/oracle_4U@//localhost:15210/ORADB
```

```
@01_setup.sql                        -- SGA/ASMM, library cache memory, snapshot B
@02_workload.sql                     -- ~4 phút: bão literal (tái dùng section_20/hard_parse.sh)
                                     --   + time model (hard parse %) + ASH CPU/phút + snap E
@03_diagnose.sql                     -- V$SHARED_POOL_ADVICE + vì sao KHÔNG tin advisory lúc bão
@04_usecase_session_cursor_cache.sql -- demo tắt/bật cache trong CHÍNH phiên mình + sizing
@05_usecase_result_cache.sql         -- RC: 2 lần chạy (gets → 0), object INVALID vì quá trần, nới trần
@06_usecase_library_cache_pin.sql    -- (mở rộng, SYS) compile package đang được gọi → treo
@99_cleanup.sql
```

File phụ trợ: `lc_pin_demo.sh` (2 caller + 1 compiler treo). Khác course: KHÔNG restart DB 3 lần (Practice 21) — dùng `ALTER SESSION` + V$MYSTAT trong chính phiên; năm 2017 → lấy năm MAX thật của ORDERS; 4 cửa sổ Putty → external job.

## Số đo (điền sau buổi chạy đầu tiên)

| Chỉ số | Kỳ vọng | Số thật |
|---|---|---|
| `hard parse elapsed time` % DB time lúc bão | tăng dần, chiếm % đáng kể | |
| Advisory: EST_TIME_SAVED khi tăng size lúc bão | tăng (bị triệu chứng đánh lừa) | |
| Cache TẮT, chạy 3 lần | hard +1, total +3, hits 0 | |
| Cache BẬT, chạy 3 lần | CURSOR_TYPE → DICTIONARY LOOKUP CURSOR CACHED, hits > 0 | |
| RC lần 1 vs lần 2 | consistent gets lớn → ~0 | |
| Kết quả > max_result | object INVALID, không dùng RC | |
| library cache pin | compiler treo, X$KGLOB → SOE.PCKORDERS | |

## 3 bài học phải thuộc

1. **Thang chi phí parse** (rẻ → đắt): app giữ cursor mở > session cursor cache hit > soft parse > hard parse. Lab 20 diệt tầng đắt nhất (bind); lab này tối ưu tầng giữa (cache 50 → sizing bằng "bao nhiêu phiên kịch trần") và tầng "không parse gì cả" (RC).
2. **Advisory chỉ tin khi đo lúc BÌNH THƯỜNG**: Shared Pool Advisory đo giữa bão literal sẽ xui tăng RAM cho bệnh mà thuốc là sửa code. Sizing dựa trên triệu chứng = mua thêm chỗ chứa rác.
3. **Result Cache là dao mổ, không phải búa**: chỉ cho dữ liệu ít đổi (DML lên bảng phụ thuộc → INVALIDATE hết); kết quả > `RESULT_CACHE_MAX_RESULT`% → object INVALID và RC vô dụng trong im lặng — phải kiểm tra `V$RESULT_CACHE_OBJECTS.STATUS`.

## Câu hỏi tự kiểm tra

1. Soft parse khác hard parse chỗ nào? Session cursor cache hit khác soft parse thường chỗ nào?
2. Vì sao course nói KHÔNG dùng được "hits/total parses %" để sizing session cursor cache? Quy tắc thay thế là gì?
3. Shared Pool Advisory đọc cột nào để quyết định? Đường cong "gãy khúc" nghĩa là gì?
4. RC object bị INVALID trong những tình huống nào (kể 2)? Kiểm tra bằng view nào?
5. Vì sao ALTER PACKAGE COMPILE có thể làm cả hệ thống khựng lại? Cách deploy an toàn trên hệ 24x7?


---

!!! info "Nguồn gốc"
    `The-Oracle-Database-Performance-Tuning-Course/labs/section_21/README.md`
