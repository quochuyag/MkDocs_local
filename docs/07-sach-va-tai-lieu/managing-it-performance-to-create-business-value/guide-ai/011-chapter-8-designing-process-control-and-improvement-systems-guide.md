---
title: 'Hướng Dẫn Học Tập: Thiết Kế Hệ Thống Kiểm Soát và Cải Thiện Quy Trình'
course: 07-sach-va-tai-lieu
source: pdf_md/managing-it-performance-to-create-business-value/guide_ai/11_chapter-8-designing-process-control-and-improvement-systems_guide.md
---

# Hướng Dẫn Học Tập: Thiết Kế Hệ Thống Kiểm Soát và Cải Thiện Quy Trình

**Nguồn sách:** Managing IT Performance to Create Business Value  
**Chương:** 8 — Designing Process Control and Improvement Systems  
**Ngày tạo:** 2026-04-26  
**Thời gian học ước tính:** 60–75 phút

---

## 🎯 Mục tiêu học tập

- **Hiểu** khái niệm IT Utility và cách bộ phận IT tự định vị như nhà cung cấp dịch vụ nội bộ
- **Phân biệt** giữa 6 cấp độ trưởng thành quy trình (0–5) trong Continuous Improvement Framework
- **Mô tả** các phương pháp cải tiến quy trình: DevOps, Kaizen, DMAIC, Six Sigma, Lean
- **Áp dụng** Balanced Scorecard vào đo lường chất lượng quy trình IT với ví dụ Philips Electronics
- **Đánh giá** quy trình Shared Services theo 7 bước của CIO Council
- **Mô tả** vai trò của Configuration Management (CM) trong kiểm soát và cải tiến quy trình
- **Áp dụng** Process Quality Index (PQI) để dự đoán chất lượng module phần mềm

---

## 📋 Tóm tắt nội dung chính

### IT Utility — Bộ phận IT như nhà cung cấp dịch vụ

Một công ty có thể dùng dữ liệu phân tích để xác định khách hàng không sinh lời và quyết định không giữ họ lại — nhưng rồi vẫn giữ vì Wall Street theo dõi tỷ lệ khách hàng rời bỏ như một chỉ số quan trọng. Câu chuyện này cho thấy: metrics có thể sai hướng, và cân bằng mục tiêu là then chốt trong quản lý hiệu suất kinh doanh.

Bộ phận IT nên tự xem mình là "IT Utility" — nhà cung cấp dịch vụ cho toàn tổ chức. Unisys cho thấy môi trường dựa trên hiệu suất tiết kiệm 10–40% chi phí so với môi trường không đo lường. Các dịch vụ IT thường được outsource gồm: quản lý tài sản, help desk, bảo trì cơ sở hạ tầng, quản lý hệ thống, quản lý mạng, tích hợp và cấu hình. Dù outsource hay không, quy trình phải được đo lường.

### Continuous Improvement Framework — 6 cấp độ trưởng thành

Khung cải tiến liên tục gồm 6 cấp: 0 (Incomplete), 1 (Initial — ad hoc), 2 (Repeatable — có kế hoạch và chính sách), 3 (Defined — chuẩn hóa theo tiêu chuẩn tổ chức), 4 (Quantitatively Managed — kiểm soát bằng thống kê), 5 (Optimizing — cải tiến liên tục dựa trên nguyên nhân biến thiên). Đây là nền tảng để đánh giá mức độ trưởng thành của tổ chức IT.

### Phương pháp cải tiến quy trình

**DevOps** tích hợp phát triển và vận hành (development + operations), kết hợp với **continuous delivery** (tự động hóa kiểm thử, triển khai) để tăng tốc độ ra thị trường và giảm chi phí. Một công ty du lịch quốc tế dùng DevOps để chuyển sang đám mây, tự động hóa kiểm thử và triển khai một-click, giảm đáng kể TTM (time-to-market).

**Kaizen** (tiếng Nhật: cải thiện liên tục) áp dụng cho tất cả chức năng và mọi nhân viên từ CEO đến nhân viên dịch vụ khách hàng. **DMAIC** (Define-Measure-Analyze-Improve-Control) là vòng lặp cải tiến dựa trên dữ liệu. **Lean Software Development** chuyển nguyên lý sản xuất Lean vào phát triển phần mềm.

