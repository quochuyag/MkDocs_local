---
title: 'Hướng Dẫn Học Tập: IT Nên Dùng Những Mô Hình Nào?'
course: 07-sach-va-tai-lieu
source: pdf_md/the-business-value-of-it-managing-risks-optimizing-performance-and-measuring-results-auerbach-publications-2008/guide_ai/13_chapter-6-what-models-should-it-use_guide.md
---

# Hướng Dẫn Học Tập: IT Nên Dùng Những Mô Hình Nào?

**Nguồn:** The Business Value of IT — Chapter 6: What Models Should IT Use?
**Ngày tạo:** 2026-04-25
**Thời gian học ước tính:** 60–70 phút

---

## 🎯 Mục Tiêu Học Tập

Sau khi hoàn thành chương này, bạn có thể:

- **Giải thích** tại sao sử dụng model/framework đã được kiểm chứng hiệu quả hơn tự phát triển
- **Mô tả** nguồn gốc, mục đích và đối tượng của 6 framework IT chính: CMMI, COBIT, ITIL, ISO, PMI và Six Sigma
- **Phân biệt** CMMI Staged Representation và Continuous Representation — khi nào dùng cái nào
- **Nhận biết** COBIT như umbrella framework liên kết ITIL, CMMI, ISO và PMBOK
- **So sánh** ITIL v2 (tập trung vào process) và ITIL v3 (tập trung vào business value)
- **Áp dụng** câu hỏi "Bạn đang ở đâu?" trước khi chọn và triển khai bất kỳ framework nào

---

## 📋 Tóm Tắt Nội Dung Chính

### Tại Sao Cần Dùng Model?

George Box phát biểu: *"All models are wrong, some are useful."* Không có model nào hoàn hảo — nhưng giá trị của model nằm ở khả năng tập trung nỗ lực vào mục tiêu chung. Model giống như bản đồ: không tự đặt hướng đi cho bạn, nhưng giúp lập kế hoạch lộ trình và ước tính nguồn lực cần thiết.

Trước khi dùng bất kỳ model nào, phải biết **"Bạn đang ở đâu?"** Watts Humphrey (SEI) cảnh báo: *"If you don't know where you are, a map won't help."* Nhiều tổ chức khởi động improvement initiatives mà không baseline được hiệu suất hiện tại — kết quả là lãng phí thời gian và tiền bạc khi phải quay lại đo lường từ đầu.

### CMMI — Cho Chất Lượng Quy Trình Phần Mềm

**Nguồn gốc:** Software Engineering Institute (SEI), Carnegie Mellon University — được DoD Mỹ thành lập để đánh giá nhà thầu phần mềm và giải quyết "software crisis" (phần mềm liên tục trễ, vượt ngân sách, đầy lỗi). Phiên bản hiện tại: CMMI v1.2.

**Mục đích:** Cải thiện chất lượng hệ thống bằng cách cải thiện quy trình tạo ra nó. Không phải đánh giá sản phẩm — mà đánh giá quy trình của tổ chức.

**5 Maturity Levels** (staged) hoặc **5 Capability Levels** (continuous): từ Level 1 (Initial/Performed) đến Level 5 (Optimizing). Level 3 là chuẩn chấp nhận được cho hợp đồng; Level 5 là mục tiêu của các tổ chức phát triển phần mềm lớn như outsourcing vendor tại Ấn Độ.

**Staged vs Continuous:** Staged — lộ trình cải tiến tuần tự theo từng level, phù hợp cho tổ chức muốn benchmarking và có formal appraisal; Continuous — linh hoạt, tập trung cải tiến process areas cụ thể theo ưu tiên business, không cần đạt full level.

**Appraisal SCAMPI:** Đánh giá bởi team chuyên gia được SEI chứng nhận; kết quả có hiệu lực 3 năm; không được chọn dự án nào muốn được đánh giá.

### COBIT — Umbrella Framework Cho IT Governance

**Nguồn gốc:** IT Governance Institute (ITGI) và ISACA (Information Systems Audit and Control Association) — phiên bản 4.1 (2007).

