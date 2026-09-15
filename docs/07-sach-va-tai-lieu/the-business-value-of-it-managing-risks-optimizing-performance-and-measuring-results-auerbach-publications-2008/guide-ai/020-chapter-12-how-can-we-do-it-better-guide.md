---
title: Chương 12 — Làm Thế Nào Để Làm Tốt Hơn IT?
course: 07-sach-va-tai-lieu
source: pdf_md/the-business-value-of-it-managing-risks-optimizing-performance-and-measuring-results-auerbach-publications-2008/guide_ai/20_chapter-12-how-can-we-do-it-better_guide.md
---

# Chương 12 — Làm Thế Nào Để Làm Tốt Hơn IT?

**Sách:** The Business Value of IT — Managing Risks, Optimizing Performance, and Measuring Results (Auerbach Publications, 2008)
**Ngày tạo:** 2026-04-26
**Thời gian học ước tính:** 35–45 phút

---

## 🎯 Mục tiêu học tập

- Hiểu được tại sao các best practices trong phát triển phần mềm không được áp dụng nhất quán
- Phân biệt giữa high-performing projects và low-performing projects dựa trên dữ liệu thực tế
- Mô tả cách sử dụng benchmarking và baseline để xác định cơ hội cải thiện
- Áp dụng kỹ thuật performance modeling để dự báo tác động của các sáng kiến cải tiến
- Đánh giá mối liên hệ giữa TCO (Total Cost of Ownership) và việc tuân thủ best practices

---

## 📋 Tóm tắt nội dung chính

Chapter 12 trả lời câu hỏi: "Làm thế nào để IT thực sự làm tốt hơn?" bằng cách kết hợp phân tích bối cảnh ngành, ba case study thực tế, và kỹ thuật performance modeling.

**Bối cảnh ngành IT và các best practices**

Ngành phát triển phần mềm đã có nhiều best practices được công nhận — formal design reviews, code inspections, requirements-gathering methods (JAD sessions), project management, agile development. Tuy nhiên, nghịch lý là dù các best practices này được biết đến rộng rãi, chúng vẫn không được áp dụng nhất quán.

Lý do chủ yếu đến từ áp lực ngắn hạn: schedule pressure, budget constraint, và thiếu trách nhiệm giải trình (accountability). Business thường đẩy IT Provider phải "ship nhanh, tốn ít" mà không tính đến chi phí dài hạn. Best practices tuy làm project ban đầu có vẻ tốn kém hơn và kéo dài hơn, nhưng lại giảm Total Cost of Ownership (TCO) — ít change requests, dễ bảo trì, ít lỗi hơn.

Ngoài ra, outsourcing offshore đã tạo áp lực cạnh tranh mới: các nhà cung cấp offshore đạt CMMI Level 5 có thể cung cấp chất lượng cao hơn với chi phí thấp hơn, khiến nhiều công ty đặt câu hỏi liệu có đáng đầu tư vào cải tiến nội bộ không.

**Ba Case Study thực tế**

*Case Study 1 — Tổ chức tài chính lớn:* Phân tích 65 projects đã hoàn thành, chia thành high-performers và low-performers. High-performing projects có: full agreement on deliverables (100%), experienced staff (100%), no staff turnover (100%), formal requirements gathering (100%). Kết quả định lượng: high-performers tạo ra nhiều functionality hơn (148 FP so với 113 FP), trong thời gian ngắn hơn (5 tháng so với 7 tháng), năng suất cao hơn hẳn (22 FP/PM so với 9 FP/PM).

*Case Study 2 — Công ty bảo hiểm cỡ trung:* So sánh với industry benchmark. Productivity của client (6.9 FP/PM) gần với mức trung bình ngành (7.3) nhưng còn kém xa best practices (22.7). Defect density cao gấp đôi mức trung bình (0.24 so với 0.12). Phát hiện: công ty đang trade-off quality lấy speed bằng cách thêm nhân lực thay vì cải tiến process.

*Case Study 3 — Tổ chức dịch vụ lớn:* Mô phỏng tác động khi đạt CMMI Level 3. Kết quả dự báo ấn tượng: năng suất tăng 132%, time to market giảm 50%, chi phí giảm 40%, defect density giảm 75%.

