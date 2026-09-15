---
title: 'Hướng Dẫn Học Tập: Thiết Kế Hệ Thống Quản Lý Rủi Ro Dựa Trên Hiệu Suất'
course: 07-sach-va-tai-lieu
source: pdf_md/managing-it-performance-to-create-business-value/guide_ai/10_chapter-7-designing-performance-based-risk-management-systems_guide.md
---

# Hướng Dẫn Học Tập: Thiết Kế Hệ Thống Quản Lý Rủi Ro Dựa Trên Hiệu Suất

**Nguồn sách:** Managing IT Performance to Create Business Value  
**Chương:** 7 — Designing Performance-Based Risk Management Systems  
**Ngày tạo:** 2026-04-26  
**Thời gian học ước tính:** 60–75 phút

---

## 🎯 Mục tiêu học tập

- **Hiểu** vai trò của chiến lược rủi ro chủ động (proactive risk strategy) trong quản lý dự án IT
- **Phân biệt** giữa rủi ro dự án (project risks), rủi ro kỹ thuật (technical risks) và rủi ro kinh doanh (business risks)
- **Mô tả** quy trình phân tích rủi ro định lượng qua các công thức EF, SLE, ARO, ALE
- **Áp dụng** RMMM (Risk Mitigation, Monitoring, and Management) để lập kế hoạch xử lý rủi ro
- **Đánh giá** các phương pháp phân tích rủi ro định lượng: Monte Carlo, Probability Trees, Analytical Methods
- **Mô tả** các framework đánh giá rủi ro IT: OCTAVE và FAIR
- **Áp dụng** các metrics đo lường quy trình quản lý rủi ro trong tổ chức

---

## 📋 Tóm tắt nội dung chính

### Chiến lược rủi ro (Risk Strategy)

Chiến lược chủ động (proactive strategy) là cách tiếp cận đúng đắn: luôn lên kế hoạch trước cho rủi ro thay vì phản ứng khi khủng hoảng xảy ra. Xác suất rủi ro (risk probability) là khả năng xảy ra sự kiện rủi ro, còn tác động rủi ro (risk impact) là hệ quả tổng hợp của xác suất và hậu quả. Trong vòng đời dự án (initiating, planning, executing, controlling, closing), rủi ro có xác suất cao hơn ở giai đoạn đầu nhưng tác động nhẹ hơn; ngược lại, rủi ro ở giai đoạn cuối ít xảy ra hơn nhưng hậu quả nghiêm trọng hơn nhiều.

### Phân tích rủi ro (Risk Analysis)

Công thức định lượng rủi ro bao gồm:
- **EF** (Exposure Factor): phần trăm tài sản bị thiệt hại
- **SLE** (Single Loss Expectancy) = Giá trị tài sản × EF
- **ARO** (Annualized Rate of Occurrence): tần suất xảy ra trong năm
- **ALE** (Annualized Loss Expectancy) = SLE × ARO
- **Phân tích lợi ích biện pháp bảo vệ** = ALE trước − ALE sau − Chi phí biện pháp

Scenario planning (lập kịch bản) là công cụ hữu ích nhưng dễ bị lạm dụng. McKinsey đề xuất "cheat sheet" với 5 nguyên tắc: bắt đầu từ thông tin thực tế, xây dựng kịch bản quanh những bất định then chốt, đánh giá tác động từng kịch bản, khuyến khích tranh luận mở, và thể chế hóa tư duy kịch bản.

### Nhận diện và phân loại rủi ro (Risk Identification)

Rủi ro phần mềm thuộc ba loại chính: rủi ro dự án (ngân sách, lịch trình, nhân sự), rủi ro kỹ thuật (thiết kế, giao diện, công nghệ lỗi thời), và rủi ro kinh doanh (thị trường, quản lý, chiến lược). Ngoài ra rủi ro còn được phân loại theo khả năng biết trước: known risks (có thể phát hiện khi xem xét kỹ kế hoạch), predictable risks (dự đoán từ kinh nghiệm quá khứ), và unpredictable risks (không thể biết trước).

**Risk table** là công cụ đơn giản: liệt kê rủi ro, phân loại, xác suất, và mức độ tác động (1: Catastrophic → 4: Negligible), sau đó sắp xếp theo ưu tiên.

### RMMM và tránh rủi ro