**Vai trò đặc biệt:** COBIT là *umbrella framework* — cung cấp ngôn ngữ chung và liên kết các framework khác: ITIL (service delivery), CMMI (solution delivery), ISO/IEC 27002 (security), PMBOK/PRINCE2 (project management).

**Cấu trúc:** 4 domain × 34 high-level control objectives: Plan & Organize (PO, 10 objectives), Acquire & Implement (AI, 7 objectives), Deliver & Support (DS, 13 objectives), Monitor & Evaluate (ME, 4 objectives).

**Chứng chỉ liên quan:** CISA (Certified Information Systems Auditor) và CISM (Certified Information Security Manager) do ISACA cấp.

### ITIL — Best Practice Cho IT Service Management

**Nguồn gốc:** UK Central Computer and Telecommunications Agency (CCTA), 1987 — ban đầu cho cơ quan chính phủ Anh, nay là chuẩn toàn cầu.

**ITIL v2 → v3:** v2 (2001) tập trung vào process; v3 (2007) tập trung vào business value và vòng đời dịch vụ. v3 có 5 cuốn sách: Service Strategy, Service Design, Service Transition, Service Operation, Continual Service Improvement.

**Chuẩn hóa:** BS 15000 (British Standards) → ISO/IEC 20000 (chuẩn quốc tế cho ITSM).

**7-step improvement process** (CSI): Xác định → đo được gì → thu thập dữ liệu → xử lý → phân tích → trình bày → thực hiện hành động khắc phục.

### ISO — Chuẩn Quốc Tế

**Nguồn gốc:** International Organization for Standardization — 155 quốc gia thành viên, trụ sở Geneva. Xuất phát từ IEC (1906), ISO thành lập 1946.

**Chuẩn IT quan trọng nhất:** ISO 9000 (quality management), ISO 14000 (environmental), ISO/IEC 27002 (information security), ISO/IEC 20000 (ITSM — aligned với ITIL), ISO/IEC 15504 SPICE (process assessment — tương tự CMMI).

**SPICE vs CMMI:** SPICE phù hợp hơn nếu cần công nhận quốc tế rộng; CMMI phù hợp hơn nếu cần hợp đồng với chính phủ Mỹ. Hai chuẩn này tương thích và bổ trợ nhau.

### PMI — Quản Lý Dự Án

**Nguồn gốc:** Project Management Institute — thành lập 1969, 240,000+ thành viên, 160 quốc gia.

**Chứng chỉ cá nhân:** PgMP (Program Management), PMP (Project Management), CAPM (Certified Associate).

**5 Process Groups:** Initiating → Planning → Executing → Monitoring & Controlling → Closing.

**9 Knowledge Areas:** Integration, Scope, Time, Cost, Quality, Human Resources, Communications, Risk Management, Procurement.

**OPM3:** Organizational Project Management Maturity Model — đánh giá maturity cấp tổ chức (ít phổ biến hơn CMMI trong cộng đồng).

### Six Sigma — Chất Lượng Thống Kê

**Nguồn gốc:** Motorola 1980s — từ Total Quality Management (Deming, Juran). Không thuộc sở hữu của tổ chức nào → nhiều cách diễn giải khác nhau.

**Định nghĩa thống kê:** 3.4 defects per million opportunities (DPMO) = 99.9997% accuracy.

**DMAIC:** Define → Measure → Analyze → Improve → Control — quy trình cải tiến 5 bước.

**Ba điều kiện để bắt đầu Six Sigma project:** (1) có khoảng cách giữa hiện tại và mong muốn; (2) nguyên nhân chưa rõ; (3) giải pháp chưa được xác định.

**Cấu trúc team:** Champion, Project Sponsor, Black Belt (expert), Green Belt, Team Members, Subject Matter Expert.

---

## 🔑 Khái Niệm Quan Trọng

### CMMI (Capability Maturity Model Integration)

