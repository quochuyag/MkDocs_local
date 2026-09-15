---
title: 'Hướng Dẫn Học Tập: Thiết Lập Chương Trình Đo Lường Phần Mềm'
course: 07-sach-va-tai-lieu
source: pdf_md/managing-it-performance-to-create-business-value/guide_ai/07_chapter-4-establishing-a-software-measurement-program_guide.md
---

# Hướng Dẫn Học Tập: Thiết Lập Chương Trình Đo Lường Phần Mềm

**Nguồn:** Managing IT Performance to Create Business Value — Chapter 4  
**Ngày tạo:** 2026-04-26  
**Thời gian học ước tính:** 55–65 phút

---

## 🎯 Mục tiêu học tập

Sau khi hoàn thành chương này, người học có thể:

- **Mô tả** 4 bước thiết lập chương trình đo lường phần mềm theo framework toàn diện
- **Phân biệt** đo lường trực tiếp (direct) và gián tiếp (indirect/derived) trong bối cảnh phần mềm
- **Áp dụng** phương pháp Goal-Question-Metric (GQM) để liên kết mục tiêu tổ chức với metrics cụ thể
- **Hiểu** mô hình IDEAL và cách nó tích hợp với SEI CMM để cải thiện quy trình phần mềm liên tục
- **Đánh giá** 5 mức độ trưởng thành của SEI CMM và loại metrics phù hợp với từng mức
- **Thiết kế** cấu trúc cơ bản của một Software Measurement Plan cho dự án thực tế

---

## 📋 Tóm tắt nội dung chính

Chương 4 cung cấp một framework thực tiễn để thiết lập chương trình đo lường phần mềm bền vững — không phải một lần rồi thôi, mà là một hệ thống sống, phát triển cùng mục tiêu tổ chức. Nguyên tắc cốt lõi: **bắt đầu nhỏ, xây dựng dựa trên thành công, và kết hợp đo lường với cải tiến quy trình**.

**4 bước thiết lập:**
1. Adopt a Software Measurement Program Model — xác định resources, processes, products cần đo
2. Use a Software Process Improvement Model (IDEAL) — thiết lập baseline, đặt mục tiêu, thực hiện, và leverage
3. Identify a GQM Structure — liên kết mục tiêu phần mềm với mục tiêu doanh nghiệp qua câu hỏi có thể đo lường
4. Develop a Software Measurement Plan — tài liệu hóa what, why, who, how, when cho tất cả hoạt động đo lường

**Ba đối tượng đo lường** trong phần mềm: **Resources** (nhân lực, vật liệu, công cụ, phương pháp — attribute quan trọng nhất là cost), **Processes** (bất kỳ hoạt động phần mềm nào — attribute chính là time và effort), và **Products** (đặc tả, code, tài liệu test — attribute chính là size và inherent defects).

**Đo lường trực tiếp** không phụ thuộc attribute khác (ví dụ: SLOC, staff hours). **Đo lường gián tiếp/derived** tính từ 2+ attributes (ví dụ: failure rate = số lỗi / execution time; productivity = output / effort).

**Ba góc nhìn đo lường:** Strategic View (long-term: time to market, cost, trade-off quality factors — quan trọng nhất với senior management), Tactical View (short + long term project: schedule progress, labor cost), và Application View (immediate: product size, complexity, defects — quan trọng với engineers).

**GQM Paradigm** hoạt động top-down: Xác định Goals (what/who/why/when) → Refine thành Questions (quantifiable) → Refine thành Metrics (data collection attributes). Điểm mạnh: đảm bảo mỗi metric đều gắn trực tiếp với mục tiêu có giá trị — không đo lường vô nghĩa.

**SEI CMM** có 5 mức: Level 1 (Initial/Ad hoc — baseline effort/schedule), Level 2 (Repeatable — track effort và schedule theo dự án), Level 3 (Defined — so sánh products/processes across projects), Level 4 (Managed — statistical process control với control boundaries), Level 5 (Optimizing — tự động điều chỉnh trong dự án dựa trên feedback real-time).

---

## 🔑 Khái niệm quan trọng