**Performance Modeling**

Kỹ thuật performance modeling cho phép IT tổ chức dự báo tác động của các sáng kiến cải tiến TRƯỚC khi đầu tư. Mô hình kết hợp dữ liệu định lượng (size, effort, duration, quality) và định tính (process attributes, capability profiles) để tạo ra baseline và simulate scenarios.

---

## 🔑 Khái niệm quan trọng

| Khái niệm | Định nghĩa | Tại sao quan trọng | Ví dụ | Liên quan đến |
|---|---|---|---|---|
| Best Practice | Phương pháp được cộng đồng thừa nhận là hiệu quả nhất dựa trên kinh nghiệm thực tế | Giúp chuẩn hóa quy trình và giảm rủi ro | Formal code inspection, JAD sessions, agile | CMMI, SDLC |
| Total Cost of Ownership (TCO) | Tổng chi phí sở hữu và vận hành một hệ thống IT trong toàn bộ vòng đời | Best practices tốn hơn ban đầu nhưng giảm TCO về lâu dài | Project theo best practice: ít defect, ít change request → bảo trì rẻ hơn | ROI, value measurement |
| Baseline Performance | Mức hiệu suất hiện tại được đo đạc và ghi nhận làm điểm tham chiếu | Không thể cải thiện điều bạn không đo lường được | FP/PM, defect density tại thời điểm T | Benchmarking, performance modeling |
| Function Point (FP) | Đơn vị đo lường kích thước phần mềm dựa trên chức năng cung cấp cho người dùng | Cho phép so sánh năng suất giữa các project khác nhau | Project 148 FP vs 113 FP | Productivity measurement |
| Performance Modeling | Kỹ thuật mô phỏng tác động của các cải tiến process dựa trên dữ liệu lịch sử | Giúp quyết định đầu tư cải tiến trước khi thực hiện | CMMI Level 3 → dự báo tăng 132% productivity | CMMI, decision-making |
| Capability Profile | Tập hợp các thuộc tính mô tả cách một tổ chức thực hiện công việc | Giải thích tại sao performance cao hoặc thấp | No staff turnover, experienced PM, formal reviews | Qualitative assessment |
| Benchmarking | So sánh hiệu suất của tổ chức với dữ liệu ngành | Xác định khoảng cách giữa vị trí hiện tại và best practices | Client: 6.9 FP/PM vs Industry Best: 22.7 FP/PM | Industry data, continuous improvement |
| Defect Density | Số lỗi trên một function point của phần mềm đã giao | Thước đo chất lượng phần mềm | Client: 0.24 defects/FP vs Best Practice: 0.02 | Quality metrics |

---

## 🌍 Ví dụ thực tế & Case Study

### Case Study 1: Tổ chức tài chính lớn — Tìm đặc điểm của high-performing projects

**Bối cảnh:** Một tổ chức tài chính lớn muốn hiểu tại sao một số project thành công vượt trội so với các project khác.

**Vấn đề:** Không có cơ chế xác định những yếu tố nào thực sự tạo ra sự khác biệt giữa project tốt và xấu.

**Giải pháp:** Phân tích 65 projects đã hoàn thành, tính toán productivity (FP/PM), duration, và cost. Sau đó phân tích các thuộc tính định tính của từng nhóm.

**Kết quả:** High-performers đạt 22 FP/PM (so với 9 FP/PM của low-performers), hoàn thành trong 5 tháng thay vì 7 tháng, với 100% có full agreement on deliverables và experienced staff.

**Bài học:** Các yếu tố "mềm" như team stability, experienced PM, clear requirements có tác động định lượng rõ ràng đến năng suất.

---

### Case Study 2: Công ty bảo hiểm — Benchmarking với ngành

**Bối cảnh:** Một công ty bảo hiểm cỡ trung muốn biết mình đang đứng ở đâu so với ngành.

**Vấn đề:** Công ty nghĩ mình đang hoạt động ổn vì deliver đúng tiến độ, nhưng không biết defect rate cao bất thường.