| Thuộc tính | Chi tiết |
| --- | --- |
| Định nghĩa | Framework đánh giá và cải thiện trưởng thành quy trình phát triển phần mềm, từ Level 1 (Initial) đến Level 5 (Optimizing) |
| Tại sao quan trọng | "Chất lượng sản phẩm phụ thuộc chất lượng quy trình tạo ra nó" — CMMI là cách đo lường và cải thiện quy trình đó một cách có hệ thống |
| Ví dụ | Outsource vendor Level 5 = quy trình phát triển phần mềm tối ưu hóa liên tục; đây là lý do các tập đoàn lớn yêu cầu vendor CMMI Level 3+ |
| Liên quan đến | SCAMPI Appraisal, SEI, COBIT (CMMI là sub-framework của COBIT cho solution delivery) |

### COBIT (Control Objectives for Information and Related Technology)

| Thuộc tính | Chi tiết |
| --- | --- |
| Định nghĩa | Umbrella framework cung cấp ngôn ngữ chung và liên kết các framework IT khác (ITIL, CMMI, ISO, PMBOK) trong bối cảnh IT governance và risk management |
| Tại sao quan trọng | Là cầu nối giữa business (cần giá trị và kiểm soát rủi ro) và IT (cần quy trình rõ ràng); cũng là chuẩn cho kiểm toán IT trong SOX compliance |
| Ví dụ | Kiểm toán viên SOX sử dụng COBIT để đánh giá 34 control objectives; CISA certification là dấu hiệu chuyên môn về COBIT và IT audit |
| Liên quan đến | ISACA, CISA, SOX, IT Governance, ITIL, CMMI, ISO/IEC 27002 |

### ITIL (IT Infrastructure Library)

| Thuộc tính | Chi tiết |
| --- | --- |
| Định nghĩa | Thư viện best practices cho IT Service Management (ITSM) — tập hợp quy trình và best practice cho vận hành IT từ service strategy đến continual improvement |
| Tại sao quan trọng | Chuẩn toàn cầu được 60%+ công ty lớn áp dụng (dự báo 2008); tạo ngôn ngữ chung giữa IT và business về service delivery |
| Ví dụ | Khi hệ thống ngân hàng online bị lỗi: Incident Management phục hồi nhanh → Problem Management tìm root cause → Change Management kiểm soát fix → ITIL định nghĩa toàn bộ quy trình này |
| Liên quan đến | COBIT, ISO/IEC 20000, BS 15000, SLA, Change Management |

### Six Sigma và DMAIC

| Thuộc tính | Chi tiết |
| --- | --- |
| Định nghĩa | Framework cải tiến chất lượng dựa trên thống kê, mục tiêu 3.4 defects per million; DMAIC là quy trình 5 bước thực hiện cải tiến |
| Tại sao quan trọng | Tạo văn hóa tổ chức tập trung vào process excellence và customer requirements; đòi hỏi leadership engagement ở mọi cấp |
| Ví dụ | Ngân hàng dùng Six Sigma để giảm thời gian xử lý hồ sơ vay từ 7 ngày xuống 2 ngày: Define (vấn đề) → Measure (thời gian hiện tại) → Analyze (bottleneck) → Improve (tái thiết quy trình) → Control (chuẩn hóa) |
| Liên quan đến | TQM, DMADV, Black Belt/Green Belt, DPMO |

### PMI và PMP

| Thuộc tính | Chi tiết |
| --- | --- |
| Định nghĩa | Project Management Institute là cơ quan toàn cầu về quản lý dự án; PMP là chứng chỉ cá nhân được công nhận rộng rãi nhất trong quản lý dự án |
| Tại sao quan trọng | Cung cấp ngôn ngữ, quy trình và tiêu chuẩn chung cho project management — đặc biệt quan trọng khi dự án IT cross-functional hoặc multi-vendor |
| Ví dụ | CIO yêu cầu tất cả IT Project Manager phải có PMP — đảm bảo mọi PM dùng cùng terminology và approach khi báo cáo tiến độ |
| Liên quan đến | PMBOK, OPM3, Monthly Project Review, IT Investment Governance |

### ISO/IEC 20000 và BS 15000

| Thuộc tính | Chi tiết |
| --- | --- |
| Định nghĩa | Chuẩn quốc tế cho IT Service Management — ISO/IEC 20000 là phiên bản quốc tế của BS 15000 (British Standard), cả hai đều aligned với ITIL |
| Tại sao quan trọng | Cho phép tổ chức chứng minh mức độ tuân thủ ITIL với bên thứ ba (khách hàng, đối tác, kiểm toán) thông qua conformity assessment độc lập |
| Ví dụ | IT outsource vendor Việt Nam muốn phục vụ khách hàng Châu Âu → đạt ISO/IEC 20000 chứng minh quy trình service management đạt chuẩn quốc tế |
| Liên quan đến | ITIL, BS 15000, COBIT, Service Level Management |