| Khái niệm | Định nghĩa | Tại sao quan trọng | Ví dụ | Liên quan đến |
|---|---|---|---|---|
| **GQM (Goal-Question-Metric)** | Phương pháp top-down: từ mục tiêu → câu hỏi cần trả lời → metrics đo lường | Đảm bảo mọi metric đều có lý do tồn tại gắn với mục tiêu tổ chức — không đo cho có | Goal: "Cải thiện độ tin cậy phần mềm" → Question: "Tỷ lệ lỗi sau release là bao nhiêu?" → Metric: "Số defect / KLOC trong 3 tháng đầu" | SEI CMM, Measurement Plan |
| **IDEAL Model** | Mô hình cải tiến quy trình 5 giai đoạn: Initiate, Diagnose, Establish, Act, Leverage | Cung cấp framework liên tục để đo lường không bị "một lần rồi thôi" — kết quả được leverage sang dự án tiếp theo | Initiate: xác định mục tiêu cải tiến. Diagnose: assessment bằng CMM. Act: thu thập metrics. Leverage: chia sẻ bài học học được | SEI CMM, GQM |
| **SEI CMM** | Mô hình trưởng thành năng lực phần mềm của Software Engineering Institute — 5 mức từ ad hoc đến optimizing | Giúp tổ chức biết đang ở đâu và cần đo lường gì ở mức tiếp theo — không skip level | Level 2: track effort + schedule. Level 4: statistical control với upper/lower bounds cho tất cả core measures | IDEAL, Measurement Plan |
| **Direct vs. Indirect Measurement** | Direct: đếm trực tiếp, không phụ thuộc attribute khác (SLOC, staff hours). Indirect/Derived: tính từ 2+ attributes (failure rate = failures/execution time) | Indirect measures thường mang nhiều ý nghĩa hơn nhưng cần 2 direct measures chính xác làm đầu vào | Direct: số dòng code. Indirect: productivity = KLOC / person-month | Resources, Products, Processes |
| **Software Measurement Plan** | Tài liệu định nghĩa: what data cần thu thập, how data sẽ được phân tích, who chịu trách nhiệm, when thực hiện | Không có plan, thu thập dữ liệu sẽ hỗn loạn và không nhất quán — "haphazard collection" làm dữ liệu vô nghĩa | Plan gồm: objectives, users and why, measures to collect, collection method, analysis method, project organization | GQM, IDEAL |
| **Strategic/Tactical/Application Views** | 3 góc nhìn core measures: Strategic (long-term, time to market), Tactical (schedule + labor cost per project), Application (size, complexity, defects cho engineers) | Mỗi cấp tổ chức cần loại metrics khác nhau — nhưng tất cả phải nhất quán và có thể tổng hợp lên cấp trên | Agile: Strategic = value/cost/risk; Tactical = schedule progress; Application = lead time, engineering time, time to deploy | Measurement Plan, GQM |

---

## 🌍 Ví dụ thực tế & Case Study

### Case Study 1: Áp dụng GQM cho dự án phần mềm ngân hàng

**Bối cảnh:** Một ngân hàng muốn cải thiện độ tin cậy của hệ thống core banking — thường xuyên xảy ra downtime trong giờ cao điểm giao dịch.

**Vấn đề:** Nhóm IT thu thập nhiều loại dữ liệu nhưng không biết nên đo gì để chứng minh cải tiến với ban giám đốc.

**Giải pháp (GQM):**
- **Goal:** Cải thiện độ tin cậy hệ thống core banking để giảm thiệt hại tài chính và mất lòng tin khách hàng
- **Questions:** (1) Tần suất hệ thống downtime là bao nhiêu? (2) Thời gian trung bình để phục hồi (MTTR) là bao lâu? (3) Phần trăm giao dịch thất bại do lỗi hệ thống là bao nhiêu?
- **Metrics:** (1) Số sự cố downtime / tháng, (2) MTTR tính bằng phút, (3) % giao dịch thất bại / tổng giao dịch mỗi ngày

**Kết quả:** Mỗi metric gắn trực tiếp với câu hỏi có ý nghĩa kinh doanh — ban giám đốc hiểu và phê duyệt ngân sách cải tiến.

**Bài học:** GQM biến "chúng tôi muốn đo phần mềm" thành "chúng tôi đang đo cụ thể X để trả lời câu hỏi Y gắn với mục tiêu Z của tổ chức."

---

### Case Study 2: SEI CMM trong thực tiễn — Hành trình từ Level 1 lên Level 3