**Giải pháp:** So sánh productivity, duration, defect density với industry benchmark từ database 7,000+ projects của David Consulting Group.

**Kết quả:** Productivity gần mức trung bình ngành nhưng defect density cao gấp đôi (0.24 vs 0.12). Phát hiện ra pattern: tăng nhân lực để deliver nhanh thay vì cải thiện quy trình.

**Bài học:** 🇻🇳 Nhiều doanh nghiệp Việt Nam cũng có xu hướng tương tự — thêm người thay vì cải tiến process. Benchmarking với dữ liệu ngành giúp nhìn thấy điểm mù này.

---

### Case Study 3: Dự báo ROI của CMMI Level 3

**Bối cảnh:** Một tổ chức dịch vụ lớn đang cân nhắc đầu tư vào CMMI Level 3 nhưng chưa biết liệu có đáng không.

**Vấn đề:** Đầu tư vào CMMI tốn kém và mất nhiều năm. Cần bằng chứng định lượng trước khi quyết định.

**Giải pháp:** Performance modeling — xây dựng baseline hiện tại, sau đó simulate kết quả với CMMI Level 3 attributes dựa trên dữ liệu ngành.

**Kết quả:** Dự báo: +132% productivity, -50% time to market, -40% cost, -75% defect density.

**Bài học:** Performance modeling cho phép "thử nghiệm" sáng kiến cải tiến trên giấy trước khi đầu tư thực, giống như simulation trong kỹ thuật cơ khí.

---

## 📊 Sơ đồ & Bảng tổng hợp

### Bảng so sánh: High-Performing vs Low-Performing Projects (Case Study 1)

| Thuộc tính | High Performers | Low Performers |
|---|---|---|
| Avg size (FP) | 148 | 113 |
| Avg duration | 5 tháng | 7 tháng |
| Productivity (FP/PM) | 22 | 9 |
| Full agreement on deliverables | 100% | 33% |
| Experienced dev staff | 100% | 33% |
| No staff turnover | 100% | 50% |
| Experienced PM | 100% | 50% |

### Bảng so sánh: Client vs Industry (Case Study 2)

| Thước đo | Client | Industry Average | Industry Best Practice |
|---|---|---|---|
| Productivity (FP/PM) | 6.9 | 7.3 | 22.7 |
| Duration (months) | 12 | 14 | 10 |
| Defects/FP | 0.24 | 0.12 | 0.02 |

### Tác động dự báo của CMMI Level 3 (Case Study 3)

| Thước đo | Baseline | CMMI Level 3 | Thay đổi |
|---|---|---|---|
| Avg FP/EM (năng suất) | 10.7 | 24.8 | +132% |
| Time to market (tháng) | 6.9 | 3.5 | -50% |
| Cost/FP | $934.58 | $567.29 | -40% |
| Defect density | 0.0301 | 0.0075 | -75% |

---

## ❓ Câu hỏi ôn tập

**1. Tại sao các IT Providers biết về best practices nhưng vẫn không áp dụng nhất quán?**

💡 Gợi ý: Nghĩ đến áp lực ngắn hạn và mối quan hệ giữa IT Provider và business.

📝 Đáp án: Có nhiều lý do chính: áp lực về schedule và budget khiến teams bỏ qua các bước "tốn thời gian" của best practices. Business không yêu cầu accountability đối với việc tuân thủ best practices, mà chỉ đo kết quả cuối (ship nhanh, rẻ). Hơn nữa, lợi ích của best practices thường là dài hạn (giảm TCO, ít defect) trong khi chi phí là ngay lập tức (thêm thời gian, thêm resource). Trong một môi trường mà "nhanh và rẻ" được khen thưởng, việc đầu tư vào chất lượng dài hạn rất khó biện minh với quản lý.

---

**2. Function Point là gì và tại sao nó hữu ích cho benchmarking?**

💡 Gợi ý: Nghĩ về cách đo "kích thước" của phần mềm một cách khách quan.