---

## 🌍 Ví Dụ Thực Tế & Case Study

### Case Study 1: Công Ty Outsourcing Việt Nam Đạt CMMI Level 3

**Bối cảnh:** Một công ty phần mềm outsourcing tại TP.HCM với 300 lập trình viên, chủ yếu nhận dự án từ Nhật Bản và Hàn Quốc. Khách hàng Nhật yêu cầu CMMI Level 3 là điều kiện bắt buộc để ký hợp đồng dài hạn.

**Vấn đề:** Công ty chưa có quy trình chuẩn hóa: mỗi team project leader có cách quản lý riêng, documentation không nhất quán, defect rate cao và khó dự báo.

**Giải pháp:** Chọn Staged CMMI (vì cần formal appraisal để chứng minh với khách hàng). Bắt đầu bằng SCAMPI C (baseline assessment) để biết đang ở đâu — phát hiện chỉ đạt Level 1. Lộ trình 18 tháng lên Level 3: tập trung vào 7 process areas của Level 2 (Project Planning, Project Monitoring & Control, Requirements Management...) trước khi lên Level 3.

**Kết quả:** Sau 20 tháng, đạt CMMI Level 3. Ký được 3 hợp đồng mới với khách Nhật, tổng giá trị tăng 40%. Defect rate giảm 60%. On-time delivery tăng từ 54% lên 81%.

**Bài học:** Biết "đang ở đâu" (Level 1 qua SCAMPI C assessment) là bước đầu tiên không thể bỏ qua. Không có baseline, không thể đo tiến độ cải tiến.

🇻🇳 **Bối cảnh Việt Nam:** CMMI đang trở thành yêu cầu ngày càng phổ biến với outsourcing vendor Việt Nam phục vụ thị trường Nhật, Hàn, và Mỹ. FPT Software, NashTech, TMA Solutions là các công ty Việt Nam đã đạt CMMI Level 5.

---

### Case Study 2: Ngân Hàng Triển Khai ITIL Để Cải Thiện Service Management

**Bối cảnh:** Một ngân hàng TMCP tại Hà Nội với 200 chi nhánh gặp vấn đề với IT service: khi hệ thống core banking có sự cố, thời gian phục hồi trung bình (MTTR) là 4 giờ; khách hàng phàn nàn liên tục; đội IT không có quy trình chuẩn để xử lý incident.

**Vấn đề:** Mỗi lần có sự cố, các kỹ sư IT tự xử lý theo kinh nghiệm cá nhân — không có escalation path rõ ràng, không phân biệt incident (triệu chứng) và problem (nguyên nhân gốc), và thay đổi vào production không có kiểm soát.

**Giải pháp:** Triển khai ITIL v3 với 3 process đầu tiên: Incident Management (phân loại, escalation, target resolution time theo SLA), Problem Management (root cause analysis sau sự cố để prevent recurrence), và Change Management (Change Advisory Board phê duyệt mọi thay đổi production).

**Kết quả:** MTTR giảm từ 4 giờ xuống 45 phút trong 6 tháng. Số sự cố tái phát giảm 70% nhờ Problem Management. Zero unauthorized change vào production sau khi có Change Advisory Board.

**Bài học:** Phân biệt Incident (phục hồi nhanh) và Problem (prevent recurrence) là insight quan trọng nhất của ITIL — nhiều tổ chức chỉ làm tốt incident mà không đầu tư vào problem management, dẫn đến sự cố lặp đi lặp lại.

🇻🇳 **Bối cảnh Việt Nam:** Ngân hàng Nhà nước Việt Nam ngày càng yêu cầu các tổ chức tín dụng có quy trình IT service management chuẩn — ITIL foundation là bước khởi đầu phù hợp.

---