**Bối cảnh:** Một công ty phần mềm Việt Nam (~200 nhân viên) nhận dự án outsourcing từ Nhật Bản. Client yêu cầu chứng minh CMM Level 3 hoặc tương đương.

**Vấn đề:** Công ty đang ở Level 1 (ad hoc) — không có quy trình nhất quán, không có measurement data, success phụ thuộc vào effort cá nhân.

**Giải pháp theo framework:**
- **Diagnose (IDEAL):** Thực hiện CMM assessment — xác nhận Level 1, xác định key process areas cần cải thiện
- **Level 2 trước:** Bắt đầu track effort và schedule progress mỗi dự án — thu thập baseline data
- **Level 3:** Chuẩn hóa quy trình đo lường size (Function Points hoặc Story Points), defect density across projects
- **Action teams:** Nhóm nhỏ phụ trách từng key process area

**Kết quả:** Sau 18 tháng, công ty đạt Level 2 thực chất (không phải "giấy tờ CMM") — có đủ dữ liệu để ước tính dự án chính xác hơn 40%.

**Bài học 🇻🇳:** Nhiều công ty phần mềm Việt Nam muốn "nhảy" lên Level 3-5 ngay — nhưng framework IDEAL cho thấy cần xây dựng nền tảng measurement từ Level 1-2 trước. Dữ liệu không có thì không thể manage.

---

### Case Study 3: Software Measurement Plan — Dự án Agile và core measures

**Bối cảnh:** Nhóm Agile phát triển ứng dụng di động cho chuỗi bán lẻ. Product Owner muốn đo lường "value" của từng sprint nhưng không biết bắt đầu từ đâu.

**Vấn đề:** Agile metrics khác biệt so với Waterfall — không thể dùng SLOC hay schedule variance truyền thống.

**Giải pháp (điều chỉnh theo Agile direct measures):**
- **Strategic View:** Value — "Tại sao làm dự án này?" (Business value per sprint), Cost — "Có afford được technical debt không?", Risk — "Execution risk có chấp nhận được không?"
- **Tactical View:** Lead time (từ idea đến production), Engineering time (giờ code thực tế / sprint)
- **Application View:** Time to change, Time to deploy, Time to roll back (khi có sự cố)

**Kết quả:** Product Owner và team có ngôn ngữ chung — sprint review không chỉ là "demo features" mà là "đây là value deliver được, đây là metrics của sprint."

**Bài học:** Chương nhấn mạnh: Agile cần điều chỉnh core measures nhưng vẫn giữ nguyên 3 views (Strategic/Tactical/Application) — triết lý không thay đổi, chỉ metrics cụ thể thay đổi.

---

## 📊 Sơ đồ & Bảng tổng hợp

### Bảng 1: SEI CMM — 5 Mức và Metrics Tương Ứng

| Mức | Tên | Đặc điểm | Core Measures |
|---|---|---|---|
| Level 1 | Initial (Ad hoc) | Không có quy trình nhất quán; thành công phụ thuộc cá nhân | Effort, Schedule progress (pilot) |
| Level 2 | Repeatable | Track và control resources theo từng dự án | Effort, Schedule progress (mỗi dự án) |
| Level 3 | Defined | Đo và so sánh products/processes xuyên dự án | Products: Size, Defects. Processes: Effort, Schedule (cross-project) |
| Level 4 | Managed | Statistical process control: upper/lower bounds | Set statistical control boundaries; estimated vs. actual comparisons |
| Level 5 | Optimizing | Tự điều chỉnh real-time dựa trên statistical control | Dynamic adjustment sử dụng kết quả Level 4 |

### Bảng 2: GQM Paradigm — Ví dụ về Độ Tin Cậy Phần Mềm

| Cấp độ | Nội dung |
|---|---|
| **Goal** | Đánh giá độ tin cậy phần mềm X từ góc độ developer để cải thiện quy trình testing |
| **Question 1** | Tỷ lệ lỗi hiện tại của phần mềm X là bao nhiêu? |
| **Metric 1.1** | Số lỗi tìm thấy trong testing / số KLOC |
| **Metric 1.2** | Số lỗi sau release / KLOC trong 3 tháng đầu |
| **Question 2** | Lỗi được tìm thấy ở phase nào trong SDLC? |
| **Metric 2.1** | % lỗi phát hiện trong design review |
| **Metric 2.2** | % lỗi phát hiện trong unit test vs. system test |