📝 Đáp án: Function Point (FP) là đơn vị đo lường kích thước phần mềm dựa trên chức năng mà phần mềm cung cấp cho người dùng, không phụ thuộc vào ngôn ngữ lập trình hay nền tảng. Điều này làm cho FP trở thành một thước đo chuẩn hóa, cho phép so sánh năng suất (FP/PM — function points per person-month) giữa các project, team, hay thậm chí các công ty khác nhau. Trong benchmarking, FP cho phép một tổ chức so sánh productivity của mình với industry database có hàng nghìn projects, xác định khoảng cách với mức trung bình và best practices.

---

**3. Phân biệt dữ liệu định lượng và định tính trong baseline study. Tại sao cần cả hai?**

💡 Gợi ý: Xem Case Study 1 và 2 để thấy hai loại dữ liệu được dùng như thế nào.

📝 Đáp án: Dữ liệu định lượng (quantitative) bao gồm các con số đo được như size (FP), productivity (FP/PM), duration, cost, defect density — chúng cho biết "kết quả là gì." Dữ liệu định tính (qualitative) là các thuộc tính mô tả về project như "có formal requirements gathering không?", "PM có kinh nghiệm không?", "team có ổn định không?" — chúng cho biết "tại sao kết quả như vậy." Cần cả hai vì dữ liệu định lượng đơn độc chỉ cho thấy vấn đề tồn tại, trong khi dữ liệu định tính giải thích nguyên nhân và chỉ ra hướng cải thiện.

---

**4. Performance modeling khác gì so với benchmarking thông thường?**

💡 Gợi ý: Một cái nhìn về hiện tại, một cái nhìn về tương lai.

📝 Đáp án: Benchmarking so sánh hiệu suất hiện tại của tổ chức với dữ liệu ngành — đây là nhìn về "mình đang đứng ở đâu so với người khác." Performance modeling đi xa hơn: nó sử dụng dữ liệu baseline và capability profile hiện tại để dự báo (simulate) tác động của các cải tiến process TRƯỚC khi thực hiện. Ví dụ trong Case Study 3, tổ chức không chỉ biết "mình đang thấp hơn CMMI Level 3" mà còn dự báo được "nếu đạt Level 3, productivity sẽ tăng 132%, cost giảm 40%." Điều này giúp justification cho các khoản đầu tư lớn.

---

**5. Một công ty IT Việt Nam đang bị áp lực "ship nhanh" và defect rate cao. Dựa trên các case study, họ nên bắt đầu từ đâu?**

💡 Gợi ý: Không thể cải thiện điều không đo được. Bước đầu tiên trong mọi case study là gì?

📝 Đáp án: Bước đầu tiên là thiết lập baseline — đo đạc và ghi nhận hiệu suất hiện tại (productivity, defect density, duration) bằng một đơn vị chuẩn hóa như function points. Tiếp theo, thu thập dữ liệu định tính về các thuộc tính project (team experience, requirements quality, PM experience...). Từ baseline này, so sánh với industry benchmarks để xác định khoảng cách. Sau đó phân tích capability profile để tìm những yếu tố có tác động lớn nhất đến performance. Cuối cùng, dùng performance modeling để ưu tiên các cải tiến có ROI cao nhất — ví dụ từ Case Study 1, việc đảm bảo "full agreement on deliverables" có tác động rất lớn mà không tốn nhiều chi phí.

---

## 💡 Ghi nhớ nhanh

- ✅ Best practices đều được biết đến nhưng ít được áp dụng — nguyên nhân là culture và accountability, không phải thiếu kiến thức
- ✅ High-performing projects có điểm chung: stable team, experienced PM, clear requirements, formal processes
- ✅ Function Points cho phép so sánh productivity một cách khách quan giữa các project và ngành
- ⚠️ Tránh nhầm lẫn "deliver nhanh bằng cách thêm người" với "cải thiện năng suất thật sự" — Case Study 2 cho thấy đây là bẫy phổ biến
- ⚠️ Benchmark với industry cần dữ liệu đủ lớn — David Consulting Group dùng 7,000+ projects
- ✅ Performance modeling = "thử nghiệm trên giấy" trước khi đầu tư thực — rất có giá trị cho ROI justification
- 🔗 Chapter tiếp theo (Chapter 13) sẽ đề cập đến quản lý thay đổi IT — bước tiếp theo sau khi đã xác định được improvements cần thực hiện