### Case Study 3: Tập Đoàn Sản Xuất Dùng Six Sigma Giảm Lỗi Phần Mềm ERP

**Bối cảnh:** Một tập đoàn sản xuất tại Việt Nam vừa triển khai ERP mới. Sau 6 tháng go-live, phát hiện tỷ lệ lỗi trong module báo cáo tài chính lên tới 15% (15,000 DPMO — tương đương 3 sigma), gây ra các báo cáo sai phải làm lại thủ công.

**Vấn đề:** Nguyên nhân chưa rõ — có thể do lỗi cấu hình, lỗi data migration, lỗi quy trình người dùng, hoặc bug phần mềm. Cả 4 giả thuyết đều được đề xuất nhưng không ai có dữ liệu để chứng minh.

**Giải pháp:** Áp dụng DMAIC: Define (mục tiêu giảm xuống 1% — 10,000 DPMO) → Measure (thu thập 3 tháng dữ liệu lỗi, phân loại theo loại và nguồn gốc) → Analyze (Pareto: 65% lỗi do data entry không đúng quy trình ở bước nhập kho) → Improve (redesign quy trình nhập kho + validation rules mới) → Control (dashboard theo dõi real-time + checklist).

**Kết quả:** Tỷ lệ lỗi giảm xuống 1.2% (12,000 DPMO — xấp xỉ mục tiêu). Thời gian làm báo cáo tài chính cuối tháng giảm từ 3 ngày xuống còn 8 giờ.

**Bài học:** Six Sigma buộc tổ chức phải *đo lường* trước khi hành động. "Measure → Analyze" trong DMAIC ngăn chặn việc đổ tiền vào giải pháp sai.

🇻🇳 **Bối cảnh Việt Nam:** Six Sigma đặc biệt hiệu quả trong bối cảnh triển khai ERP tại Việt Nam — nơi chất lượng dữ liệu và tuân thủ quy trình là thách thức phổ biến trong giai đoạn adoption.

---

## 📊 Sơ Đồ & Bảng Tổng Hợp

### Bảng 1: So Sánh 6 Framework IT Chính

| Framework | Nguồn gốc | Mục đích chính | Đối tượng | Đánh giá/Chứng chỉ |
| --- | --- | --- | --- | --- |
| CMMI | SEI/Carnegie Mellon + DoD | Cải thiện quy trình phát triển phần mềm | Dev teams, outsource vendors | SCAMPI (Level 1–5) |
| COBIT | ITGI + ISACA | IT Governance, risk, compliance | CIO, Board, Auditors | CISA, CISM |
| ITIL | UK CCTA / OGC | IT Service Management best practices | IT Operations, Service Desk | ITIL Foundation → Expert |
| ISO (20000/27002) | ISO International | Chuẩn quốc tế cho ITSM và bảo mật | Tổ chức muốn certification quốc tế | Conformity Assessment |
| PMI (PMBOK) | PMI | Quản lý dự án chuyên nghiệp | Project Managers, Sponsors | PMP, PgMP, CAPM |
| Six Sigma | Motorola/GE (không có chủ sở hữu) | Cải thiện chất lượng quy trình bằng thống kê | Quality teams, Process owners | Black Belt, Green Belt |

### Bảng 2: CMMI 5 Maturity Levels — Ý Nghĩa Thực Tế

| Level | Tên | Đặc điểm | Thực tế |
| --- | --- | --- | --- |
| 1 | Initial | Ad hoc, không có quy trình chuẩn | Thành công phụ thuộc cá nhân |
| 2 | Managed | Quy trình được theo dõi và kiểm soát ở cấp project | Tối thiểu cho hầu hết hợp đồng |
| 3 | Defined | Quy trình chuẩn hóa toàn tổ chức, có tailoring | Đủ tin cậy cho hầu hết mục đích |
| 4 | Quantitatively Managed | Đo lường thống kê, kiểm soát biến động | Bước đệm lên Level 5 |
| 5 | Optimizing | Cải tiến liên tục, xử lý defect proactively | FPT Software, các vendor outsourcing lớn |

### Sơ Đồ: COBIT Là Umbrella Framework

