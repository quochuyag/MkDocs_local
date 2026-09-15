---
title: 'Guide: Chương 9 — Đo Lường Hiệu Suất IT Như Thế Nào?'
course: 07-sach-va-tai-lieu
source: pdf_md/the-business-value-of-it-managing-risks-optimizing-performance-and-measuring-results-auerbach-publications-2008/guide_ai/17_chapter-9-how-do-i-measure-it-performance_guide.md
---

# Guide: Chương 9 — Đo Lường Hiệu Suất IT Như Thế Nào?

**Nguồn:** The Business Value of IT (Auerbach Publications, 2008) — Chapter 9  
**Ngày tạo:** 2026-04-25  
**Thời gian học ước tính:** 55–65 phút

---

## 🎯 Mục tiêu học tập

Sau khi học xong chương này, bạn có thể:

- **Hiểu** sự khác biệt giữa góc nhìn đo lường của external customer (speed/cost/quality) và internal customer (cùng ba thước đo nhưng với ngưỡng chấp nhận khác nhau)
- **Phân biệt** "4 thước đo chính" (Cost, Quality, Duration, Customer Satisfaction) và "thước đo còn thiếu" (Size) — tại sao thiếu Size khiến các thước đo kia trở nên vô nghĩa khi so sánh
- **Mô tả** Function Point Analysis (FPA): 5 thành phần, cách tính, ưu điểm so với lines of code
- **Áp dụng** 8 metrics kết hợp Size với 4 thước đo chính: cost/FP, cost to repair, reliability, time to market, defect density, defect removal efficiency, test case coverage, productivity
- **Đánh giá** 3 thách thức cốt lõi khi xây dựng measurement program: nguồn data, tính toàn vẹn data, và báo cáo data
- **Nhận biết** 10 bước CMMI để thể chế hóa một measurement program bền vững

---

## 📋 Tóm tắt nội dung chính

### Hai Góc Nhìn Đo Lường IT

Khi đo lường IT performance, có hai điểm nhìn khác nhau cần xét:

**External customer** (khách hàng bên ngoài): tập trung vào speed (giao phần mềm đúng hạn), cost (giá thấp nhất), và quality (tính năng đúng, hoạt động hiệu quả). Họ ít chấp nhận thỏa hiệp.

**Internal customer** (business unit nội bộ): cùng ba thước đo nhưng **phải cân bằng với cost of running the business**. Câu hỏi không chỉ là "có nhanh không?" mà còn là "nhanh thế này có xứng đáng với chi phí không?" và "Six Sigma quality có cần thiết ở đây không, hay 99.5% đã đủ?"

### IT Value Contribution: Trách Nhiệm Chung

Chương làm rõ một điểm thường gây nhầm lẫn: ai chịu trách nhiệm về value của phần mềm?

- **IT Providers** chịu trách nhiệm về **"right software"** (kỹ thuật đúng, giao đúng hạn, đúng ngân sách, đúng requirements)
- **Business units** chịu trách nhiệm về **"right software solution"** (phần mềm đó có thực sự giải quyết vấn đề kinh doanh không? Có tăng revenue hay giảm cost không?)

Đây là trách nhiệm chia sẻ — IT không thể đơn độc guarantee business value nếu business không xác định đúng problem và requirements từ đầu.

### 4 Thước Đo Chính (+1)

**1. Cost (Chi phí):** Chủ yếu là labor cost. Phải thu thập ở project level, không chỉ ở organizational level. Phải bao gồm cả chi phí fix defects sau khi release — "cost of poor quality."

**2. Quality (Chất lượng):** Đo bằng defects. Quan trọng: đo defect removal THROUGHOUT life cycle, không chỉ trong testing. Defects tìm thấy sớm rẻ hơn nhiều lần so với tìm thấy sau khi release. Metric chính: defect removal efficiency.

**3. Duration (Thời gian):** Đo từ project initiation đến delivery. Không có định nghĩa chuẩn toàn cầu — quan trọng là tổ chức phải consistent trong cách định nghĩa và áp dụng xuyên suốt.

**4. Customer Satisfaction (Sự hài lòng của khách hàng):** Survey là cách hiệu quả nhất và ít tốn kém nhất. Nên dùng bên thứ ba để tránh bias. Phải sẵn sàng phản hồi với kết quả — nếu hỏi mà không làm gì thì mất tin cậy hơn là không hỏi.