Kế hoạch RMMM (Risk Mitigation, Monitoring, and Management) mô tả cách từng rủi ro sẽ được giám sát và xử lý. Process Quality Management (PQM), phát triển bởi IBM, dùng Critical Success Factors (CSF) để phòng ngừa rủi ro thông qua việc xác định mục tiêu, brainstorm nhân tố cản trở, liệt kê business processes và ưu tiên hóa qua priority graph.

### Phân tích định lượng (Quantitative Risk Analysis)

Ba loại phân tích: kỹ thuật (technical performance), lịch trình (schedule), và chi phí (cost). Các phương pháp:
- **Analytical methods** (second-moment): tính mean và standard deviation, đơn giản nhưng ít hữu ích cho schedule risk
- **Monte Carlo simulation**: vẽ mẫu ngẫu nhiên từ phân phối xác suất, linh hoạt và phổ biến nhất
- **Probability trees / Decision trees**: mô hình hóa xác suất có điều kiện, mạnh mẽ nhưng phức tạp

### Framework đánh giá rủi ro IT

**OCTAVE** (Carnegie Mellon): đánh giá rủi ro từ góc nhìn vật lý, kỹ thuật và con người; do các nhóm nhỏ liên phòng ban thực hiện để tăng cộng tác.

**FAIR** (Factor Analysis of Information Risk): 4 giai đoạn — xác định thành phần kịch bản → đánh giá tần suất mất mát → đánh giá mức độ mất mát → diễn đạt rủi ro. Dùng ước tính bằng đô la và giá trị xác suất để mô hình hóa toán học.

### Đo lường quy trình rủi ro

Bất kỳ checklist nào trong chương đều có thể chuyển thành metrics đo lường. Ví dụ: "% rủi ro chính đã được giảm thiểu", "thời gian từ đầu vào đến khi leo thang lên người ra quyết định", "số lần ban lãnh đạo xem xét chiến lược quản lý rủi ro".

---

## 🔑 Khái niệm quan trọng

| Khái niệm | Định nghĩa | Tại sao quan trọng | Ví dụ | Liên quan đến |
|---|---|---|---|---|
| **Risk Probability** (Xác suất rủi ro) | Khả năng xảy ra sự kiện rủi ro, từ 1 (rất thấp) đến 5 (rất cao) | Giúp ưu tiên hóa rủi ro cần quản lý | Khả năng 70% khách hàng thay đổi yêu cầu | Risk Table, RMMM |
| **ALE** (Annualized Loss Expectancy) | Tổn thất kỳ vọng hàng năm = SLE × ARO | Cơ sở tính lợi ích của biện pháp bảo vệ | Tổn thất 50,000 USD/năm do sự cố bảo mật | EF, SLE, ARO |
| **RMMM** (Risk Mitigation, Monitoring, Management) | Kế hoạch ba chiều: giảm thiểu, giám sát và quản lý từng rủi ro | Tài liệu hóa cách ứng phó với mỗi rủi ro | Tài liệu mô tả biện pháp kỹ thuật cho rủi ro bảo mật | Risk Identification |
| **Monte Carlo Simulation** | Mô phỏng bằng máy tính dùng số ngẫu nhiên để đánh giá tác động của nhiều bất định | Phương pháp phổ biến nhất cho phân tích rủi ro dự án | Ước tính chi phí dự án với 80% độ tin cậy | Quantitative Risk Analysis |
| **OCTAVE** | Framework đánh giá rủi ro IT từ Carnegie Mellon, xét tất cả góc độ: người, quy trình, công nghệ | Cung cấp đánh giá toàn diện và có tài liệu rõ ràng | Nhóm liên phòng ban đánh giá rủi ro hệ thống ERP | FAIR, IT Risk Frameworks |
| **CSF** (Critical Success Factors) | Những nhiệm vụ cụ thể mà nhóm phải hoàn thành để đạt sứ mệnh | Cơ sở để xây dựng PQM và tránh rủi ro chiến lược | "Đàm phán với nhà cung cấp" là CSF cho dự án JIT | PQM, Risk Avoidance |
| **Scenario Planning** | Xây dựng nhiều kịch bản tương lai để ra quyết định trong điều kiện bất định | Giúp chuẩn bị cho các tương lai khác nhau, không chỉ tương lai "có thể nhất" | Ngân hàng lập kịch bản cho lãi suất tăng/giảm | Risk Analysis |
| **Tornado Diagram** | Biểu đồ thể hiện độ nhạy cảm của rủi ro, yếu tố nào ảnh hưởng nhiều nhất | Xác định các nhân tố rủi ro quan trọng nhất | Thanh dài nhất = hạng mục chi phí nhân công | Monte Carlo, Sensitivity Analysis |

