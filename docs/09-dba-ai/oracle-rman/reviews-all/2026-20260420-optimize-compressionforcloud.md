---
title: '🛠️ Thử Thách Tối Ưu: Ép Cân Backup Lên Cloud'
course: 09-dba-ai
source: dba_ai/oracle_rman/reviews_all/20260420_Optimize_CompressionForCloud.md
---

# 🛠️ Thử Thách Tối Ưu: Ép Cân Backup Lên Cloud

**Chế độ**: Tối ưu & Tái cấu trúc (Optimization Challenge - Module 8, 17)
**Ngày tạo**: 2026-04-20

## 1. Tình huống doanh nghiệp
Công ty của bạn vừa chuyển đổi hệ thống lưu trữ dự phòng sang Oracle Cloud Infrastructure (OCI) Object Storage để tiết kiệm chi phí băng thông và lưu trữ. 
Database `CRMDB` của công ty có dung lượng **3TB**.

Vấn đề hiện tại:
1. Bạn có một kênh truyền (Network Bandwidth) lên Cloud rất giới hạn (chỉ 500Mbps). Với tốc độ này, việc đẩy 3TB backup lên Cloud mất quá nhiều thời gian, có khi đứt kết nối giữa chừng.
2. Chi phí lưu trữ Cloud tính theo GB, vì thế công ty yêu cầu bạn phải nén file backup nhỏ nhất có thể.
3. Database có vài file dữ liệu (Datafile) khổng lồ, mỗi file nặng tới 500GB, khiến các channel của RMAN bị "kẹt" xử lý.

### Script backup Cloud hiện tại:
```rman
RUN {
  ALLOCATE CHANNEL c1 DEVICE TYPE sbt 
    PARMS='SBT_LIBRARY=/opt/oracle/lib/libopc.so, SBT_PARMS=(OPC_PFILE=/opt/oracle/opcCRMDB.ora)';
  BACKUP DATABASE;
}
```

## 2. Nhiệm vụ của bạn (DBA)
Viết lại đoạn Script RMAN trên bằng cách áp dụng 3 kỹ thuật tối ưu cốt lõi:
1. Đa luồng (đẩy qua nhiều kênh mạng cùng lúc).
2. Nén dữ liệu (tiết kiệm tiền Cloud và băng thông).
3. Cắt nhỏ các file 500GB ra thành các khúc nhỏ (Section Size) để backup song song.

---

## 3. Hướng dẫn xử lý (Action Plan - Đáp án)

Đoạn script hiện tại quá "ngây thơ" khi chỉ phân bổ đúng 1 channel, không nén, không cắt nhỏ, dẫn tới thất bại hoàn toàn trên môi trường Cloud.
Dưới đây là Script tối ưu kết hợp 3 siêu kỹ thuật của RMAN (Module 8):

### Kịch bản Tái cấu trúc (RMAN Script Mới):

**Bước 1: Cấu hình mặc định thuật toán Nén (Compression Algorithm)**
Mặc định Oracle nén bằng `BASIC` (miễn phí). Tuy nhiên nếu cty có bản quyền Advanced Compression, hãy dùng `MEDIUM` để cân bằng hoàn hảo giữa mức độ nén và CPU.
```rman
RMAN> CONFIGURE COMPRESSION ALGORITHM 'MEDIUM';
```

**Bước 2: Script Backup Tối Ưu Hóa**
```rman
RUN {
  -- 1. Đa luồng: Cấp phát 4 Channels để gửi dữ liệu song song lên Cloud
  ALLOCATE CHANNEL c1 DEVICE TYPE sbt PARMS='...';
  ALLOCATE CHANNEL c2 DEVICE TYPE sbt PARMS='...';
  ALLOCATE CHANNEL c3 DEVICE TYPE sbt PARMS='...';
  ALLOCATE CHANNEL c4 DEVICE TYPE sbt PARMS='...';
  
  -- 2 & 3. Áp dụng Nén (COMPRESSED) và Cắt nhỏ Datafile (SECTION SIZE)
  BACKUP AS COMPRESSED BACKUPSET 
  SECTION SIZE 50G 
  DATABASE;
}
```

### Phân tích giá trị của đoạn Script mới:
1. **Đa luồng (Parallelism = 4)**: Cùng lúc có 4 luồng dữ liệu đẩy lên OCI, tận dụng tối đa băng thông mạng.
2. **AS COMPRESSED BACKUPSET**: RMAN sẽ sử dụng CPU tại server Local để nén dữ liệu (từ 3TB có thể xuống còn 500GB - 800GB) trước khi đẩy qua mạng. Điều này giải quyết cả bài toán Network (chuyển ít byte hơn) và bài toán chi phí lưu trữ Cloud.
3. **SECTION SIZE 50G**: Datafile 500GB khổng lồ sẽ được chia thành 10 khối nhỏ (mỗi khối 50GB). Thay vì 1 channel phải cõng 500GB mướt mồ hôi, bây giờ 4 channels sẽ chia nhau mỗi channel nén và backup một khối 50GB song song, tăng tốc độ xử lý Datafile lớn lên gấp 4 lần.


---

!!! info "Nguồn gốc"
    `dba_ai/oracle_rman/reviews_all/20260420_Optimize_CompressionForCloud.md`