**Hai tốc độ IT (two-speed IT):** tốc độ cao cho các ứng dụng hướng khách hàng (nhanh, linh hoạt), tốc độ ổn định cho hệ thống lõi (core systems, chất lượng dữ liệu cao). Một ngân hàng châu Âu đã dùng thiết kế song song (concurrent design) để rút ngắn quy trình đăng ký tài khoản từ 15 bước xuống còn 5 bước.

### Chất lượng quy trình và Balanced Scorecard

Philips Electronics tích hợp chất lượng vào trung tâm của Balanced Scorecard với 4 cấp: strategy review card → operations review scorecard → business unit card → individual employee card. Ba tiêu chí cascade scorecard: Inclusion (CSF cấp trên phải được addressed bởi CSF cấp dưới), Continuity (kết nối liên tục qua các cấp), Robustness (đạt CSF cấp dưới phải đảm bảo đạt CSF cấp trên). Hệ thống traffic-light (xanh/vàng/đỏ) giúp chia sẻ metrics với nhân viên.

**Process Quality Index (PQI)** = tích của 5 chiều chất lượng module phần mềm: tỷ lệ thiết kế/coding, review thiết kế, review code, mật độ lỗi compile, mật độ lỗi unit test. PQI từ 0.4–1.0 dự báo module sẽ có zero defects sau này.

### Shared Services — 7 bước của CIO Council

Nguyên tắc "shared-first" (ưu tiên dùng dịch vụ chung) nhằm cải thiện ROI, giảm chi phí và tăng tốc độ đổi mới. Bảy bước: (1) Kiểm kê và đánh giá, (2) Xác định nhà cung cấp tiềm năng, (3) So sánh dịch vụ nội bộ vs. shared services, (4) Ra quyết định đầu tư, (5) Xác định phương thức tài trợ, (6) Thiết lập SLA, (7) Quản lý sau triển khai.

### Configuration Management (CM)

CM quản lý toàn bộ sản phẩm, cơ sở vật chất và quy trình của tổ chức — bao gồm mọi yêu cầu và thay đổi, đảm bảo kết quả phù hợp với yêu cầu. Quy trình CM về cơ bản không thay đổi trong 20–30 năm qua, chỉ có môi trường thay đổi. Các tổ chức Level 1 (SEI CMM) dựa vào "heroes" — ít người biết cách làm việc, quy trình ad hoc và hỗn loạn. CM hiệu quả tổ chức hóa kiến thức này, theo dõi và tài liệu hóa mọi thay đổi.

---

## 🔑 Khái niệm quan trọng

| Khái niệm | Định nghĩa | Tại sao quan trọng | Ví dụ | Liên quan đến |
|---|---|---|---|---|
| **IT Utility** | Cách bộ phận IT tự định vị như nhà cung cấp dịch vụ nội bộ cho tổ chức | Tạo tư duy dịch vụ, đo lường theo SLA như outsourcing | Bộ phận IT cung cấp help desk như Unisys cung cấp cho khách hàng | Balanced Scorecard, Shared Services |
| **DMAIC** | Vòng lặp cải tiến: Define → Measure → Analyze → Improve → Control | Phương pháp có cấu trúc để cải tiến quy trình dựa trên dữ liệu | Giảm thời gian xử lý ticket từ 5 ngày xuống 1 ngày | Six Sigma, BPM |
| **DevOps** | Tích hợp phát triển (Dev) và vận hành (Ops) với tự động hóa kiểm thử và triển khai | Tăng tốc độ ra thị trường, giảm lỗi do tự động hóa | Intuit dùng "infrastructure as code" để tự động hóa toàn bộ | Continuous Delivery, Kaizen |
| **PQI** (Process Quality Index) | Tích của 5 chiều chất lượng module phần mềm; PQI 0.4–1.0 = zero defects | Dự báo sớm chất lượng module trước khi test | PQI = 0.6 sau unit test → dự báo module không có lỗi thêm | Balanced Scorecard, Quality |
| **Two-Speed IT** | Mô hình IT hai tốc độ: nhanh cho ứng dụng khách hàng, ổn định cho core systems | Cân bằng giữa đổi mới nhanh và ổn định hệ thống nền tảng | Ngân hàng có team "fast IT" phát triển mobile app, team "slow IT" duy trì core banking | DevOps, Agile |
| **Shared Services** | Tập trung hóa các dịch vụ chung để loại bỏ trùng lặp và giảm chi phí | Giảm chi phí vận hành, tăng tính nhất quán và chất lượng dịch vụ | Trung tâm dữ liệu dùng chung cho nhiều cơ quan chính phủ | CM, IT Utility |
| **Configuration Management (CM)** | Quản lý toàn bộ sản phẩm và quy trình tổ chức: theo dõi mọi yêu cầu và thay đổi | Nền tảng cho cải tiến — phải biết hiện trạng trước khi thay đổi | Hệ thống Git + change control board cho dự án phần mềm lớn | Process Improvement, CMMI |
| **Kaizen** | Triết lý cải tiến liên tục (tiếng Nhật), áp dụng cho mọi cấp của tổ chức | Tạo văn hóa cải tiến từ dưới lên, không chỉ từ trên xuống | Toyota áp dụng Kaizen cho dây chuyền sản xuất; IT áp dụng cho CI/CD | DMAIC, Lean, DevOps |