### Sơ đồ: Mô hình IDEAL

```
[INITIATE]              [DIAGNOSE]            [ESTABLISH]
Xác định mục tiêu  →   Baseline assessment →  Ưu tiên cải tiến
& success criteria      (CMM assessment)       & action teams

       ↑                                              ↓
[LEVERAGE]                                    [ACT]
Leverage improvements  ←————————   Thực thi action plan
sang tất cả dự án                   + Thu thập measurements
```

---

## ❓ Câu hỏi ôn tập

**Câu 1 (Nhớ lại):** Kể 4 bước thiết lập chương trình đo lường phần mềm và mô tả ngắn gọn mục đích của từng bước.

💡 *Gợi ý: Bắt đầu từ model, sau đó process improvement, rồi GQM, và cuối cùng là plan.*

📝 *Đáp án:* Bốn bước: (1) **Adopt a Software Measurement Program Model** — xác định chính xác software objects cần đo (resources, processes, products), ai là khách hàng của kết quả đo lường, và tại sao kết quả đó quan trọng với họ; (2) **Use a Software Process Improvement Model (IDEAL)** — đặt measurement trong môi trường cải tiến liên tục; nếu không có môi trường này, measures sẽ không được coi là có giá trị và chương trình sẽ không bền vững; (3) **Identify a GQM Structure** — liên kết mục tiêu phần mềm với mục tiêu doanh nghiệp qua câu hỏi có thể đo lường — đảm bảo mỗi metric đều có lý do tồn tại; (4) **Develop a Software Measurement Plan** — tài liệu hóa toàn bộ: data nào cần thu thập, phân tích thế nào, ai chịu trách nhiệm, khi nào thực hiện.

---

**Câu 2 (Nhớ lại):** Phân biệt đo lường trực tiếp và gián tiếp trong phần mềm. Cho 2 ví dụ mỗi loại.

💡 *Gợi ý: Direct = đếm trực tiếp một attribute. Indirect = tính từ 2 attributes.*

📝 *Đáp án:* **Đo lường trực tiếp** không phụ thuộc vào việc đo attribute nào khác. Ví dụ: (1) SLOC (Source Lines of Code) — chỉ cần đếm; (2) Staff hours — số giờ nhân viên làm việc trên một process. Trong Agile, direct measures bao gồm: lead time, engineering time, time to change, time to deploy. **Đo lường gián tiếp (derived)** tính từ 2+ attributes. Ví dụ: (1) Software failure rate = số lỗi quan sát được / execution time của phần mềm; (2) Productivity = lượng sản phẩm tạo ra / effort hoặc thời gian. Derived measures thường mang nhiều ý nghĩa hơn nhưng cần 2 direct measures chính xác làm đầu vào — sai ở một input sẽ làm sai toàn bộ kết quả.

---

**Câu 3 (Hiểu):** Tại sao một chương trình đo lường phần mềm phải được đặt trong "môi trường cải tiến quy trình liên tục" (continuous software process improvement)? Điều gì xảy ra nếu không có?

💡 *Gợi ý: Nghĩ về việc ai sẽ dùng kết quả đo lường và liệu họ có thấy nó "có giá trị" không.*

📝 *Đáp án:* Nếu tổ chức không có văn hóa cải tiến quy trình liên tục, measures sẽ không được coi là "value-added" — chúng trở thành gánh nặng thêm thay vì công cụ hỗ trợ. Nhân viên sẽ thu thập dữ liệu một cách hình thức mà không dùng nó để ra quyết định. Chương trình sẽ không bền vững — thường chỉ tồn tại đủ lâu để đáp ứng yêu cầu kiểm toán hoặc chứng nhận, sau đó bị bỏ. Ngược lại, trong môi trường cải tiến liên tục (như IDEAL model), kết quả đo lường ngay lập tức được dùng để: thiết lập baseline, xác định gaps, ưu tiên action plans, và leverage cải tiến sang dự án tiếp theo — tạo ra vòng phản hồi có giá trị thực sự.

---

**Câu 4 (Hiểu):** So sánh Strategic View, Tactical View, và Application View của core measures. Tại sao chúng phải "nhất quán và có thể tổng hợp lên nhau"?

💡 *Gợi ý: Nếu mỗi cấp dùng metrics khác nhau hoàn toàn, điều gì sẽ xảy ra khi CEO muốn kết nối với kết quả kỹ thuật?*