**+1 = SIZE (Kích thước phần mềm — THE MISSING MEASURE):**

Câu chuyện minh họa trong chương: Dự án A có 12 defects, chi phí $500K. Dự án B có 22 defects, chi phí $990K. Dự án nào tốt hơn? **Không thể biết được nếu không biết size!**

Khi thêm size: Dự án A (250 FP) có defect density 0.048 và unit cost $2,000/FP. Dự án B (1,498 FP) có defect density 0.014 và unit cost $660/FP. Dự án B thực ra **tốt hơn nhiều** mặc dù tổng defects nhiều hơn và tổng chi phí cao hơn.

**"Size does matter!"** — đây là câu kết luận quan trọng nhất của chương.

### Function Point Analysis (FPA)

FPA là kỹ thuật đo size phần mềm được chấp nhận rộng rãi nhất thế giới, được quản lý bởi IFPUG (International Function Point Users Group). Ưu điểm: statistically demonstrable repeatability, nhanh, có nhiều chuyên gia.

**5 thành phần của FPA:**
1. **Inputs** — dữ liệu được đưa vào ứng dụng từ bên ngoài
2. **Outputs** — dữ liệu được xuất ra ngoài ứng dụng
3. **Inquiries** — truy vấn kết hợp input + output (lookup, report)
4. **Internal data stores** — logical groups of data được duy trì trong ứng dụng
5. **External interface files** — data được dùng chung với ứng dụng khác

Mỗi thành phần được đánh giá complexity (Low/Average/High) → tính tổng function points. Enhancement nhỏ: 50–100 FP. Ứng dụng lớn: hàng nghìn FP.

### 8 Metrics Tích Hợp Size

| Metric | Công thức | Dùng để đo |
|---|---|---|
| Cost per FP | Total project cost / Total FP | Hiệu quả chi phí, so sánh projects và benchmarks |
| Cost to repair | (Hours to repair × Cost/hour) / Release FP | Chất lượng process phát triển (cost of poor quality) |
| Reliability | Production failures / Total app FP | Độ ổn định của hệ thống đang chạy |
| Time to market | FP / Elapsed calendar time | Tốc độ delivery |
| Defect density | Defects (by phase hoặc total) / Total FP | Chất lượng sản phẩm theo phase |
| Defect removal efficiency | Pre-delivery defects / Total defects | Hiệu quả QA trong life cycle |
| Test case coverage | Test cases / Total FP | Độ bao phủ của testing |
| Productivity | Size / Effort (hoặc hours/FP) | Năng suất team |

### Xây Dựng Measurement Program Bền Vững

Ba thách thức cốt lõi:
1. **Nguồn data** — data cần thiết thường không sẵn có; cần đầu tư thêm resources
2. **Tính toàn vẹn data** — nhiều tổ chức track time nhưng không audit để đảm bảo chính xác; effort bị misallocated sang projects sai
3. **Báo cáo data** — biết audience là ai (summary vs detail), xây dựng credibility, tránh misrepresentation

CMMI đề xuất 10 bước thể chế hóa measurement: Establish policy → Plan → Provide resources → Assign responsibility → Train → Manage configurations → Involve stakeholders → Monitor & control → Evaluate adherence → Review with management.

---

## 🔑 Khái niệm quan trọng