---

## 🌍 Ví dụ thực tế & Case Study

### Case Study 1: Dự án cổng thông tin ngành giáo dục Việt Nam

**Bối cảnh:** Bộ Giáo dục và Đào tạo Việt Nam triển khai hệ thống quản lý thi tốt nghiệp THPT trực tuyến.

**Vấn đề:** Nhóm dự án không lập risk table chính thức. Trước kỳ thi, máy chủ bị quá tải do lượng truy cập đột biến — một rủi ro có thể dự đoán được (predictable risk: "Server may not be able to handle larger number of users simultaneously", xác suất 30%, tác động Catastrophic).

**Giải pháp:** Sau sự cố, nhóm lập RMMM với chiến lược kỹ thuật: load balancing, auto-scaling trên nền tảng đám mây, thử nghiệm tải trước kỳ thi 2 tuần.

**Kết quả:** Năm tiếp theo, hệ thống xử lý 500,000 đăng nhập đồng thời mà không gián đoạn.

**Bài học:** Rủi ro "đông người dùng hơn dự kiến" phải nằm trong risk table ngay từ giai đoạn planning — tác động thấp lúc đầu, catastrophic khi phát sinh muộn.

---

### Case Study 2: Công ty fintech Việt Nam áp dụng FAIR

**Bối cảnh:** Startup fintech tại TP.HCM cần đánh giá rủi ro bảo mật dữ liệu khách hàng trước khi ra mắt ứng dụng vay tiêu dùng.

**Vấn đề:** Nhóm kỹ thuật muốn đầu tư ngay vào mã hóa end-to-end tốn 500 triệu VND nhưng ban lãnh đạo chưa thấy rõ lợi ích tài chính.

**Giải pháp:** Áp dụng FAIR: ALE trước bảo mật = 2 tỷ VND/năm (ước tính tổn thất nếu rò rỉ dữ liệu). ALE sau = 200 triệu VND/năm. Lợi ích = 2B − 200M − 500M = 1.3 tỷ VND/năm — thuyết phục ban lãnh đạo đầu tư.

**Kết quả:** Hệ thống được triển khai bảo mật, công ty được cấp phép hoạt động, không có sự cố rò rỉ trong 2 năm đầu.

**Bài học:** FAIR chuyển đổi rủi ro kỹ thuật thành ngôn ngữ tài chính, giúp ban lãnh đạo ra quyết định đầu tư bảo mật dựa trên dữ liệu.

---

### Case Study 3: Ngân hàng thương mại dùng Scenario Planning

**Bối cảnh:** Một ngân hàng tại Đông Nam Á chuẩn bị triển khai hệ thống core banking mới (dự án $15 triệu, 18 tháng).

**Vấn đề:** Nhiều rủi ro chưa lường trước: nhà cung cấp phần mềm thay đổi nhóm triển khai giữa chừng, quy định ngân hàng trung ương thay đổi yêu cầu báo cáo.

**Giải pháp:** Nhóm dự án áp dụng Scenario Planning theo khung McKinsey: xây dựng 3 kịch bản (thuận lợi / bình thường / xấu nhất), mỗi kịch bản có contingency plan riêng. Rủi ro nhà cung cấp thay đổi nhóm → kịch bản "xấu nhất" đã có sẵn phương án dự phòng.

**Kết quả:** Khi nhà cung cấp thực sự thay thế team triển khai, dự án trễ 2 tháng thay vì 6 tháng như trường hợp không có kế hoạch.

**Bài học:** Scenario planning phải được thực hiện bởi quản lý cấp cao, không delegated cho nhân viên cấp dưới — đây là một trong những "What to Avoid" của McKinsey.

---

## 📊 Sơ đồ & Bảng tổng hợp

### Bảng 1: Tóm tắt công thức phân tích rủi ro

| Chỉ số | Công thức | Ý nghĩa | Ví dụ |
|---|---|---|---|
| EF (Exposure Factor) | % tài sản bị mất | Mức độ thiệt hại khi rủi ro xảy ra | 40% dữ liệu bị mất |
| SLE | Giá trị tài sản × EF | Tổn thất từ một sự kiện | 1B × 40% = 400M VND |
| ARO | Tần suất/năm | Số lần rủi ro xảy ra trong năm | 2 lần/năm |
| ALE | SLE × ARO | Tổn thất kỳ vọng hàng năm | 400M × 2 = 800M VND |
| Giá trị biện pháp bảo vệ | ALE trước − ALE sau − Chi phí biện pháp | ROI của đầu tư bảo mật | 800M − 80M − 200M = 520M VND |