📝 *Đáp án:* **Strategic View** (senior management): long-term — time to market, product cost, trade-off quality factors. **Tactical View** (project management): short + long term — schedule progress và labor cost cho từng dự án. **Application View** (engineers): immediate — product size, complexity, reliability, defects cụ thể. Lý do phải nhất quán: nếu các views không kết nối, từng dự án sẽ "out of sync" với chiến lược tổ chức. Senior management không thể nhìn thấy tổng quan từ dữ liệu engineering; engineers không hiểu context chiến lược của công việc họ làm. Ví dụ nhất quán: engineer báo cáo defect density → project manager tổng hợp thành schedule risk → senior management thấy ảnh hưởng đến time-to-market. Chuỗi nhân quả này chỉ hoạt động khi 3 views dùng chung ngôn ngữ và định nghĩa nhất quán.

---

**Câu 5 (Áp dụng):** Một startup fintech Việt Nam (30 nhân viên) đang phát triển ứng dụng vay tiêu dùng. CTO muốn thiết lập chương trình đo lường phần mềm đầu tiên. Sử dụng framework 4 bước trong chương, đề xuất kế hoạch cụ thể cho 3 tháng đầu.

💡 *Gợi ý: Áp dụng nguyên tắc "bắt đầu nhỏ" — không cần triển khai toàn bộ ngay, chỉ cần bắt đầu đúng hướng.*

📝 *Đáp án:* **Tháng 1 — Bước 1 (Program Model):** Xác định software objects: Resources (dev team 20 người, AWS infrastructure), Processes (sprint planning, code review, testing), Products (mobile app, API). Xác định measurement customers: CTO (strategic: time to market), PM (tactical: sprint velocity), Developers (application: defect rate). **Tháng 1–2 — Bước 2 (IDEAL-Initiate):** Assessment hiện trạng bằng CMM Level 1–2 checklist tự đánh giá. Kết quả: xác nhận Level 1, ưu tiên cải tiến: (a) tracking effort bằng Jira, (b) tracking defects bằng bug tracker. **Tháng 2 — Bước 3 (GQM):** Goal: "Giảm time-to-market cho tính năng mới." Questions: Thời gian trung bình từ story approval đến production? % story hoàn thành đúng sprint? Metrics: lead time per story (ngày), sprint completion rate (%). **Tháng 3 — Bước 4 (Plan):** Viết Measurement Plan 1 trang: ai thu thập (PM), khi nào (cuối sprint), lưu ở đâu (Google Sheet/Jira), ai phân tích (CTO monthly), và cách report (bar chart trend theo sprint).

---

## 💡 Ghi nhớ nhanh

- ✅ "Bắt đầu nhỏ, xây dựng dựa trên thành công" — đừng cố tạo chương trình đo lường hoàn hảo ngay từ đầu
- ✅ GQM đảm bảo mọi metric đều có "visa" rõ ràng: phục vụ goal nào, trả lời question nào
- ✅ CMM Level 2 (tracking effort và schedule) là nền tảng tối thiểu — không có dữ liệu lịch sử, không thể ước tính dự án tương lai
- ✅ Automated collection tools là hỗ trợ, không phải định nghĩa của quá trình đo lường — đừng để tool quyết định bạn đo gì
- ⚠️ "Haphazard collection" (thu thập hỗn loạn không có kế hoạch) tạo ra lượng lớn dữ liệu vô nghĩa — tệ hơn là không có dữ liệu
- ⚠️ Không được skip CMM levels — Level 4 và 5 yêu cầu dữ liệu lịch sử từ Level 2 và 3 mới có ý nghĩa
- 🔗 Chương tiếp theo (Chapter 5) chuyển từ "đo phần mềm" sang "đo và cải thiện con người" — thiết kế hệ thống cải tiến hiệu suất nhân viên

---

## 📖 Giải thích thuật ngữ chuyên ngành

**Goal-Question-Metric (GQM)** — Mục tiêu-Câu hỏi-Chỉ số  
Phương pháp top-down để liên kết mục tiêu tổ chức với metrics cụ thể: từ Goals → Questions cần trả lời → Metrics để đo. Đảm bảo mỗi metric đều có lý do tồn tại gắn với mục tiêu có giá trị.  
*Ví dụ:* Goal: giảm lỗi production → Question: lỗi phát sinh ở phase nào? → Metric: % defects found trong code review vs. UAT vs. production.  
*Tại sao quan trọng:* Tránh việc đo lường vô nghĩa ("chúng tôi đo SLOC vì mọi người đều đo") — mỗi metric phải trả lời một câu hỏi quan trọng.