| Khái niệm | Định nghĩa | Tại sao quan trọng | Ví dụ | Liên quan đến |
|---|---|---|---|---|
| Function Point Analysis (FPA) | Kỹ thuật đo size phần mềm dựa trên 5 yếu tố chức năng (input, output, inquiry, internal store, external file) — đo từ góc nhìn user, không phải code | Là "normalizing factor" duy nhất được công nhận quốc tế; cho phép so sánh projects khác nhau và với benchmark ngành | Enhancement nhỏ = 50–100 FP; hệ thống ERP lớn = 50,000+ FP | IFPUG, Benchmarking, Chapter 11 |
| Defect Removal Efficiency (DRE) | Tỷ lệ defects được phát hiện VÀ loại bỏ trước khi release so với tổng số defects (trước + sau release) | Đo hiệu quả thực sự của QA; một team tìm 100 bugs nhưng tất cả đều sau release kém hơn team tìm 50 bugs nhưng tất cả trước release | DRE = 80/100 = 80% (tốt); DRE = 40/100 = 40% (kém) | Quality, Testing, CMMI |
| Cost per Function Point | Tổng chi phí dự án / tổng function points được deliver | Chuẩn hóa chi phí để so sánh projects khác size và để benchmark với ngành | Dự án A: $500K / 250 FP = $2,000/FP vs benchmark ngành $800/FP → đắt hơn 2.5 lần | Cost, Benchmarking |
| Defect Density | Số defects / tổng function points — đo mật độ lỗi trong một đơn vị chức năng | Cho phép so sánh quality của các projects khác nhau về size | Dự án 1,498 FP có 22 defects → density 0.014 defect/FP; Dự án 250 FP có 12 defects → density 0.048 defect/FP | Quality, FPA |
| Time to Market | FP / Elapsed calendar time — đo tốc độ delivery được chuẩn hóa theo size | Một team deliver 500 FP trong 3 tháng nhanh hơn team deliver 100 FP trong 3 tháng | 1,500 FP / 9 tháng = 167 FP/tháng | Duration, Productivity |
| Productivity | Size / Effort (thường tính ngược: hours per FP) | Đo hiệu quả chuyển đổi effort → working software; thường dùng để so sánh offshore vs onshore, hay tool adoption impact | Team A: 20 hours/FP (expensive). Team B: 8 hours/FP (efficient) | Effort, FPA, Tools (Chapter 8) |

---

## 🌍 Ví dụ thực tế & Case Study

### Case Study 1: "Size Không Quan Trọng" — Và Hậu Quả 🇻🇳

**Bối cảnh:** Công ty bảo hiểm Việt Nam 200 dev có 4 dự án hoàn thành trong quý. Manager tổng kết: "Dự án nào cũng on-time và on-budget, chất lượng tốt." Nhưng CFO muốn biết dự án nào hiệu quả nhất để phân bổ ngân sách quý sau.

**Vấn đề:** Không có size measurement. Kết quả thô: Project Alpha $200K/15 bugs, Project Beta $600K/10 bugs, Project Gamma $400K/20 bugs, Project Delta $800K/8 bugs. Manager kết luận Delta tốt nhất (ít bugs nhất). CFO chọn đẩy mạnh đội Delta.

**Thực tế sau khi đo FP:** Alpha (200 FP) → $1,000/FP, density 0.075. Beta (1,200 FP) → $500/FP, density 0.008. Gamma (300 FP) → $1,333/FP, density 0.067. Delta (2,000 FP) → $400/FP, density 0.004. Thực ra Beta và Delta hiệu quả nhất, Alpha và Gamma kém nhất.

**Kết quả:** Sau khi bổ sung FP measurement, quyết định của CFO thay đổi hoàn toàn — đầu tư vào đội Beta và Delta, cải thiện process đội Alpha và Gamma.

**Bài học:** "Size does matter!" — không có size normalizer, mọi so sánh performance đều có thể dẫn đến quyết định sai. Đây là lý do FPA quan trọng hơn metrics thô.

---

### Case Study 2: Defect Removal Efficiency — Tìm Đúng Lúc Tiết Kiệm 10 Lần Chi Phí

**Bối cảnh:** Hai đội phát triển phần mềm ngân hàng (mỗi đội 20 người, cùng project size 500 FP):

- **Đội A:** Tìm 200 defects — 50 trong design/code review, 100 trong testing, 50 sau production release
- **Đội B:** Tìm 200 defects — 160 trong design/code review, 30 trong testing, 10 sau production release

**So sánh DRE:** Đội A: DRE = 150/200 = 75%. Đội B: DRE = 190/200 = 95%.

**Chi phí thực tế:** Theo research (Wiegers, 2002 — được trích dẫn trong chương): Fix defect trong design review tốn 1x. Trong testing tốn 10x. Sau production tốn 100x. Đội A: 50×1 + 100×10 + 50×100 = 6,050 units. Đội B: 160×1 + 30×10 + 10×100 = 1,460 units. **Đội B tiết kiệm hơn 4 lần** dù cùng số defects tổng.

**Kết quả:** Management đầu tư vào peer review, static analysis tools, và code review process cho tất cả đội → DRE trung bình tăng từ 72% lên 88% trong 1 năm → chi phí bảo trì giảm 35%.

**Bài học:** Defect removal efficiency là metric mạnh nhất để justify đầu tư vào front-end quality activities. Không cần Six Sigma — cần biết mình đang ở đâu trong defect removal lifecycle.

---

### Case Study 3: Xây Dựng Measurement Program Từ Đầu — Startup Fintech 🇻🇳