---

## 🌍 Ví dụ thực tế & Case Study

### Case Study 1: Compaq (nay là HP) — Balanced Scorecard cho IT

**Bối cảnh:** Vào cuối những năm 1990, Compaq đang đối mặt với áp lực cạnh tranh khốc liệt trong ngành máy tính. Công ty triển khai Balanced Scorecard vào năm 1997 để cải thiện hiệu suất toàn diện.

**Vấn đề:** Các quy trình kinh doanh rời rạc: đặt hàng không kết nối với sản xuất, thông tin nhà cung cấp không chia sẻ, không có cách để theo dõi đơn hàng của khách hàng. Dẫn đến chu kỳ giao hàng dài và chi phí vận hành cao.

**Giải pháp:** Compaq reengineering toàn bộ quy trình kinh doanh trước, sau đó mới thay đổi hệ thống IT. Triển khai SAP R/3 để tích hợp quy trình và thông tin bán hàng. Xây dựng extranet Compaq On-Line để khách hàng cấu hình và đặt máy tính trực tiếp. Liên kết đơn hàng điện tử với nhà cung cấp để hỗ trợ JIT manufacturing.

**Kết quả:** Doanh số tăng sau 1997; đạt được bằng cách tạo giá trị, tăng dịch vụ khách hàng, cải tiến sản phẩm và giảm TTM. Chu kỳ thời gian được cải thiện, chi phí giảm, thu nhập ròng và doanh thu mỗi nhân viên tăng.

**Bài học:** Quy trình phải được reengineering trước khi IT được triển khai — công nghệ chỉ hỗ trợ quy trình đã được thiết kế tốt, không tự mình sửa chữa quy trình xấu.

---

### Case Study 2: Ngân hàng châu Âu áp dụng Two-Speed IT 🇻🇳 Liên hệ Việt Nam

**Bối cảnh:** Một ngân hàng tại Đông Âu cần cải thiện trải nghiệm đăng ký tài khoản trực tuyến — từ 15 bước phức tạp xuống còn mức cạnh tranh.

**Vấn đề:** Core banking system ổn định nhưng chậm thay đổi. Trong khi đó, khách hàng kỳ vọng trải nghiệm số nhanh và đơn giản như các fintech startup.

**Giải pháp:** Ngân hàng thành lập "fast IT team" riêng biệt với quyền tự chủ. Nhóm dùng concurrent design (nhiệm vụ song song) để phát triển prototype, tái sử dụng tối đa hệ thống hiện có. Test với khách hàng thực tế trong môi trường live và cải tiến liên tục. Kết quả: quy trình từ 15 bước → 5 bước.

**Liên hệ Việt Nam:** Các ngân hàng Việt Nam như VPBank, Techcombank đang áp dụng mô hình tương tự: duy trì core banking ổn định (T24, Flexcube) trong khi xây dựng layer digital banking riêng biệt phát triển nhanh để cạnh tranh với MoMo, ZaloPay.