```text
          [COBIT — IT Governance Umbrella]
               /        |         \         \
    [ITIL]  [CMMI]  [ISO 27002]  [PMBOK/PRINCE2]
  Service   Solution  Information   Project
  Delivery  Delivery   Security   Management
```

---

## ❓ Câu Hỏi Ôn Tập

**Câu 1 (Nhớ lại):** COBIT đóng vai trò gì trong hệ sinh thái các framework IT? Nó liên kết với những framework nào?

💡 Gợi ý: Từ "umbrella" — COBIT là mái vòm phía trên, các framework khác là các trụ cột bên dưới.

📝 Đáp án: COBIT đóng vai trò umbrella framework — cung cấp ngôn ngữ chung và liên kết các framework IT chuyên biệt khác trong bối cảnh IT governance và risk management. Cụ thể, COBIT liên kết: ITIL (cho service delivery), CMMI (cho solution delivery), ISO/IEC 27002 (cho information security), và PMBOK/PRINCE2 (cho project management). COBIT không thay thế các framework này mà đặt chúng vào bối cảnh governance lớn hơn — xác định control objectives và metrics cho từng domain. Điều này có nghĩa là một tổ chức đang dùng ITIL và CMMI có thể dùng COBIT như "ngôn ngữ chung" để báo cáo và đánh giá toàn diện cho ban lãnh đạo và kiểm toán.

---

**Câu 2 (Nhớ lại):** ITIL v3 khác gì so với ITIL v2? Sự thay đổi này phản ánh xu hướng gì trong IT Management?

💡 Gợi ý: Từ khóa: "process focus" (v2) vs "business value and service lifecycle" (v3).

📝 Đáp án: ITIL v2 (2001) tập trung chủ yếu vào quy trình vận hành IT — Service Delivery và Service Support là hai nhóm quy trình cốt lõi, thiên về góc nhìn kỹ thuật. ITIL v3 (2007) tái cơ cấu theo vòng đời dịch vụ: Service Strategy → Service Design → Service Transition → Service Operation → Continual Service Improvement — tập trung nhiều hơn vào business value và liên kết IT với chiến lược kinh doanh. Sự thay đổi này phản ánh xu hướng rộng hơn: IT không còn là nhà cung cấp kỹ thuật mà phải là đối tác business. v3 cũng thêm nhiều process mới (ROI, Service Portfolio Management, Demand Management) và phản ánh tầm quan trọng của ISO/IEC 20000 và các chuẩn regulatory. Nội dung v2 vẫn có giá trị — certification v2 vẫn được công nhận trong v3.

---

**Câu 3 (Hiểu):** Tại sao Watts Humphrey nói "If you don't know where you are, a map won't help" lại là nguyên tắc quan trọng trước khi triển khai bất kỳ framework nào?

💡 Gợi ý: Nghĩ đến analogy bản đồ — bạn cần biết điểm xuất phát (hiện tại) và điểm đến (mục tiêu) để lập lộ trình.

📝 Đáp án: Nguyên tắc này nhắc nhở rằng một framework chỉ hiệu quả khi tổ chức biết rõ trạng thái hiện tại của mình. Không có baseline, tổ chức không thể xác định khoảng cách cần cải thiện, không thể ưu tiên hóa đúng các process areas, và không thể đo lường tiến độ sau khi áp dụng framework. Kết quả là nhiều tổ chức khởi động CMMI hoặc ITIL implementation nhưng sau 12 tháng không biết mình đã tiến bộ bao nhiêu vì không có điểm xuất phát. Tệ hơn, tổ chức có thể chọn sai framework vì không biết thực sự vấn đề của mình là gì. SCAMPI assessment (cho CMMI) và ITIL current-state assessment đều được thiết kế để trả lời câu hỏi "chúng ta đang ở đâu" trước khi bắt đầu hành trình cải thiện.

---

**Câu 4 (Hiểu):** Khi nào nên chọn CMMI Staged Representation và khi nào chọn Continuous Representation?

💡 Gợi ý: Nghĩ đến mục tiêu của tổ chức: có cần formal appraisal để chứng minh với bên ngoài không, hay cần linh hoạt cải tiến quy trình nội bộ?