**Bối cảnh:** Startup fintech Việt Nam 60 dev muốn scale lên 150 dev trong 18 tháng. CTO muốn thiết lập measurement program để đảm bảo quality không giảm khi scale.

**Vấn đề:** Chưa có measurement gì. Không có baseline. Team chưa biết FP là gì. CFO không muốn đầu tư nhiều vào "measuring" — muốn dùng tiền cho dev.

**Giải pháp 3 bước từ chương:**
1. **Nguồn data:** Thiết lập Jira tracking đầy đủ cho time, defects theo phase; train đội lead về FP counting (không cần count toàn bộ — sample 30% dự án đủ để baseline)
2. **Tính toàn vẹn:** Monthly spot-check 3 projects ngẫu nhiên bởi Tech Lead — so sánh Jira data với actual output
3. **Báo cáo:** Dashboard đơn giản 4 metrics/tháng: cost/FP, defect density, DRE, time to market — gửi cho CTO và CFO

**Kết quả:** Sau 6 tháng có baseline. Khi scale từ 60 → 150 dev, phát hiện productivity giảm 20% (từ 8 → 10 hours/FP) — sớm hơn dự kiến. CTO dùng data này để justify đầu tư vào CI/CD tools và onboarding process cải thiện. Productivity phục hồi về 8.5 hours/FP sau 3 tháng.

**Bài học:** Bắt đầu đơn giản (4 metrics, sample-based FP counting) tốt hơn chờ perfect data. Measurement program phải có "owner" rõ ràng và được review với management hàng tháng.

---

## 📊 Sơ đồ & Bảng tổng hợp

### Bảng 1: "Size Does Matter" — Ví dụ So Sánh Từ Chương

| Dự án | Size (FP) | Chi phí ($K) | Unit Cost ($/FP) | Defects | Defect Density |
|---|---|---|---|---|---|
| PO special | 250 | 500 | **2,000** | 12 | **0.048** |
| Vendor mods | 765 | 760 | 993 | 18 | 0.023 |
| Pricing adj | 100 | 80 | 800 | 5 | **0.050** |
| Store sys | 1,498 | 990 | **660** | 22 | **0.014** |

*Store sys có unit cost thấp nhất và defect density thấp nhất — TỐTНАЙТ. PO special nhìn rẻ nhất nhưng thực ra đắt nhất khi chuẩn hóa theo size.*

---

### Bảng 2: 8 Metrics Quan Trọng — Công Thức và Ứng Dụng

| Metric | Công thức tính | Benchmark điển hình | Ứng dụng |
|---|---|---|---|
| **Cost per FP** | Total cost / Total FP | $500–$1,500/FP (tùy ngành) | So sánh projects, outsource vs in-house |
| **Cost to repair** | (Repair hours × Rate) / Release FP | — | Đo "cost of poor quality" |
| **Reliability** | Production failures / App FP | <0.01 failures/FP | Monitor production quality |
| **Time to market** | FP / Calendar months | 50–200 FP/month | Đo tốc độ team |
| **Defect density** | Defects / FP | <0.05/FP (tốt) | So sánh quality giữa projects |
| **Defect removal efficiency** | Pre-delivery defects / Total defects | >85% (tốt) | Đánh giá hiệu quả QA |
| **Test case coverage** | Test cases / FP | 3–10 cases/FP | Forecast testing effort |
| **Productivity** | Hours / FP (inverted) | 8–20 hours/FP (tùy loại) | Đo hiệu năng team |

---

### Bảng 3: 3 Thách Thức Xây Dựng Measurement Program

| Thách thức | Biểu hiện | Giải pháp |
|---|---|---|
| **Nguồn data không sẵn có** | Không có project-level cost; không track defects theo phase | Đầu tư tools tracking + training; bắt đầu với sample |
| **Tính toàn vẹn data** | Effort bị misallocate; time sheet không chính xác | Internal audit process 7 bước định kỳ |
| **Báo cáo không hiệu quả** | Data tốt nhưng report không ai đọc hoặc bị misread | Biết audience; design report trước khi collect data |

---

## ❓ Câu hỏi ôn tập

**Câu 1 (Nhớ lại):** 5 thành phần của Function Point Analysis là gì? Mỗi thành phần đo lường điều gì?

💡 **Gợi ý:** Nghĩ đến cách dữ liệu "vào" và "ra" khỏi một ứng dụng, và cách dữ liệu được lưu trữ.

