---
title: 'Guide: Chapter 10 — IT Có Đang Hoạt Động Hiệu Quả Không?'
course: 07-sach-va-tai-lieu
source: pdf_md/the-business-value-of-it-managing-risks-optimizing-performance-and-measuring-results-auerbach-publications-2008/guide_ai/18_chapter-10-is-it-operating-effectively_guide.md
---

# Guide: Chapter 10 — IT Có Đang Hoạt Động Hiệu Quả Không?

**Nguồn:** The Business Value of IT (Auerbach Publications, 2008) — Chapter 10: Is IT Operating Effectively?  
**Ngày tạo:** 2026-04-25  
**Thời gian học ước tính:** 35–40 phút

---

## 🎯 Mục tiêu học tập

Sau khi học xong phần này, bạn có thể:

- **Hiểu** tại sao cần kết hợp cả dữ liệu định lượng (quantitative) và định tính (qualitative) để đánh giá toàn diện hiệu quả IT
- **Phân biệt** 4 loại dữ liệu định lượng và 6 nhóm dữ liệu định tính trong mô hình đo lường hiệu suất
- **Mô tả** quy trình xây dựng Performance Profile từ baseline data và cách diễn giải kết quả
- **Áp dụng** mô hình 3 thành phần (Size × Complexity × Capacity) để hiểu và cải thiện ước lượng phần mềm
- **Đánh giá** ý nghĩa thực tế khi so sánh hiệu suất theo platform, SDM usage, và business unit

---

## 📋 Tóm tắt nội dung chính

### Mô Hình Đo Lường Hiệu Suất

Chapter 10 mở rộng từ Chapter 9: nếu Chapter 9 giới thiệu các thước đo cốt lõi, Chapter 10 xây dựng mô hình hoàn chỉnh để đánh giá IT có đang hoạt động hiệu quả không. Chìa khóa là **kết hợp dữ liệu định lượng (quantitative) và định tính (qualitative)** — hai loại dữ liệu bổ sung cho nhau, không thể thay thế nhau.

**Quantitative data** trả lời câu hỏi "cái gì đã xảy ra": bao nhiêu FP được deliver, tốn bao nhiêu giờ, mất bao nhiêu tháng, có bao nhiêu defect. **Qualitative data** trả lời câu hỏi "tại sao": team có kinh nghiệm không, quy trình có chuẩn không, môi trường có thuận lợi không. Chỉ có quantitative data thì biết project A kém hơn project B, nhưng không biết lý do. Chỉ có qualitative data thì có ý kiến chủ quan nhưng không có bằng chứng số liệu.

### Dữ Liệu Định Lượng — 4 Thành Phần

**Size (Kích thước)** đo bằng Function Points — lý do FP được ưu tiên là SLOC (source lines of code) không có định nghĩa chuẩn ngành, khó so sánh giữa các tổ chức và công nghệ. FP có IFPUG định nghĩa chuẩn, áp dụng được cho mọi ngôn ngữ.

**Effort (Nỗ lực)** đo bằng person-hours — bao gồm tất cả labor của toàn bộ project team kể cả project manager, không tính end-user effort.

**Duration (Thời gian)** đo từ khi IT bắt đầu ghi nhận thời gian cho project đến khi phần mềm "fit for use" hoặc rollout lần đầu. Với dự án stop-and-start, **lag-time** (thời gian không productive / tổng thời gian) là metric hữu ích để thấy lãng phí ẩn.

**Quality (Chất lượng)** bao gồm cả pre-release defects (từ design review, code inspection) và post-release defects (problem tickets từ user). Thu thập pre-release defect data đòi hỏi đầu tư ban đầu nhưng cho thấy cơ hội phát hiện lỗi sớm — rẻ hơn nhiều so với sửa sau.

### Dữ Liệu Định Tính — 6 Nhóm, ~80 Biến