📝 Đáp án: Chọn CMMI Staged khi: (1) tổ chức cần formal appraisal để chứng minh năng lực với khách hàng hoặc để đáp ứng điều kiện hợp đồng (ví dụ: chính phủ Mỹ yêu cầu Level 3); (2) tổ chức mới bắt đầu cải tiến quy trình và cần lộ trình rõ ràng step-by-step; (3) muốn benchmark với đối thủ cạnh tranh theo maturity level. Chọn CMMI Continuous khi: (1) không cần formal appraisal hoặc không quan tâm đến maturity level rating; (2) đã có kinh nghiệm cải tiến quy trình và muốn tập trung vào những process areas cụ thể quan trọng nhất với business objectives; (3) đang migration từ ISO/IEC 15504 SPICE; (4) muốn linh hoạt cải tiến theo từng bước nhỏ trong các process areas cụ thể mà không cần đạt full level.

---

**Câu 5 (Ứng dụng):** Công ty bạn đang gặp vấn đề: tỷ lệ defect trong deployment tăng 40% so với năm trước, khiến nhiều hotfix phải thực hiện sau khi go-live. Bạn sẽ đề xuất framework nào để giải quyết và tại sao?

💡 Gợi ý: Xác định bản chất vấn đề trước: là quy trình phát triển (CMMI), quy trình deployment (ITIL Change/Release Management), hay chất lượng quy trình tổng thể (Six Sigma)?

📝 Đáp án: Với vấn đề này, tôi đề xuất kết hợp ITIL và Six Sigma theo thứ tự: trước tiên dùng ITIL Change Management và Release & Deployment Management để kiểm soát chất lượng deployment — thiết lập Change Advisory Board, deployment checklist, và rollback plan; song song dùng Six Sigma DMAIC để tìm root cause của defect tăng 40%: Measure (đo lường loại defect nào, stage nào, team nào), Analyze (Pareto để tìm top causes), Improve (điều chỉnh quy trình), Control (chuẩn hóa). Nếu phân tích cho thấy vấn đề nằm ở quy trình development lifecycle (không chỉ deployment), thì CMMI Level 2 process areas (Project Monitoring, Configuration Management, Process & Product Quality Assurance) sẽ là step tiếp theo. Quan trọng: không áp framework nào trước khi có baseline data về defect rate hiện tại.

---

## 💡 Ghi Nhớ Nhanh

- ✅ COBIT là umbrella framework — liên kết ITIL, CMMI, ISO, PMBOK trong một ngôn ngữ chung cho IT governance
- ✅ "Biết bạn đang ở đâu" là bước đầu tiên — không có baseline, mọi framework đều lãng phí
- ✅ CMMI Staged = lộ trình rõ ràng + formal appraisal cho khách hàng bên ngoài; CMMI Continuous = linh hoạt cải tiến quy trình cụ thể
- ✅ ITIL v3 khác v2 ở chỗ: tập trung vào business value và vòng đời dịch vụ, không chỉ quy trình kỹ thuật
- ✅ Six Sigma = 3.4 defects per million; DMAIC = Define → Measure → Analyze → Improve → Control
- ⚠️ Pitfall: Chọn framework vì "đang thịnh hành" thay vì vì nó phù hợp với vấn đề thực tế của tổ chức
- ⚠️ Pitfall: SCAMPI appraisal CMMI không cho phép chọn dự án được đánh giá — cần chuẩn bị toàn bộ tổ chức, không chỉ "đội tốt nhất"
- ⚠️ Pitfall: Nhầm Six Sigma là chỉ dành cho sản xuất — DMAIC áp dụng hiệu quả cho quy trình phần mềm và IT operations
- 🔗 Chương 7 tiếp theo sẽ trả lời câu hỏi thực tế: khi IT outsource công việc ra bên ngoài, làm thế nào đảm bảo outsourcing thực sự hiệu quả?

---

## 📖 Giải Thích Thuật Ngữ Chuyên Ngành

**CMMI (Capability Maturity Model Integration)** — Mô hình tích hợp trưởng thành năng lực
Framework do SEI (Carnegie Mellon) phát triển để đánh giá và cải thiện trưởng thành quy trình phát triển phần mềm theo 5 level. "Maturity" ở đây là về quy trình tổ chức, không phải về sản phẩm hay cá nhân. Tương tự như chứng nhận ISO nhưng tập trung vào software process improvement.