📝 **Đáp án:** 5 thành phần của FPA bao gồm: (1) **Inputs** — dữ liệu đưa vào ứng dụng từ người dùng hoặc hệ thống bên ngoài (ví dụ: form nhập liệu, file upload); (2) **Outputs** — dữ liệu được xuất ra ngoài ứng dụng (ví dụ: báo cáo PDF, file export, screen hiển thị kết quả); (3) **Inquiries** — yêu cầu kết hợp input (câu hỏi từ user) và output (kết quả tra cứu) mà không cần xử lý tính toán phức tạp (ví dụ: tra cứu trạng thái đơn hàng); (4) **Internal data stores** — logical groups of data được duy trì trong ứng dụng (ví dụ: bảng khách hàng, bảng sản phẩm trong database); (5) **External interface files** — dữ liệu được dùng chung với ứng dụng khác mà không thuộc sở hữu của ứng dụng này (ví dụ: file tỷ giá từ ngân hàng nhà nước). Mỗi thành phần được đánh giá complexity Low/Average/High và cộng điểm để ra tổng function points.

---

**Câu 2 (Nhớ lại):** Tại sao Customer Satisfaction surveys nên được thực hiện bởi bên thứ ba thay vì do IT department tự thực hiện?

💡 **Gợi ý:** Nghĩ đến conflict of interest và objectivity.

📝 **Đáp án:** Khi IT department tự thực hiện customer satisfaction survey, có ít nhất ba vấn đề: (1) **Bias trong thiết kế câu hỏi** — người thiết kế survey có xu hướng (dù vô thức) viết câu hỏi theo hướng nhận được phản hồi tích cực; (2) **Bias trong phân tích kết quả** — kết quả tiêu cực có thể bị "giải thích" theo hướng ít gây tổn hại; (3) **Người được khảo sát không trả lời thật** — nhân viên biết rằng IT đang đọc kết quả có thể ngần ngại phê bình thẳng thắn. Bên thứ ba độc lập loại bỏ ba vấn đề này: câu hỏi được thiết kế khách quan, kết quả được phân tích không thiên vị, và người được khảo sát tin rằng phản hồi của mình ẩn danh thực sự. Ngoài ra, tác giả nhấn mạnh: IT phải **sẵn sàng phản hồi với kết quả** — nếu hỏi mà không làm gì, mất niềm tin còn nhiều hơn là không hỏi.

---

**Câu 3 (Hiểu):** Tại sao Defect Removal Efficiency (DRE) được mô tả là "one of the most powerful performance indicators" — mạnh hơn chỉ đo tổng số defects?

💡 **Gợi ý:** Chi phí fix defect ở giai đoạn nào thì rẻ nhất?

📝 **Đáp án:** DRE mạnh hơn tổng defect count vì hai lý do: (1) **Thời điểm phát hiện quyết định chi phí** — fix defect trong design review tốn khoảng 1x, trong testing tốn ~10x, sau production tốn ~100x (được chứng minh bởi Wiegers, 2002, được trích dẫn trong chương). Hai team cùng tìm 100 defects có thể có chi phí khác nhau 5–10 lần tùy vào lúc nào tìm thấy; (2) **DRE đo hiệu quả QA process** — nếu DRE thấp (ví dụ 50%), nghĩa là một nửa defects không được phát hiện trước khi release — front-end QA activities (peer review, static analysis, code review) đang kém. DRE cao (>85%) thì ngược lại — QA process đang hoạt động tốt. Vì vậy DRE không chỉ cho biết có bao nhiêu bugs mà còn cho biết QA process của tổ chức có systematically loại bỏ defects sớm không — thông tin này có giá trị kinh doanh trực tiếp.

---

**Câu 4 (Hiểu):** Chương phân biệt trách nhiệm của IT Provider và Business Unit như thế nào trong việc deliver "right software"?

💡 **Gợi ý:** Ai quyết định "right" problem cần giải? Ai quyết định cách giải "right"?