### Bảng 2: So sánh phương pháp phân tích định lượng

| Phương pháp | Ưu điểm | Nhược điểm | Khi nào dùng |
|---|---|---|---|
| Traditional (empirical) | Đơn giản, dựa trên lịch sử | Không hỗ trợ schedule risk, ít giao tiếp rủi ro | Ước tính nhanh chi phí |
| Analytical (second-moment) | Cần ít dữ liệu đầu vào | Khó áp dụng cho schedule, không trực quan | Mô hình đơn giản |
| Monte Carlo | Linh hoạt, chi tiết, phổ biến nhất | Cần kiến thức thống kê, cần phân phối xác suất đầy đủ | Dự án phức tạp |
| Probability/Decision Trees | Mô hình hóa xác suất có điều kiện | Phức tạp, cần nhiều dữ liệu | Dự án khó, rủi ro liên kết |

### Sơ đồ vòng lặp Risk Management

```
Xác định rủi ro → Phân tích (EF/SLE/ALE) → Lập risk table
        ↓
Xây dựng RMMM → Thực thi chiến lược → Giám sát liên tục
        ↓
Đo lường metrics → Phản hồi → Xác định rủi ro mới (vòng lặp)
```

---

## ❓ Câu hỏi ôn tập

**Câu 1 (Nhớ lại):** ALE là gì và công thức tính như thế nào?

💡 *Gợi ý: ALE liên quan đến SLE và ARO.*

📝 *Đáp án:* ALE (Annualized Loss Expectancy — Tổn thất kỳ vọng hàng năm) là thước đo tổng thiệt hại dự kiến trong một năm từ một rủi ro cụ thể. Công thức: ALE = SLE × ARO, trong đó SLE = Giá trị tài sản × EF (Exposure Factor), và ARO là số lần rủi ro xảy ra trong năm. Ví dụ, nếu một hệ thống trị giá 1 tỷ VND có EF = 30% và ARO = 2, thì SLE = 300 triệu, ALE = 600 triệu VND/năm. Chỉ số này là cơ sở để tính toán xem đầu tư vào biện pháp bảo vệ có đáng hay không bằng cách so sánh chi phí biện pháp với ALE tiết kiệm được.

---

**Câu 2 (Nhớ lại):** Ba loại rủi ro phần mềm chính theo chương là gì? Cho ví dụ cho mỗi loại.

💡 *Gợi ý: Project / Technical / Business.*

📝 *Đáp án:* Ba loại rủi ro phần mềm chính là: (1) **Rủi ro dự án** (project risks) — các vấn đề về ngân sách, lịch trình, nhân sự, ví dụ: mất nhân viên chủ chốt giữa dự án; (2) **Rủi ro kỹ thuật** (technical risks) — các vấn đề về thiết kế, công nghệ, giao diện, ví dụ: xây dựng hệ thống dựa trên công nghệ chưa được kiểm chứng; (3) **Rủi ro kinh doanh** (business risks) — các vấn đề về thị trường, chiến lược, quản lý, ví dụ: xây dựng sản phẩm mà không ai muốn mua (market risk) hoặc mất sự ủng hộ của ban lãnh đạo cấp cao (management risk). Hiểu đúng loại rủi ro giúp đưa ra chiến lược RMMM phù hợp.

---

**Câu 3 (Thông hiểu):** Tại sao rủi ro ở giai đoạn đầu dự án có xác suất cao hơn nhưng tác động thấp hơn so với giai đoạn cuối?

💡 *Gợi ý: Nghĩ về tính linh hoạt và nguồn lực đã đầu tư.*

📝 *Đáp án:* Ở giai đoạn đầu dự án, nhiều yếu tố chưa được xác định rõ (yêu cầu chưa hoàn chỉnh, nhóm chưa quen nhau) nên xác suất xảy ra vấn đề cao hơn. Tuy nhiên tác động nhẹ hơn vì: (1) còn nhiều linh hoạt để thay đổi hướng tiếp cận; (2) nguồn lực đầu tư còn ít, nên thiệt hại nếu dừng lại không quá lớn. Ngược lại, ở giai đoạn cuối, hầu hết vấn đề đã được giải quyết (xác suất thấp hơn) nhưng nếu phát sinh vấn đề thì: (1) rất khó thay đổi vì hệ thống đã gần hoàn chỉnh; (2) đã đầu tư rất nhiều nguồn lực, sửa chữa tốn kém. Đây là lý do tại sao risk identification phải bắt đầu sớm nhất có thể.