**Bài học:** Two-speed IT không phải hai hệ thống tách biệt hoàn toàn — mà là phân lớp rõ ràng với API tích hợp, cho phép tốc độ khác nhau mà không mất tính toàn vẹn dữ liệu.

---

### Case Study 3: Intuit và Continuous Development

**Bối cảnh:** Intuit, công ty phần mềm kế toán (TurboTax, QuickBooks), chạy trên hàng chục nền tảng khác nhau — đặt ra thách thức infrastructure khổng lồ.

**Vấn đề:** Mỗi lần release phần mềm tốn nhiều thời gian kiểm thử thủ công. Quản lý infrastructure cho môi trường development, test và production đòi hỏi nhiều nhân lực.

**Giải pháp:** Intuit triển khai "infrastructure as code" — toàn bộ infrastructure được lập trình và tự động hóa. Mọi code commit đều được chạy automated unit tests, smoke tests. Một số dự án đạt continuous deployment (tự động lên production), số khác ở mức continuous delivery (cần review trước production).

**Kết quả:** Giảm thời gian từ code → production. Phát hiện lỗi sớm hơn với chi phí sửa chữa thấp hơn. Nhóm phát triển có thể tập trung vào tính năng thay vì quản lý infrastructure.

**Bài học:** Continuous development đòi hỏi culture shift toàn diện — không chỉ công cụ kỹ thuật mà cả PM, developers, QA, và operations phải cộng tác khác đi. Không thể áp đặt DevOps mà không thay đổi văn hóa.

---

## 📊 Sơ đồ & Bảng tổng hợp

### Bảng 1: 6 cấp độ Continuous Improvement Framework

| Cấp độ | Tên | Đặc điểm chính | Dấu hiệu nhận biết |
|---|---|---|---|
| 0 | Incomplete | Quy trình không thực hiện hoặc thực hiện một phần | Không đạt specific goals |
| 1 | Initial | Ad hoc, đôi khi hỗn loạn, phụ thuộc "heroes" | Không có tài liệu quy trình, chỉ một số người biết cách làm |
| 2 | Repeatable | Có kế hoạch, thực thi theo chính sách, kiểm soát | Quy trình được lập kế hoạch, có corrective actions khi lệch |
| 3 | Defined | Chuẩn hóa theo tiêu chuẩn tổ chức | Dùng quy trình chuẩn của tổ chức, có tailoring guidelines |
| 4 | Quantitatively Managed | Kiểm soát bằng thống kê, đo lường được | Dùng SPC, dự báo được performance tương lai |
| 5 | Optimizing | Cải tiến liên tục dựa trên phân tích nguyên nhân biến thiên | Incremental + innovative improvements, giải quyết common causes |

### Bảng 2: So sánh các phương pháp cải tiến quy trình

| Phương pháp | Nguồn gốc | Trọng tâm | Phù hợp khi |
|---|---|---|---|
| Six Sigma | Motorola (1980s) | Giảm defects theo thống kê (≤3.4 defects/triệu) | Cần giảm biến thiên và lỗi đo được |
| DMAIC | Six Sigma | Cải tiến quy trình hiện có bằng dữ liệu | Vấn đề đã xác định, muốn cải tiến có hệ thống |
| Kaizen | Nhật Bản (Toyota) | Cải tiến nhỏ liên tục, mọi cấp nhân viên | Văn hóa cải tiến từ dưới lên, mọi ngày |
| DevOps | Industry (2009+) | Tích hợp Dev + Ops, tự động hóa CI/CD | Muốn tăng tốc deployment và giảm lỗi production |
| Lean Software | Manufacturing Lean | Loại bỏ lãng phí trong software development | Giảm waste: chờ đợi, rework, overproduction |
| BPM | Operations Management | Quản lý và tối ưu hóa toàn bộ business processes | Cần cải thiện quy trình kinh doanh tổng thể |

### Sơ đồ: Vòng lặp Continuous Development

```
Code commit → Automated unit tests → Smoke tests
      ↓ pass
Integration tests → Staging environment → Review/approval
      ↓ pass
Production deployment ←→ Monitoring & feedback
      ↓
Identify improvement → Code commit (vòng lặp tiếp theo)
```

---

## ❓ Câu hỏi ôn tập