David Consulting Group đã xây dựng hệ thống thu thập qualitative data với 6 nhóm chính: **Management** (quản lý dự án, kinh nghiệm PM, tools), **Definition** (rõ ràng yêu cầu, involvement khách hàng), **Design** (quy trình thiết kế, reuse, kinh nghiệm), **Build** (code review, source code tracking, reuse), **Test** (formal testing, test plans, effective tools), **Environment** (training, organizational dynamics, certification).

Mỗi câu hỏi có dạng yes/no với trọng số được gán sẵn. Điểm tổng hợp cho mỗi project là Profile Score từ 1–100. Một điểm thú vị từ dữ liệu thực tế: category Design thường xuất hiện "na" (not applicable) — có thể phản ánh thực tế nhiều dự án bỏ qua bước thiết kế.

### Phân Tích Dữ Liệu và Báo Cáo Kết Quả

Ví dụ minh họa từ cuốn sách so sánh hai dự án cùng platform PC: **Vendor Solution** (111 FP, productivity 12.8 FP/PM) vs **Merchandise Reporting** (83 FP, productivity 3.2 FP/PM). Vendor Solution vượt trội rõ ràng về tốc độ, chi phí, và chất lượng. Phân tích qualitative cho thấy Vendor Solution có nhiều indicator tích cực hơn — đặc biệt về testing practices.

Bảng tổng hợp performance (Tables 10.4a–d) phân tích theo platform (PC vs UNIX), business unit (BU1/2/3), và SDM usage. Một quan sát quan trọng: **"Used SDM" cho productivity thấp hơn "No SDM" (5.3 vs 12.1 FP/PM)** — không có nghĩa SDM làm giảm năng suất, mà phản ánh thực tế SDM thường được áp dụng cho các dự án phức tạp hơn.

Phân tích portfolio ứng dụng (Figures 10.5a–d) cho thấy PC platform rẻ hơn cả khi phát triển ($352/FP vs mainframe $687/FP) lẫn khi bảo trì (assignment scope 512 FP/FTE vs mainframe 262 FP/FTE). Mainframe có tuổi trung bình 12.9 năm, 65% ứng dụng trên 10 năm — đây là rủi ro aging software.

### Cải Thiện Ước Lượng

Ước lượng phần mềm luôn là điểm yếu của IT. Chương này đề xuất framework 3 thành phần: **Size** (được đo bằng FP) × **Complexity** (độ phức tạp — có thể dùng Low/Medium/High đơn giản, hoặc commercial estimating tool) × **Capacity** (năng lực team — từ qualitative profile). Thiếu bất kỳ thành phần nào, estimate sẽ không đáng tin cậy.

SEI yêu cầu good estimating cần: historical database, structured processes, cơ chế extrapolation từ past projects, audit trails, và data feedback. Trước khi có framework này, nhiều tổ chức ước lượng bằng "gut feel" hoặc burn extra unaccounted hours để fit vào estimate ban đầu — cả hai đều nguy hiểm.

---

## 🔑 Khái niệm quan trọng