---

**IDEAL Model** — Mô hình IDEAL (Initiate, Diagnose, Establish, Act, Leverage)  
Framework 5 giai đoạn cho cải tiến quy trình liên tục, tương tự PDSA cycle nhưng có thêm Leverage — đưa bài học học được từ một dự án vào toàn bộ tổ chức.  
*Ví dụ:* Initiate: đặt mục tiêu "giảm defect rate 30%". Diagnose: CMM assessment. Establish: ưu tiên action (code review mandatory). Act: thực hiện và đo. Leverage: lan tỏa code review process sang tất cả teams.  
*Tại sao quan trọng:* Đảm bảo cải tiến không bị lãng quên sau một dự án — knowledge được hệ thống hóa và nhân rộng.

---

**SEI CMM (Capability Maturity Model)** — Mô hình trưởng thành năng lực  
Framework 5 mức đánh giá và cải thiện quy trình phát triển phần mềm, từ Level 1 (ad hoc, không nhất quán) đến Level 5 (optimizing, tự điều chỉnh dựa trên data real-time).  
*Ví dụ:* Level 2: sprint tracking mỗi dự án. Level 4: biểu đồ statistical control với upper/lower bounds cho defect rate — trigger alert khi vượt bounds.  
*Tại sao quan trọng:* Giúp tổ chức biết mình đang ở đâu, cần đo gì tiếp theo, và ưu tiên cải tiến có trình tự hợp lý.

---

**Software Measurement Plan** — Kế hoạch đo lường phần mềm  
Tài liệu chính thức định nghĩa: data nào cần thu thập, phân tích thế nào, ai chịu trách nhiệm, khi nào thực hiện, và kết quả được lưu trữ và báo cáo ra sao.  
*Ví dụ:* Plan của một dự án banking: PM thu thập effort data từ Jira mỗi thứ Sáu; Measurement Coordinator phân tích weekly; báo cáo CPI cho Steering Committee mỗi tháng.  
*Tại sao quan trọng:* Không có plan → "haphazard collection" → dữ liệu không nhất quán, không thể so sánh, và không thể dùng để ra quyết định.

---

**Direct Measurement** — Đo lường trực tiếp  
Đo một attribute phần mềm mà không phụ thuộc vào việc đo attribute nào khác. Thường là đếm (counting).  
*Ví dụ:* SLOC (Source Lines of Code), số staff hours, số defects tìm thấy trong testing, số test cases.  
*Tại sao quan trọng:* Là "nguyên liệu thô" cho derived measures — nếu direct measure không chính xác, mọi derived measure tính từ nó đều sai.

---

**Indirect (Derived) Measurement** — Đo lường gián tiếp/dẫn xuất  
Đo một attribute bằng cách tính toán từ 2 hoặc nhiều direct measures khác. Thường là tỷ lệ hoặc density.  
*Ví dụ:* Software failure rate = số lỗi / execution time. Defect density = số defects / KLOC. Productivity = Function Points / person-month.  
*Tại sao quan trọng:* Derived measures thường mang nhiều ý nghĩa management hơn direct measures — nhưng cần 2+ direct measures chính xác và nhất quán.

---

**Software Measurement Case** — Hồ sơ đo lường phần mềm  
Tài liệu thực tế ghi lại dữ liệu thu thập được, kết quả phân tích, bài học học được, và các quyết định điều chỉnh dự án dựa trên measurement data — bổ sung cho Measurement Plan.  
*Ví dụ:* Trong khi Plan nói "collect defect data mỗi sprint," thì Case ghi "Sprint 5: defect rate 2.3/KLOC, vượt target 1.8 → decision: tăng code review từ 30% lên 60% story."  
*Tại sao quan trọng:* Case là nguồn "lessons learned" thực tế cho dự án tương lai — giúp chuyển kinh nghiệm thành tài sản tổ chức.


---

!!! info "Nguồn gốc"
    `pdf_md/managing-it-performance-to-create-business-value/guide_ai/07_chapter-4-establishing-a-software-measurement-program_guide.md`