**SCAMPI (Standard CMMI Appraisal Method for Process Improvement)** — Phương pháp đánh giá CMMI chính thức
Quy trình đánh giá chính thức do team chuyên gia được SEI chứng nhận thực hiện để xác định mức maturity level của một tổ chức. Có 3 cấp: SCAMPI C (benchmark nhẹ), B (trung bình), A (formal, full appraisal — cần thiết để được công nhận maturity level). Kết quả SCAMPI A có hiệu lực 3 năm.

**COBIT (Control Objectives for Information and Related Technology)** — Mục tiêu kiểm soát cho IT
Framework quản trị IT do ISACA và ITGI phát triển, cung cấp 34 high-level control objectives trong 4 domain (Plan/Organize, Acquire/Implement, Deliver/Support, Monitor/Evaluate). Được dùng rộng rãi trong IT audit và SOX compliance.

**ISACA** — Hiệp hội kiểm soát và kiểm toán hệ thống thông tin
Tổ chức toàn cầu phát triển COBIT và cấp hai chứng chỉ quan trọng: CISA (Certified Information Systems Auditor) cho IT auditors, và CISM (Certified Information Security Manager) cho IT security managers.

**ITIL (IT Infrastructure Library)** — Thư viện hạ tầng IT
Bộ sưu tập best practices cho IT Service Management — không phải một cuốn sách mà là một thư viện gồm nhiều cuốn (v3: 5 cuốn theo vòng đời dịch vụ). "Library" nhấn mạnh rằng tổ chức chọn lọc và áp dụng những gì phù hợp, không phải implement tất cả.

**ITSM (IT Service Management)** — Quản lý dịch vụ IT
Cách tiếp cận coi IT như một tập hợp các dịch vụ cung cấp cho khách hàng (internal hoặc external), không phải như một tập hợp công nghệ. Chuyển từ "IT quản lý servers" sang "IT cung cấp dịch vụ email/storage/analytics" — mỗi dịch vụ có SLA, cost, và quality metrics riêng.

**DMAIC** — Define-Measure-Analyze-Improve-Control
Quy trình 5 bước cốt lõi của Six Sigma cho cải tiến quy trình hiện có. Tương tự PDCA (Plan-Do-Check-Act) của Deming nhưng với nhấn mạnh mạnh hơn vào đo lường và phân tích thống kê. Khác với DMADV (Design-Measure-Analyze-Design-Validate) dùng cho thiết kế quy trình mới.

**DPMO (Defects Per Million Opportunities)** — Số lỗi trên một triệu cơ hội
Đơn vị đo lường chất lượng trong Six Sigma. Six Sigma = 3.4 DPMO = 99.9997% chính xác. Để so sánh: 3 sigma = 66,807 DPMO (93.3%); 4 sigma = 6,210 DPMO (99.4%). Tên "Six Sigma" xuất phát từ cách tính khoảng cách thống kê giữa mean và specification limit.

**Black Belt / Green Belt** — Đai đen / Đai xanh Six Sigma
Chứng chỉ năng lực Six Sigma: Green Belt có thể tham gia và lead các dự án Six Sigma nhỏ; Black Belt là expert được đào tạo đầy đủ về thống kê và methodology, lead các dự án phức tạp và coaching Green Belts. Master Black Belt là cấp cao nhất — huấn luyện và mentoring Black Belts.

**OPM3 (Organizational Project Management Maturity Model)** — Mô hình trưởng thành quản lý dự án tổ chức
Phiên bản của PMI để đánh giá maturity project management ở cấp tổ chức (thay vì cấp cá nhân như PMP). Ít được công nhận rộng rãi hơn CMMI nhưng cung cấp framework để cải thiện PM capability toàn tổ chức. Tương tự CMMI nhưng tập trung vào project management domain.


---

!!! info "Nguồn gốc"
    `pdf_md/the-business-value-of-it-managing-risks-optimizing-performance-and-measuring-results-auerbach-publications-2008/guide_ai/13_chapter-6-what-models-should-it-use_guide.md`