📝 **Đáp án:** Chương phân biệt rõ: IT Provider chịu trách nhiệm về **"right software"** — tức là phần mềm được xây đúng kỹ thuật, giao đúng hạn, đúng ngân sách, và đáp ứng đúng requirements đã được thỏa thuận. Đây là trách nhiệm kỹ thuật và project delivery. Business Unit chịu trách nhiệm về **"right software solution"** — tức là phần mềm đó có thực sự giải quyết đúng vấn đề kinh doanh không, có tạo ra tăng doanh thu hay cắt giảm chi phí không. Đây là trách nhiệm về problem definition và business impact. Thực tế: IT có thể build perfect software cho wrong requirements và vẫn "fail" dưới góc nhìn business. Ngược lại, business có thể define đúng problem nhưng IT deliver kém về quality/schedule → cũng fail. Do đó, chương nhấn mạnh đây là **trách nhiệm chia sẻ** — cả hai bên cùng phải sở hữu outcome, không thể một bên đổ lỗi cho bên kia hoàn toàn.

---

**Câu 5 (Ứng dụng):** Bạn là CTO của một công ty thương mại điện tử Việt Nam. CEO hỏi: "Đội IT của chúng ta đang làm việc hiệu quả không? Và làm sao tôi biết?" Sử dụng framework của chương, bạn sẽ xây dựng measurement program như thế nào trong 90 ngày đầu?

💡 **Gợi ý:** Bắt đầu từ 4 thước đo chính + Size, không cần đo tất cả ngay lập tức.

📝 **Đáp án:** Trong 90 ngày đầu, tôi sẽ thực hiện theo 3 phase: **Phase 1 (tháng 1) — Thiết lập baseline:** Xác định 4–6 dự án gần nhất làm mẫu; train 2 Tech Lead về FP counting (dùng IFPUG method); thu thập data retrospective: total cost, duration, defects theo phase cho 6 dự án đó; tính 4 metrics cơ bản: cost/FP, defect density, DRE, time to market. **Phase 2 (tháng 2) — Audit và Validate:** Spot-check time tracking của 2 dự án đang chạy để đảm bảo data integrity; xây dựng simple Jira/tracking template để capture data forward-looking; so sánh baseline với ISBSG benchmark ngành e-commerce nếu có. **Phase 3 (tháng 3) — Báo cáo đầu tiên:** Trình bày dashboard 1 trang cho CEO: 4 metrics hiện tại vs trend 3 tháng gần nhất (nếu có data); so sánh với benchmark ngành; 1–2 action items cụ thể (ví dụ: "DRE hiện tại 65%, target 80% trong 6 tháng bằng cách thêm code review process"). Sau 90 ngày, CEO có câu trả lời định lượng và CTO có roadmap cải thiện cụ thể.

---

## 💡 Ghi nhớ nhanh

- ✅ "Size does matter!" — không có size normalizer, mọi so sánh IT performance đều có thể misleading
- ✅ Function Point Analysis là kỹ thuật đo size được công nhận quốc tế — đo từ góc nhìn user (functional), không phải từ code
- ✅ Defect Removal Efficiency là metric mạnh nhất để optimize cost of quality — fix sớm rẻ hơn fix sau 10–100 lần
- ⚠️ Data integrity là điều kiện tiên quyết — collect data mà không audit sẽ tạo ra false picture và quyết định sai
- ⚠️ IT chịu trách nhiệm về "right software" (kỹ thuật), Business chịu trách nhiệm về "right solution" (business impact) — không thể một bên đổ lỗi hoàn toàn cho bên kia
- ⚠️ Customer satisfaction survey phải dùng third-party và phải cam kết phản hồi — nếu hỏi mà không làm gì = mất tin cậy
- 🔗 Chapter 10 tiếp theo sẽ đánh giá toàn diện liệu IT có đang hoạt động hiệu quả không, dựa trên các metrics này

---

## 📖 Giải thích thuật ngữ chuyên ngành

**Function Point Analysis — FPA (Phân tích điểm chức năng)**
Kỹ thuật đo lường kích thước phần mềm dựa trên 5 thành phần chức năng từ góc nhìn người dùng, được chuẩn hóa bởi IFPUG và sử dụng rộng rãi toàn cầu.
*Ví dụ:* Một màn hình nhập đơn hàng (input) + xuất hóa đơn PDF (output) + tra cứu tồn kho (inquiry) → đóng góp khoảng 15–25 FP cho hệ thống.
*Vai trò trong chương:* "The missing measure" — normalizing factor cho phép so sánh cost, quality, duration giữa các projects khác nhau về size.

---

**IFPUG (International Function Point Users Group)**
Tổ chức quốc tế duy trì phương pháp FPA, hỗ trợ certification chuyên gia đếm function points (CFPS), và xuất bản Counting Practices Manual (CPM).
*Ví dụ:* Chuyên gia được IFPUG chứng nhận (CFPS) có thể count FP cho bất kỳ hệ thống nào với kết quả statistically repeatable.
*Vai trò trong chương:* Đảm bảo FPA có "statistically demonstrable repeatability" — tiêu chí quan trọng của sizing metric tốt.