| Khái niệm | Định nghĩa | Tại sao quan trọng | Ví dụ | Liên quan đến |
|---|---|---|---|---|
| Performance Profile | Tổng hợp quantitative + qualitative data thành bức tranh toàn diện về hiệu quả IT của tổ chức | Không có profile = chỉ thấy "cái gì xảy ra" mà không biết "tại sao" | Vendor Solution score 49.3/100, Merchandise Reporting 29.2/100 → profile giải thích chênh lệch productivity 4:1 | Chapter 9, Qualitative Data |
| Qualitative Data (6 nhóm) | Dữ liệu "mềm" về đặc điểm dự án: kỹ năng, quy trình, công cụ, quản lý — thu thập qua yes/no survey, tính điểm 1–100 | Giải thích nguyên nhân biến động trong quantitative results | 2 dự án PC cùng quy mô nhưng khác performance → qualitative reveal: 1 dự án có formal test plan, 1 không | Performance Profile, Chapter 9 Quality |
| Assignment Scope | Số function points mà mỗi FTE (full-time equivalent) phụ trách trong maintenance | Đo cost-effectiveness của bảo trì ứng dụng — FP/FTE cao = ít người duy trì nhiều chức năng hơn = rẻ hơn | PC: 512 FP/FTE vs Mainframe: 262 FP/FTE → PC rẻ hơn gần 2x để bảo trì | Portfolio Management, Aging Analysis |
| Lag-Time | Thời gian không productive (khi dự án bị tạm dừng) tính theo % tổng thời gian dự án | Phát hiện lãng phí ẩn trong dự án stop-and-start — không đo thì không thấy | Dự án 10 tháng có 3 tháng hold → lag-time 30% — IT đang tính phí cho thời gian không làm gì | Duration, Baseline |
| FP Lite® | Phương pháp đếm function point đơn giản hóa, giảm thời gian và công sức so với IFPUG full count | Phá vỡ rào cản "quá phức tạp để đếm FP" — cho phép tổ chức bắt đầu đo size mà không cần đội chuyên gia | Thay vì 2 ngày đếm đầy đủ, FP Lite® hoàn thành trong vài giờ với sai số chấp nhận được | Function Point Analysis, Chapter 9 |
| Estimating Model (3 thành phần) | Framework ước lượng dựa trên Size × Complexity × Capacity — không phải magic number mà là quản lý kỳ vọng | Nếu thiếu bất kỳ thành phần nào: estimate sẽ bỏ qua yếu tố quan trọng ảnh hưởng đến outcome | Dự án 350 FP (Size) × High complexity (1.3x) × Junior team (0.8x productivity) = estimate khác hẳn Senior team | Qualitative Profile, FPA |

---

## 🌍 Ví dụ thực tế & Case Study

### Case Study 1: Ngân Hàng Việt Nam Phát Hiện Khoảng Cách Giữa Business Unit 🇻🇳

**Bối cảnh:** IT Director của một ngân hàng có 3 business unit (BU) sử dụng IT — BU Core Banking, BU Digital, BU Operations. Sau 6 tháng thu thập baseline data lần đầu, kết quả được tổng hợp.

**Vấn đề:** BU Digital đạt 11.5 FP/person-month (tương đương Business Unit 3 trong sách), trong khi BU Operations chỉ đạt 4.0 FP/person-month — gần 3x chênh lệch. Ban lãnh đạo ngạc nhiên: cùng tổ chức, cùng tools, cùng processes.

**Giải pháp:** Phân tích qualitative profile cho thấy BU Digital có: (1) kinh nghiệm staff cao hơn, (2) formal test plan được thực hiện nghiêm túc, (3) customer involvement tốt hơn từ đầu dự án. BU Operations có testing score gần 0 — hầu hết câu hỏi test category đều trả lời "No."

**Kết quả:** Chương trình mentoring cross-BU được thiết lập — BU Digital chia sẻ testing practices cho BU Operations. Sau 12 tháng, BU Operations cải thiện từ 4.0 lên 6.2 FP/PM.

**Bài học:** Qualitative data không chỉ giải thích quá khứ mà còn chỉ ra chính xác điều gì cần cải thiện. Không có qualitative profile, giải pháp sẽ là mua tool mới hoặc tuyển thêm người — không giải quyết root cause.

---

### Case Study 2: Công Ty Phần Mềm Bắt Đầu Thu Thập Defect Data 🇻🇳

**Bối cảnh:** Một công ty outsourcing Việt Nam với 150 developer không bao giờ thu thập pre-release defect data. Defect chỉ được ghi nhận khi client report sau khi deploy.

**Vấn đề:** Không có data về defect density, không thể cam kết quality SLA với client, không biết mình đang "tốt hay kém" về chất lượng so với ngành.