---

**Câu 4 (Thông hiểu):** So sánh OCTAVE và FAIR. Khi nào nên dùng từng framework?

💡 *Gợi ý: OCTAVE = con người + quy trình, FAIR = tài chính + toán học.*

📝 *Đáp án:* **OCTAVE** (Carnegie Mellon) tập trung vào đánh giá toàn diện từ góc nhìn con người, kỹ thuật và vật lý; được thực hiện bởi các nhóm nhỏ liên phòng ban, tăng sự cộng tác và nhận thức rủi ro trong tổ chức. Phù hợp khi cần đánh giá rủi ro tổng thể của tổ chức, đặc biệt khi lần đầu triển khai chương trình quản lý rủi ro. **FAIR** tập trung vào định lượng tài chính: dùng ước tính bằng đô la và xác suất để xây dựng mô hình toán học cho rủi ro thông tin. Phù hợp khi cần thuyết phục ban lãnh đạo đầu tư vào bảo mật bằng ROI cụ thể, hoặc khi cần so sánh chi phí-lợi ích của các biện pháp bảo vệ khác nhau. Lý tưởng nhất là dùng OCTAVE để nhận diện rủi ro toàn diện, sau đó dùng FAIR để định lượng các rủi ro quan trọng nhất.

---

**Câu 5 (Ứng dụng):** Bạn là PM của một dự án xây dựng hệ thống quản lý kho cho doanh nghiệp logistics. Liệt kê 3 rủi ro, xếp loại (BU/CU/PS/ST/TE), ước tính xác suất và tác động, và đề xuất chiến lược RMMM cho rủi ro có mức độ ưu tiên cao nhất.

💡 *Gợi ý: Dùng bảng risk table với category abbreviations trong chương.*

📝 *Đáp án:* Ba rủi ro điển hình: (1) Nhân viên kho kháng cự hệ thống mới (CU, 60%, Critical) — phải ưu tiên cao nhất; (2) Tích hợp với hệ thống ERP hiện tại gặp sự cố do API không tương thích (TE, 40%, Critical); (3) Ngân sách bị cắt giảm do tái cơ cấu công ty (BU, 20%, Marginal). RMMM cho rủi ro (1) — CU, 60%, Critical: **Giảm thiểu:** tổ chức demo sớm với người dùng cuối, lập nhóm champion từ nhân viên kho để dẫn dắt thay đổi, xây dựng module training tương tác; **Giám sát:** khảo sát hàng tháng mức độ chấp nhận, theo dõi tỷ lệ dùng hệ thống thực tế; **Quản lý:** nếu tỷ lệ sử dụng dưới 50% sau 1 tháng go-live, kích hoạt contingency plan: đào tạo bổ sung và điều chỉnh UI theo phản hồi.

---

## 💡 Ghi nhớ nhanh

- ✅ **Luôn chủ động:** Xác định rủi ro sớm — xác suất cao nhưng tác động thấp ở giai đoạn đầu dự án
- ✅ **ALE là ngôn ngữ chung:** Dùng ALE = SLE × ARO để thuyết phục ban lãnh đạo đầu tư vào bảo mật
- ✅ **Risk table là điểm khởi đầu:** Liệt kê, phân loại, sắp xếp theo xác suất × tác động, vẽ cutoff line
- ⚠️ **Scenario planning không phải cho cấp dưới:** Delegating cho junior staff là một trong những "what to avoid"
- ⚠️ **Monte Carlo cần kiến thức thống kê:** Không áp dụng nếu không hiểu phân phối xác suất đầu vào
- ⚠️ **Unpredictable risks tồn tại:** Không thể loại bỏ hoàn toàn — cần ngân sách dự phòng tổng quát
- 🔗 **Chương 8 tiếp theo:** Từ quản lý rủi ro chuyển sang kiểm soát và cải thiện quy trình — RMMM là nền tảng để process improvement có thể thực hiện một cách an toàn

---

## 📖 Giải thích thuật ngữ chuyên ngành