---

**Defect Removal Efficiency — DRE (Hiệu quả loại bỏ lỗi)**
Tỷ lệ phần trăm defects được phát hiện và loại bỏ TRƯỚC khi phần mềm được release, so với tổng số defects (trước + sau release trong một khoảng thời gian xác định).
*Ví dụ:* Tổng 100 defects: 80 tìm trước release, 20 sau release → DRE = 80%. Mục tiêu tốt: >85%.
*Vai trò trong chương:* "One of the most powerful performance indicators" — trực tiếp đo hiệu quả QA process và correlate với cost of quality.

---

**Defect Density (Mật độ lỗi)**
Số defects chia cho tổng function points — chuẩn hóa số lỗi theo kích thước phần mềm để có thể so sánh chất lượng giữa các sản phẩm khác nhau.
*Ví dụ:* Product A: 22 defects / 1,498 FP = 0.015 defect/FP (tốt). Product B: 12 defects / 250 FP = 0.048 defect/FP (kém hơn).
*Vai trò trong chương:* Minh họa "size does matter" — product A ít bugs/FP hơn dù có nhiều bugs tuyệt đối hơn.

---

**Cost per Function Point (Chi phí mỗi điểm chức năng)**
Tổng chi phí dự án (chủ yếu labor) chia cho tổng function points được deliver — đơn vị chuẩn hóa chi phí để so sánh projects và benchmark với ngành.
*Ví dụ:* Dự án $990K / 1,498 FP = $660/FP; ngành average $800/FP → đội này hiệu quả hơn ngành 17%.
*Vai trò trong chương:* Metric cốt lõi để trả lời câu hỏi từ Chapter 4: "Am I paying too much for IT?"

---

**Productivity (Năng suất)**
Trong IT: Size (FP) / Effort (hours), thường được tính ngược thành hours per FP — bao nhiêu giờ cần để produce một function point.
*Ví dụ:* Team A: 10,000 hours cho 500 FP = 20 hours/FP. Team B: 4,000 hours cho 500 FP = 8 hours/FP. Team B năng suất hơn 2.5 lần.
*Vai trò trong chương:* Metric quan trọng để justify investment vào tools (Chapter 8) và so sánh offshore vs onshore productivity.

---

**Baseline (Đường cơ sở hiệu suất)**
Mức hiệu suất đo được trong một khoảng thời gian xác định, được dùng làm điểm tham chiếu để so sánh hiệu suất tương lai hoặc để set performance targets trong SLA/contract.
*Ví dụ:* Đo 10 dự án trong 6 tháng qua → baseline: cost/FP = $900, DRE = 72%, defect density = 0.038/FP.
*Vai trò trong chương:* Điều kiện tiên quyết của bất kỳ measurement program nào — không có baseline = không thể đo cải thiện.

---

**Defect Density by Phase (Mật độ lỗi theo giai đoạn)**
Đo số defects phát hiện trong từng giai đoạn (requirements, design, coding, testing) / total FP — để xác định giai đoạn nào đang "introduce" nhiều lỗi nhất.
*Ví dụ:* Nếu 80% defects xuất hiện trong coding phase, có thể coding standards hoặc code review đang yếu.
*Vai trò trong chương:* Cho phép phân tích root cause của quality issues theo từng phase — không chỉ biết "có nhiều bugs" mà còn biết "bugs đến từ đâu trong process."

---

**AD/M (Application Development and Maintenance — Phát triển và bảo trì ứng dụng)**
Thuật ngữ mô tả toàn bộ vòng đời của phần mềm: từ phát triển mới đến bảo trì, nâng cấp và hỗ trợ ứng dụng đang chạy.
*Ví dụ:* Đội AD/M gồm dev mới tính năng, team fix bugs production, và team hỗ trợ user.
*Vai trò trong chương:* Context chính của Chapter 9 — "For this chapter, the context for our view of IT performance is primarily within the AD/M domain."


---

!!! info "Nguồn gốc"
    `pdf_md/the-business-value-of-it-managing-risks-optimizing-performance-and-measuring-results-auerbach-publications-2008/guide_ai/17_chapter-9-how-do-i-measure-it-performance_guide.md`