**Giải pháp:** Bắt đầu từ thứ đơn giản nhất: áp dụng code inspection cho 5 dự án đang chạy. Thu thập defect theo phase (requirements, design, code). Sau 3 tháng có đủ data để tính defect density cơ bản.

**Kết quả:** Phát hiện 70% defect được tìm thấy ở phase code — quá muộn và tốn kém. Chuyển sang review requirements sớm hơn. Defect density post-release giảm 40% trong 6 tháng. Chi phí sửa lỗi giảm vì lỗi được phát hiện sớm hơn trong lifecycle.

**Bài học:** Thu thập defect data "đau" ban đầu nhưng lợi ích là ngay lập tức. Không phải chờ có đủ tool hay process hoàn hảo — bắt đầu từ code inspection là đủ để thấy pattern.

---

### Case Study 3: Platform Decision Dựa Trên Data

**Bối cảnh:** CTO của một tập đoàn bán lẻ đang cân nhắc có nên tiếp tục phát triển trên mainframe hay không. Mainframe cũ, đắt tiền để maintain, nhưng team có kinh nghiệm nhiều năm với nó.

**Vấn đề:** Quyết định thiếu data. Team mainframe lập luận "chúng tôi hiểu hệ thống này." Team PC/web lập luận "tương lai là cloud." Không ai có số liệu.

**Giải pháp:** Phân tích portfolio theo platform (tương tự Figures 10.5a–d): Mainframe $687/FP vs PC $352/FP khi phát triển; Assignment scope mainframe 262 FP/FTE vs PC 512 FP/FTE khi bảo trì; Mainframe avg age 12.9 năm, 65% ứng dụng > 10 năm.

**Kết quả:** Data cho thấy mainframe đắt gấp đôi để phát triển và chỉ bằng một nửa hiệu quả khi bảo trì. Quyết định: tiếp tục hỗ trợ mainframe cho core banking (quá critical để migrate ngay) nhưng tất cả new development chuyển sang PC/web.

**Bài học:** Portfolio analysis (by platform, age, cost) chuyển cuộc tranh luận từ "cảm tính và kinh nghiệm" thành "data và business case." Đây là loại IT transparency mà Chapter 10 hướng đến.

---

## 📊 Sơ đồ & Bảng tổng hợp

### Mô Hình Đo Lường Baseline

| Loại dữ liệu | Thành phần | Phương pháp thu thập | Mục đích |
|---|---|---|---|
| Quantitative | Size (FP), Effort (hours), Duration (months), Quality (defects) | Project manager + FP counter độc lập | Đo "điều gì đã xảy ra" — bằng chứng số liệu |
| Qualitative | 6 nhóm: Management, Definition, Design, Build, Test, Environment (~80 biến) | Interview/survey dạng yes/no, weighted score | Giải thích "tại sao xảy ra" — nguyên nhân biến động |

### Estimating Model — 3 Thành Phần Bắt Buộc

| Thành phần | Định nghĩa | Cách đo | Nếu thiếu |
|---|---|---|---|
| Size | Lượng chức năng cần deliver | Function Point Analysis | Không biết "bao nhiêu việc" — estimate chỉ là đoán |
| Complexity | Mức độ khó của vấn đề | Low/Med/High rating hoặc commercial tool | Bỏ qua rủi ro kỹ thuật — underestimate thường xuyên |
| Capacity | Năng lực team để deliver | Qualitative profile scores (skills, experience, tools) | Giả định "average team" — không phản ánh thực tế |

### So Sánh Performance Theo Platform (từ dữ liệu chương)

| Platform | Cost/FP | Assignment Scope (FP/FTE) | Avg Age (năm) | % Apps > 10 năm |
|---|---|---|---|---|
| Mainframe | $687 | 262 | 12.9 | 65% |
| Client/Server | $654 | 275 | 5.6 | 14% |
| Mid-Range | $748 | 241 | 13.2 | 81% |
| PC | $352 | 512 | 4.3 | 0% |