**Câu 1 (Nhớ lại):** PQI được tính như thế nào và giá trị nào dự báo module sẽ không có lỗi?

💡 *Gợi ý: PQI là tích của 5 chiều, giá trị ngưỡng là 0.4.*

📝 *Đáp án:* PQI (Process Quality Index) được tính bằng cách nhân 5 chiều chất lượng module phần mềm: (1) tỷ lệ thời gian thiết kế/coding phải lớn hơn 1 (thiết kế nhiều hơn code); (2) thời gian review thiết kế phải ≥ 50% thời gian thiết kế; (3) thời gian review code phải ≥ 50% thời gian coding; (4) mật độ lỗi compile < 10 lỗi/1000 dòng code; (5) mật độ lỗi unit test < 5 lỗi/1000 dòng code. SEI cho thấy PQI từ 0.4 đến 1.0 dự báo module sẽ có zero defects sau unit test. PQI hữu ích vì giá trị của nó đã biết ngay sau khi developer hoàn thành unit test, trước khi bước vào integration testing — giúp phát hiện sớm module cần chú ý thêm.

---

**Câu 2 (Nhớ lại):** Nguyên tắc "Shared First" của CIO Council là gì và nó mang lại những lợi ích gì?

💡 *Gợi ý: "Shared First" = ưu tiên dùng dịch vụ chung trước khi xây dựng riêng.*

📝 *Đáp án:* "Shared First" là nguyên tắc của CIO Council liên bang Mỹ: khi cần một dịch vụ IT, tổ chức nên tìm kiếm và sử dụng shared services đang có trước khi xây dựng hoặc mua riêng. Lợi ích bao gồm: loại bỏ chi phí trùng lặp từ nhiều phòng ban làm cùng việc; tăng tốc độ triển khai bằng cách dùng dịch vụ đã có sẵn; cải thiện ROI thông qua quy mô kinh tế; thúc đẩy đổi mới bằng cách tập trung nguồn lực vào core mission thay vì hạ tầng hỗ trợ; giảm rủi ro bằng cách dùng dịch vụ đã được kiểm chứng. Shared services bao gồm commodity IT (data centers, networks, software) và support services (tài chính, HR, asset management).

---

**Câu 3 (Thông hiểu):** Tại sao chương mở đầu bằng câu chuyện công ty quyết định giữ lại khách hàng không sinh lời? Bài học quản lý là gì?

💡 *Gợi ý: Nghĩ về Wall Street metrics vs. business value thực sự.*

📝 *Đáp án:* Câu chuyện minh họa hai điểm quan trọng: (1) metrics có thể sai hướng — một quyết định đúng về tài chính nội bộ (loại bỏ khách hàng không sinh lời) có thể sai về mặt thị trường vì Wall Street dùng customer churn rate như tín hiệu sức khỏe công ty; (2) cần cân bằng nhiều mục tiêu thay vì tối ưu hóa một chỉ số duy nhất. Bài học quản lý: khi thiết kế hệ thống đo lường hiệu suất, phải hiểu rằng mọi metric đều có thể bị "gamified" hoặc dẫn đến hành vi không mong muốn nếu nhìn một chiều. Balanced Scorecard ra đời chính vì lý do này — cân bằng tài chính, khách hàng, quy trình, và học hỏi/phát triển để tránh tối ưu hóa cục bộ gây hại toàn cục.

---

**Câu 4 (Thông hiểu):** So sánh Continuous Delivery và Continuous Deployment. Tổ chức nào phù hợp với mỗi mức?

💡 *Gợi ý: Sự khác biệt nằm ở bước review thủ công cuối cùng.*

📝 *Đáp án:* **Continuous Delivery** có nghĩa là code luôn ở trạng thái sẵn sàng deploy và được đẩy lên staging environment, nhưng cần có review và approval thủ công trước khi lên production. **Continuous Deployment** đi xa hơn — mọi thay đổi vượt qua automated tests đều tự động lên production mà không cần can thiệp thủ công. Ví dụ từ Intuit: một số dự án đạt continuous deployment, số khác vẫn ở continuous delivery với manual review trước khi production, và một số dự án cần manual testing bởi QA engineers. Tổ chức phù hợp với Continuous Deployment: startup tech với tolerance cao cho rapid iteration và rollback nhanh. Tổ chức phù hợp với Continuous Delivery: ngân hàng, y tế, chính phủ — nơi mỗi thay đổi production cần audit trail và human sign-off vì lý do compliance hoặc risk management.