**Risk Probability (Xác suất rủi ro)**
Khả năng một sự kiện rủi ro xảy ra, thường đo từ 1 (rất thấp) đến 5 (rất cao). Như dự báo thời tiết: "70% khả năng mưa" là xác suất rủi ro bị ướt. Quan trọng vì là một trong hai chiều của risk table, giúp ưu tiên hóa nguồn lực.

**EF — Exposure Factor (Hệ số phơi lộ)**
Phần trăm giá trị tài sản bị mất khi rủi ro xảy ra. Như bảo hiểm cháy: nếu nhà cháy toàn bộ thì EF = 100%, cháy một nửa thì EF = 50%. Nền tảng để tính SLE và ALE.

**SLE — Single Loss Expectancy (Tổn thất từ một sự kiện)**
Giá trị tài sản nhân với EF — tức thiệt hại dự kiến từ một lần sự kiện rủi ro xảy ra. Như tính thiệt hại một lần máy chủ bị tấn công. Bước đầu của chuỗi tính ALE.

**ARO — Annualized Rate of Occurrence (Tần suất hàng năm)**
Số lần dự kiến một sự kiện rủi ro xảy ra trong một năm. Tần suất 0.5 nghĩa là mỗi 2 năm một lần. Giúp chuyển thiệt hại một lần thành góc nhìn hàng năm.

**ALE — Annualized Loss Expectancy (Tổn thất kỳ vọng hàng năm)**
SLE × ARO — thiệt hại trung bình hàng năm từ một rủi ro. Như phí bảo hiểm tối thiểu cần đầu tư để hòa vốn. Cơ sở để quyết định có nên đầu tư vào biện pháp bảo vệ hay không.

**RMMM — Risk Mitigation, Monitoring, Management**
Kế hoạch ba chiều: giảm thiểu nguyên nhân rủi ro, giám sát dấu hiệu cảnh báo, và quản lý/ứng phó khi rủi ro xảy ra. Như kế hoạch phòng cháy chữa cháy: phòng ngừa + cảnh báo sớm + xử lý khi cháy. Tài liệu hóa hành động cụ thể cho từng rủi ro.

**Monte Carlo Simulation (Mô phỏng Monte Carlo)**
Phương pháp tính toán dùng số ngẫu nhiên để lấy mẫu từ các phân phối xác suất nhằm đánh giá tác động tổng hợp của nhiều bất định. Như chạy 10,000 kịch bản dự án ngẫu nhiên để biết phân phối chi phí có thể xảy ra. Phổ biến nhất vì linh hoạt và cung cấp thông tin chi tiết.

**Tornado Diagram (Biểu đồ lốc xoáy)**
Biểu đồ thanh nằm ngang sắp xếp từ thanh dài nhất đến ngắn nhất, thể hiện yếu tố nào ảnh hưởng nhiều nhất đến rủi ro tổng thể. Trông như cơn lốc xoáy nhìn từ trên xuống. Giúp xác định "risk drivers" — những biến số cần quản lý chặt nhất.

**OCTAVE (Operationally Critical Threat, Asset, and Vulnerability Evaluation)**
Framework đánh giá rủi ro IT phát triển tại Carnegie Mellon, xem xét tài sản là con người, phần cứng, phần mềm, thông tin, và hệ thống; do các nhóm nhỏ liên phòng ban thực hiện. Như kiểm tra sức khỏe toàn diện cho tổ chức, không chỉ kiểm tra một bộ phận. Tạo ra đánh giá có tài liệu đầy đủ từ nhiều góc nhìn.

**FAIR (Factor Analysis of Information Risk)**
Framework định lượng rủi ro thông tin bằng đô la và xác suất, gồm 4 giai đoạn: xác định kịch bản → tần suất mất mát → mức độ mất mát → diễn đạt rủi ro. Như báo cáo tài chính cho rủi ro bảo mật. Giúp ban lãnh đạo hiểu rủi ro bằng ngôn ngữ kinh doanh.

**PQM — Process Quality Management**
Phương pháp do IBM phát triển kết hợp Critical Success Factors với brainstorming nhóm để xác định và ưu tiên hóa các quy trình kinh doanh cần cải thiện nhằm giảm rủi ro. Như workshop chiến lược có cấu trúc cho dự án phức tạp. Đặc biệt hữu ích khi cần đồng thuận nhóm về ưu tiên.


---

!!! info "Nguồn gốc"
    `pdf_md/managing-it-performance-to-create-business-value/guide_ai/10_chapter-7-designing-performance-based-risk-management-systems_guide.md`