---

## ❓ Câu hỏi ôn tập

**Câu 1 (Nhớ lại):** Tại sao SLOC (source lines of code) không phải là thước đo size tốt cho industry benchmark, trong khi Function Points lại được ưu tiên?

💡 **Gợi ý:** Nghĩ về điều kiện để 2 tổ chức có thể so sánh metric với nhau một cách có ý nghĩa.

📝 **Đáp án:** SLOC không có định nghĩa chuẩn ngành — cùng một đoạn code, các tổ chức khác nhau có thể đếm theo cách khác nhau (có tính blank lines không, có tính comments không, đếm theo ngôn ngữ nào). Điều này làm cho việc so sánh giữa các tổ chức hoặc dự án sử dụng các công nghệ khác nhau trở nên vô nghĩa. Function Points, ngược lại, được định nghĩa chuẩn bởi IFPUG với methodology nhất quán, không phụ thuộc vào ngôn ngữ lập trình hay nền tảng — cho phép so sánh có ý nghĩa cả nội bộ lẫn với industry.

---

**Câu 2 (Nhớ lại):** 3 thành phần của estimating model theo Chapter 10 là gì, và tại sao thiếu bất kỳ thành phần nào cũng làm estimate không đáng tin cậy?

💡 **Gợi ý:** Mỗi thành phần đại diện cho một loại thông tin khác nhau về dự án — khi nào bạn thiếu một trong ba?

📝 **Đáp án:** Ba thành phần là: (1) **Size** — lượng chức năng cần build, đo bằng FP; (2) **Complexity** — mức độ khó của vấn đề kỹ thuật; (3) **Capacity** — năng lực thực tế của team. Thiếu Size nghĩa là không biết "bao nhiêu việc" — estimate hoàn toàn là đoán mò. Thiếu Complexity nghĩa là hai dự án cùng size (350 FP) nhưng khác độ phức tạp sẽ cho cùng một estimate — một dự án CRUD đơn giản và một dự án real-time trading algorithm không thể estimate bằng nhau. Thiếu Capacity nghĩa là assume "average team" — một junior team và senior team với cùng Size và Complexity sẽ cho outcome rất khác nhau.

---

**Câu 3 (Hiểu):** Trong bảng 10.4a, nhóm "Used SDM" có productivity thấp hơn "No SDM" (5.3 vs 12.1 FP/PM). Điều này có nghĩa là sử dụng Software Development Methodology làm giảm năng suất không? Giải thích.

💡 **Gợi ý:** Hãy nghĩ đến loại dự án nào thường được áp dụng SDM, và loại nào thường không.

📝 **Đáp án:** Không — đây là ví dụ điển hình về correlation không đồng nghĩa với causation. SDM thường được áp dụng cho các dự án phức tạp hơn, lớn hơn, có nhiều stakeholder hơn — những dự án vốn đã khó hơn và tốn thời gian hơn. Trong khi đó, "No SDM" thường là các project nhỏ, đơn giản, team nhỏ — productivity tự nhiên cao hơn vì ít overhead. Dữ liệu không nói rằng SDM xấu; thay vào đó, để hiểu impact thực sự của SDM, cần so sánh hai nhóm dự án cùng size và complexity — một nhóm dùng SDM, một nhóm không. Chapter 10 nhấn mạnh tầm quan trọng của việc "giữ các biến khác không đổi" (holding variables constant) khi phân tích data.

---

**Câu 4 (Hiểu):** Qualitative data và quantitative data bổ sung cho nhau như thế nào trong việc phân tích hiệu quả IT? Cho ví dụ cụ thể từ chương.

💡 **Gợi ý:** Mỗi loại data trả lời một câu hỏi khác nhau — cùng nhau chúng mới tạo thành bức tranh đầy đủ.