---

**Câu 5 (Ứng dụng):** Bộ phận IT của một công ty logistics Việt Nam đang ở Level 1 (Initial) theo Continuous Improvement Framework. Hãy đề xuất kế hoạch 3 bước để nâng lên Level 3, với metrics đo lường tiến độ.

💡 *Gợi ý: Level 1 → 2 = có kế hoạch và chính sách; Level 2 → 3 = chuẩn hóa theo tiêu chuẩn tổ chức.*

📝 *Đáp án:* **Bước 1 (nâng lên Level 2 — Repeatable):** Tài liệu hóa các quy trình IT hiện tại — dù ad hoc, vẫn phải viết ra cách đang làm; lập policy cho incident management, change management, deployment; triển khai ITSM tool (ví dụ: Jira Service Desk); chỉ định owner cho mỗi quy trình. Metrics: % quy trình được tài liệu hóa (mục tiêu: 80% trong 3 tháng); % incidents được ghi nhận trong hệ thống.

**Bước 2 (nâng lên Level 3 — Defined):** Chuẩn hóa quy trình theo ITIL hoặc tiêu chuẩn nội bộ thống nhất; áp dụng một bộ quy trình cho toàn bộ dự án thay vì mỗi team làm khác nhau; training nhân viên theo tiêu chuẩn mới; thiết lập configuration management. Metrics: % projects tuân theo quy trình chuẩn (mục tiêu: 90%); điểm audit nội bộ.

**Bước 3 (củng cố Level 3):** Triển khai Configuration Management Board (CMB) để kiểm soát thay đổi; tổ chức retrospective hàng tháng để nhận diện process gaps; kết nối quy trình IT với Balanced Scorecard của tổ chức. Metrics: số lỗi production do thiếu change control; thời gian trung bình xử lý change request.

---

## 💡 Ghi nhớ nhanh

- ✅ **IT là nhà cung cấp dịch vụ:** Tư duy IT Utility giúp bộ phận IT đo lường và cải tiến như doanh nghiệp thực sự
- ✅ **PQI = tích của 5 chiều:** Giá trị 0.4–1.0 dự báo zero defects — đo được ngay sau unit test
- ✅ **Shared First trước khi build:** Luôn tìm shared services trước khi đầu tư xây dựng riêng
- ⚠️ **DevOps cần văn hóa thay đổi:** Công cụ CI/CD chỉ hoạt động khi cả team — PM, dev, QA, ops — cộng tác theo cách mới
- ⚠️ **Metrics có thể sai hướng:** Như câu chuyện mở đầu — một metric tốt cho một stakeholder có thể xấu cho tổ chức
- ⚠️ **Level 1 không thể nhảy thẳng Level 5:** Phải qua từng cấp; Level 2 (Repeatable) trước tiên
- 🔗 **Chương trước (7):** RMMM cung cấp nền tảng để process improvement có thể thực hiện an toàn; Chapter 8 cho biết cách đo lường và cải tiến sau khi rủi ro đã được quản lý

---

## 📖 Giải thích thuật ngữ chuyên ngành

**IT Utility (Tiện ích IT)**
Cách định vị bộ phận IT như nhà cung cấp dịch vụ hạ tầng cho toàn tổ chức, tương tự điện hay nước — sẵn sàng theo nhu cầu, được tính phí theo mức sử dụng. Như công ty điện lực cung cấp điện cho hộ gia đình theo KWh. Giúp IT có tư duy dịch vụ và đo lường hiệu suất theo tiêu chuẩn khách hàng.

**DevOps**
Kết hợp văn hóa, thực hành và công cụ của nhóm phát triển phần mềm (Dev) và nhóm vận hành hệ thống (Ops) để tự động hóa và tích hợp các quy trình từ build đến deploy. Như "dây chuyền lắp ráp tự động" của phần mềm: từ code đến production với ít can thiệp thủ công nhất có thể. Tăng tần suất và độ tin cậy của việc phát hành phần mềm.