---

## 📖 Giải thích thuật ngữ chuyên ngành

**Best Practice** — Thực hành tốt nhất
Phương pháp hoặc kỹ thuật được cộng đồng thừa nhận là hiệu quả nhất dựa trên kinh nghiệm tích lũy. Giống như "công thức nấu ăn đã được kiểm chứng" trong ẩm thực — không bắt buộc phải theo nhưng thường cho kết quả tốt nhất. Quan trọng trong chương này vì sự không nhất quán trong áp dụng best practices là nguyên nhân chính của performance thấp.

**Function Point (FP)** — Điểm chức năng
Đơn vị đo kích thước phần mềm dựa trên số lượng chức năng cung cấp cho người dùng. Tương tự như "mét vuông" trong xây dựng — cho phép so sánh "căn hộ" (project phần mềm) dù xây ở nhiều nơi khác nhau. Cần thiết để tính năng suất (FP/PM) theo chuẩn quốc tế.

**Total Cost of Ownership (TCO)** — Tổng chi phí sở hữu
Tổng chi phí của một hệ thống trong toàn bộ vòng đời, bao gồm chi phí phát triển + bảo trì + vận hành + nâng cấp. Như mua xe: giá mua chỉ là một phần — xăng, bảo dưỡng, sửa chữa mới là TCO thật sự. Best practices làm tăng chi phí phát triển ban đầu nhưng giảm TCO tổng thể.

**Baseline** — Đường cơ sở / Mức nền
Hiệu suất hiện tại được đo đạc và ghi nhận làm điểm tham chiếu cho việc so sánh và cải thiện sau này. Như "số đo ban đầu" trước khi bắt đầu chương trình giảm cân — không có baseline thì không thể đo được tiến bộ.

**Benchmarking** — Đo chuẩn / So sánh chuẩn
Quá trình so sánh hiệu suất của tổ chức với dữ liệu từ các tổ chức khác trong ngành. Như "xếp hạng học sinh trong lớp" — biết điểm tuyệt đối chưa đủ, cần biết mình đứng ở đâu so với mọi người.

**Performance Modeling** — Mô hình hóa hiệu suất
Kỹ thuật sử dụng dữ liệu lịch sử và dữ liệu ngành để dự báo tác động của các thay đổi process trước khi thực hiện. Như "chạy simulation" trong kỹ thuật hàng không trước khi bay thử — giúp dự đoán kết quả mà không tốn chi phí thực.

**Capability Profile** — Hồ sơ năng lực
Tập hợp các thuộc tính định tính mô tả cách tổ chức thực hiện công việc (process, methods, skills, tools, management). Đây là "DNA" của tổ chức giải thích tại sao productivity cao hoặc thấp.

**CMMI (Capability Maturity Model Integration)** — Mô hình tích hợp năng lực trưởng thành
Framework đánh giá mức độ trưởng thành của quy trình phát triển phần mềm từ Level 1 (Initial) đến Level 5 (Optimizing). Như "cấp độ bằng lái" cho tổ chức phần mềm — Level 5 là tổ chức có quy trình chuẩn hóa và liên tục cải tiến.

**JAD Session (Joint Application Design)** — Phiên thiết kế ứng dụng chung
Phương pháp thu thập yêu cầu trong đó developers và users cùng làm việc trong các workshop tập trung. Như "họp thiết kế có cả kiến trúc sư và chủ nhà" — đảm bảo requirements rõ ràng ngay từ đầu.

**Defect Density** — Mật độ lỗi
Số lượng lỗi (defects) trên một đơn vị kích thước phần mềm (thường là FP). Thước đo chất lượng phần mềm — số càng thấp càng tốt. Case Study 2 cho thấy 0.24 defects/FP là cao gấp đôi mức trung bình ngành.


---

!!! info "Nguồn gốc"
    `pdf_md/the-business-value-of-it-managing-risks-optimizing-performance-and-measuring-results-auerbach-publications-2008/guide_ai/20_chapter-12-how-can-we-do-it-better_guide.md`