📝 **Đáp án:** Quantitative data cung cấp bằng chứng khách quan về "điều gì đã xảy ra": Vendor Solution deliver 111 FP với productivity 12.8 FP/PM, Merchandise Reporting deliver 83 FP với productivity 3.2 FP/PM — Vendor Solution tốt hơn rõ ràng. Nhưng quantitative data không giải thích tại sao. Qualitative data điền vào gap này: profile score của Vendor Solution cao hơn đặc biệt ở testing category, trong khi Merchandise Reporting có nhiều indicator âm hơn ở test và management. Nếu chỉ có quantitative: ta biết ai tốt hơn nhưng không biết phải làm gì để cải thiện. Nếu chỉ có qualitative: ta có ý kiến chủ quan về quy trình nhưng không có số liệu để backup. Kết hợp cả hai tạo ra performance profile đầy đủ để ra quyết định cải tiến.

---

**Câu 5 (Áp dụng):** Một CIO muốn bắt đầu baseline performance IT nhưng tổ chức chưa bao giờ thu thập function point data. Theo Chapter 10, bước đầu tiên nên làm gì, và tại sao đây là điểm khởi đầu hợp lý?

💡 **Gợi ý:** Chapter 10 thừa nhận rào cản nhận thức về FP collection — và đề xuất cách vượt qua.

📝 **Đáp án:** Theo Chapter 10, bước đầu tiên là chọn một tập hợp dự án **đại diện đã hoàn thành gần đây** (trong 6–12 tháng) và bắt đầu đếm function points cho chúng. Không cần đếm tất cả dự án — chỉ cần portfolio sample đủ đại diện (ví dụ: nếu 80% là small enhancements, baseline nên có 80% small enhancements). Đây là điểm khởi đầu hợp lý vì: (1) FP collection thực ra không tốn thời gian hơn weekly effort tracking vốn đã làm; (2) FP Lite® có thể giúp đếm nhanh hơn; (3) chỉ cần một người chuyên đếm FP (có thể outsource) là đủ. Nên bắt đầu đồng thời thu thập effort và duration data vì các data này thường đã có sẵn trong project management records. Defect data có thể bắt đầu đơn giản từ post-release problem tickets trước khi nâng cấp lên pre-release tracking.

---

## 💡 Ghi nhớ nhanh

- ✅ Quantitative data = "điều gì đã xảy ra"; Qualitative data = "tại sao xảy ra" — cả hai là bắt buộc để đánh giá IT effectiveness toàn diện
- ✅ Performance Profile = điểm số 1–100 tổng hợp từ ~80 biến định tính trong 6 category; dùng để so sánh dự án và identify root cause
- ✅ Estimating = Size × Complexity × Capacity — không phải "magic number" mà là framework quản lý kỳ vọng dựa trên data thực tế
- ✅ Assignment Scope (FP/FTE) = metric quan trọng để đánh giá cost-effectiveness của maintenance, không chỉ development
- ⚠️ "Used SDM = productivity thấp hơn" KHÔNG có nghĩa SDM xấu — đây là correlation do project selection bias, không phải causation
- ⚠️ Không thu thập defect data trong lifecycle = không thể measure quality = không có baseline để cải tiến chất lượng
- 🔗 Chapter 11 tiếp theo sẽ so sánh baseline nội bộ này với industry benchmark data — "chúng ta đứng ở đâu so với ngành?"

---

## 📖 Giải thích thuật ngữ chuyên ngành

**Performance Profile (Hồ sơ hiệu suất)**
Tổng hợp từ quantitative và qualitative data thành một bức tranh toàn diện về hiệu quả hoạt động của IT tổ chức.
*Ví dụ:* Profile Score 49.3/100 cho Vendor Solution vs 29.2/100 cho Merchandise Reporting — cùng với productivity data, profile giải thích nguyên nhân chênh lệch 4:1.
*Vai trò:* Nền tảng để so sánh dự án, identify best practices nội bộ, và track improvement theo thời gian.

---