**Continuous Delivery (Phân phối liên tục)**
Thực hành đảm bảo code luôn ở trạng thái sẵn sàng deploy lên production bất cứ lúc nào, thông qua pipeline kiểm thử tự động. Có bước review/approval thủ công trước production. Như hàng trong kho đã được kiểm tra chất lượng, chỉ chờ lệnh xuất. Giảm rủi ro release và tăng tin cậy với stakeholders.

**DMAIC (Define-Measure-Analyze-Improve-Control)**
Vòng lặp cải tiến quy trình 5 bước của Six Sigma: xác định vấn đề → đo lường hiện trạng → phân tích nguyên nhân gốc rễ → cải tiến → kiểm soát để duy trì cải tiến. Như phương pháp khoa học ứng dụng vào kinh doanh. Đảm bảo cải tiến dựa trên dữ liệu, không phải cảm tính.

**Kaizen (改善)**
Triết lý Nhật Bản về cải tiến liên tục nhỏ bằng cách tất cả nhân viên ở mọi cấp độ thực hiện hàng ngày, thay vì chờ đợi cải tiến lớn. Như chạy bộ mỗi ngày 1km thay vì tập gym 1 lần/tháng. Xây dựng văn hóa không ngừng cải thiện trong tổ chức.

**Configuration Management — CM (Quản lý cấu hình)**
Quá trình kiểm soát có hệ thống mọi thay đổi đối với sản phẩm, hệ thống hoặc quy trình của tổ chức; đảm bảo tính toàn vẹn và truy xuất nguồn gốc. Như "lịch sử y tế" của phần mềm — biết chính xác ai thay đổi gì, khi nào, tại sao. Nền tảng cho mọi hoạt động cải tiến quy trình.

**PQI — Process Quality Index (Chỉ số chất lượng quy trình)**
Chỉ số dự báo chất lượng module phần mềm bằng cách nhân 5 chiều đo được ngay sau unit test: thiết kế/coding ratio, design review ratio, code review ratio, compile defect density, unit test defect density. Như "điểm tín dụng" của module: cho biết nguy cơ có lỗi trong tương lai. PQI ≥ 0.4 dự báo zero subsequent defects.

**Shared Services (Dịch vụ chung)**
Mô hình tập trung hóa các chức năng hỗ trợ (IT, tài chính, HR) vào một đơn vị phục vụ chung cho nhiều phòng ban, thay vì mỗi phòng ban có team riêng. Như căng-tin chung cho toàn công ty thay vì mỗi phòng tự nấu ăn. Giảm chi phí trùng lặp và tạo tính nhất quán.

**SLA — Service Level Agreement (Thỏa thuận mức dịch vụ)**
Hợp đồng chính thức giữa nhà cung cấp dịch vụ và khách hàng định nghĩa: dịch vụ được cung cấp là gì, mức chất lượng tối thiểu, cách đo lường, hậu quả nếu không đạt. Như cam kết của nhà mạng: "internet 100Mbps, uptime 99.9%". Cơ sở pháp lý và đo lường cho IT utility và shared services.

**BPM — Business Process Management (Quản lý quy trình kinh doanh)**
Lĩnh vực quản lý vận hành tập trung vào cải thiện hiệu suất doanh nghiệp bằng cách quản lý và tối ưu hóa các quy trình kinh doanh từ đầu đến cuối. Như "bản đồ" và "GPS" cho tất cả hoạt động của công ty. Kết hợp với IT để số hóa và tự động hóa quy trình.

**Two-Speed IT (IT hai tốc độ)**
Mô hình kiến trúc IT trong đó tầng ứng dụng hướng khách hàng (digital layer) phát triển nhanh và linh hoạt, trong khi hệ thống lõi (core systems) phát triển chậm hơn với ưu tiên ổn định và toàn vẹn dữ liệu. Như xe có số tự động (fast layer) và hệ thống khung gầm (core layer) — cùng một xe nhưng phản ứng khác nhau. Cho phép ngân hàng và tổ chức lớn đổi mới nhanh mà không mạo hiểm hệ thống nền tảng.


---

!!! info "Nguồn gốc"
    `pdf_md/managing-it-performance-to-create-business-value/guide_ai/11_chapter-8-designing-process-control-and-improvement-systems_guide.md`