**Qualitative Data (Dữ liệu định tính)**
Dữ liệu "mềm" về đặc điểm và thuộc tính của dự án — kỹ năng team, quy trình phát triển, công cụ sử dụng, phong cách quản lý. Thu thập qua yes/no survey với trọng số.
*Ví dụ:* "Development staff experienced with type of application being developed? Yes/No" — câu hỏi này có trọng số cao vì kinh nghiệm ảnh hưởng lớn đến outcome.
*Vai trò:* Giải thích nguyên nhân của biến động trong quantitative results — không có qualitative data, ta chỉ biết "ai tốt hơn" mà không biết "tại sao."

---

**Assignment Scope (Phạm vi phụ trách bảo trì)**
Số function points mà mỗi FTE (full-time equivalent) phụ trách trong hoạt động maintenance.
*Ví dụ:* PC platform có assignment scope 512 FP/FTE vs Mainframe 262 FP/FTE — có nghĩa cần ít nhân sự hơn để bảo trì cùng lượng chức năng trên PC.
*Vai trò:* Metric quan trọng để đánh giá TCO (total cost of ownership) của portfolio ứng dụng — không chỉ nhìn vào development cost.

---

**Lag-Time (Thời gian trống)**
Phần trăm thời gian không productive trong tổng thời gian dự án — xảy ra khi dự án bị tạm dừng rồi khởi động lại.
*Ví dụ:* Dự án 10 tháng tổng, nhưng 3 tháng bị hold vì thiếu resource → lag-time 30% — hiển thị thời gian lãng phí mà không tính vào effort.
*Vai trò:* Phát hiện hidden waste trong duration — giúp management thấy impact thực của resource contention và priority conflicts.

---

**FP Lite® (Đếm function point đơn giản hóa)**
Phương pháp đếm function point rút gọn so với full IFPUG methodology — giảm thời gian và yêu cầu expertise trong khi vẫn đảm bảo đủ chính xác cho mục đích đo lường.
*Ví dụ:* Full IFPUG count có thể cần 1–2 ngày cho một ứng dụng trung bình; FP Lite® hoàn thành trong vài giờ với sai số thống kê được kiểm chứng.
*Vai trò:* Phá vỡ rào cản "FP quá phức tạp" — cho phép tổ chức bắt đầu đo size ngay mà không cần xây dựng đội chuyên gia FP lớn.

---

**Software Development Methodology — SDM (Phương pháp phát triển phần mềm)**
Framework có cấu trúc cho quá trình phát triển phần mềm — bao gồm Waterfall, Agile, Spiral và các biến thể.
*Ví dụ:* Trong data Chapter 10, "Used SDM" cho productivity 5.3 FP/PM vs "No SDM" 12.1 — nhưng đây là correlation do project selection bias, không phải bằng chứng SDM xấu.
*Vai trò:* Một trong các biến qualitative được phân tích để hiểu impact của process choices lên performance — phải kiểm soát các biến khác khi so sánh.

---

**Baseline Initiative (Sáng kiến thiết lập đường cơ sở)**
Chương trình có cấu trúc để thu thập, phân tích, và báo cáo data hiệu suất từ một tập hợp dự án đại diện — nhằm tạo ra điểm tham chiếu cho improvement tracking.
*Ví dụ:* Chọn 15–20 dự án hoàn thành trong 12 tháng gần nhất, đếm FP, thu thập effort/duration/defects, thực hiện qualitative survey → baseline hoàn chỉnh trong 2–3 tháng.
*Vai trò:* Xuất phát điểm không thể thiếu trước khi so sánh với industry benchmark (Chapter 11) hoặc track improvement (Chapter 12).


---

!!! info "Nguồn gốc"
    `pdf_md/the-business-value-of-it-managing-risks-optimizing-performance-and-measuring-results-auerbach-publications-2008/guide_ai/18_chapter-10-is-it-operating-effectively_guide.md`
