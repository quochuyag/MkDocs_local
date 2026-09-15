---
title: 'Hướng Dẫn Học Tập: Thiết Kế Metrics'
course: 07-sach-va-tai-lieu
source: pdf_md/managing-it-performance-to-create-business-value/guide_ai/06_chapter-3-designing-metrics_guide.md
---

# Hướng Dẫn Học Tập: Thiết Kế Metrics

**Nguồn:** Managing IT Performance to Create Business Value — Chapter 3  
**Ngày tạo:** 2026-04-26  
**Thời gian học ước tính:** 70–85 phút

---

## 🎯 Mục tiêu học tập

Sau khi hoàn thành chương này, người học có thể:

- **Hiểu** tại sao metric quan trọng và vượt qua các lý do phổ biến mà nhân viên đưa ra để tránh bị đo lường
- **Mô tả** 10 tiêu chí của một metric hiệu quả và áp dụng để đánh giá chất lượng của một chỉ số cụ thể
- **Áp dụng** phương pháp Analytic Hierarchy Process (AHP) để ưu tiên và chọn lọc metrics cho Balanced Scorecard
- **Phân biệt** vai trò IT là "Service Provider" so với "Strategic Partner" và ý nghĩa của sự khác biệt này
- **Tính toán** ROI, NPV, BCR và sử dụng Earned Value Management (EVM) để đánh giá hiệu suất dự án
- **Đánh giá** khi nào nên dùng hard data hay soft data trong phân tích ROI

---

## 📋 Tóm tắt nội dung chính

Chương 3 giải quyết câu hỏi thực tiễn cốt lõi: làm thế nào chọn và thiết kế đúng metrics cho tổ chức? Điểm khởi đầu là phá vỡ 5 lý do phổ biến nhất mà nhân viên đưa ra để tránh bị đo lường: "không thể đo được," "không công bằng," "sẽ bị so sánh bất công," "kết quả sẽ bị dùng chống lại chúng tôi," và "không có dữ liệu."

Một **metric tốt** phải thỏa mãn 10 tiêu chí: Results-oriented, Important, Reliable, Useful, Quantitative, Realistic, Cost-effective, Easy to interpret, Comparable, và Credible. Quy trình chuẩn để triển khai benchmarking metrics gồm 6 bước: chọn quy trình, xác định hiệu suất hiện tại, xác định hiệu suất mong muốn, tính performance gap, thiết kế action plan, và striving for continuous improvement.

**Analytic Hierarchy Process (AHP)** là phương pháp khoa học để chọn và trọng số hóa metrics. Thay vì chọn ngẫu nhiên, AHP dùng so sánh cặp đôi (pairwise comparisons) theo thang 1–9 để tính local weight (quan trọng trong category) và global weight (quan trọng so với toàn bộ mục tiêu). Kết quả: mỗi metric có trọng số toàn cục (global outcome = local × local category weight) để ưu tiên theo chiến lược.

**IT Scorecard** là phiên bản Balanced Scorecard được điều chỉnh cho bộ phận IT (thường là nhà cung cấp dịch vụ nội bộ, không phải bên ngoài). Bốn góc nhìn IT: User Orientation (giá trị cho end-user), Business Value (đóng góp vào kinh doanh), Internal Processes (vận hành hiệu quả), và Future Readiness (sẵn sàng cho tương lai). Mục tiêu chiến lược: CIO phải định vị IT là **Strategic Partner** (IT gắn với tăng trưởng kinh doanh, không tách rời), không chỉ là Service Provider (IT như chi phí cần kiểm soát).

**Financial Metrics** bao gồm: Cost-Benefit Analysis (so sánh chi phí và lợi ích tangible + intangible), BCR (Benefit-Cost Ratio = Benefits/Cost), Break-even Analysis (thời điểm lợi ích bằng chi phí), ROI = (Benefits − Costs)/Costs, NPV (giá trị hiện tại ròng theo time value of money), IRR (tỷ suất chiết khấu để NPV = 0), và EVM (Earned Value Management đo giá trị công việc thực tế vs. chi phí). Hard data (output, time, quality, costs) dễ tính; soft data (morale, turnover, loyalty) khó nhưng cần thiết cho bức tranh đầy đủ.

---

## 🔑 Khái niệm quan trọng

| Khái niệm | Định nghĩa | Tại sao quan trọng | Ví dụ | Liên quan đến |
|---|---|---|---|---|
| **Analytic Hierarchy Process (AHP)** | Framework logic để tổ chức dữ liệu thành hệ thống phân cấp, dùng so sánh cặp đôi để tính trọng số tương đối của từng metric | Cho phép nhiều người ra quyết định nhất quán, minh bạch về độ ưu tiên metrics — không dựa vào cảm tính | AHP tính: Market Share (Innovation) = 0.40 × 0.32 = 0.128 là metric quan trọng nhất | Balanced Scorecard, Metric Selection |
| **Performance Gap** | Khoảng cách giữa hiệu suất hiện tại và hiệu suất mong muốn; phân loại theo nguyên nhân: people, process, technology, culture | Xác định đúng gap mới có thể ưu tiên đúng action plan | Công ty đang ở 75% SLA, mục tiêu 99% → gap 24% do thiếu automation (technology) | Benchmarking, Action Plan |
| **IT Strategic Partner** | Vai trò mà IT không thể tách rời khỏi kinh doanh; ngân sách IT được quyết định bởi chiến lược kinh doanh, không phải benchmark bên ngoài | Khi IT là Strategic Partner, CIO có tiếng nói ngang C-level; IT được coi là đầu tư, không phải chi phí | Bảng so sánh: IT là investment to manage vs. IT là expense to control | IT Scorecard, Business Value |
| **Return on Investment (ROI)** | (Benefits − Costs) / Costs × 100%; đo lợi tức thu được sau khi hoàn vốn | Chỉ số được quản lý yêu thích nhất; trả lời câu hỏi "đầu tư này có đáng không?" | Đầu tư $500K, thu lợi $700K: ROI = ($700K−$500K)/$500K = 40% | NPV, Break-even, EVM |
| **Net Present Value (NPV)** | Giá trị hiện tại ròng: chiết khấu dòng tiền tương lai về giá trị hiện tại, thừa nhận time value of money | Phù hợp với đầu tư IT kéo dài nhiều năm; NPV > 0 là dấu hiệu chấp nhận đầu tư | Đầu tư $1M có NPV tiết kiệm $1.5M → ROI = 50% (hoặc 150% tính theo NPV/Cost) | ROI, IRR |
| **Earned Value Management (EVM)** | Đo hiệu suất dự án qua Cost Performance Index (CPI) = Earned Value / Actual Cost; CPI < 1 nghĩa là tiêu nhiều hơn giá trị tạo ra | Cảnh báo sớm vấn đề dự án khi chỉ 20% hoàn thành — thay vì phát hiện quá muộn | CPI = 0.8 khi dự án 20% hoàn thành → tổng chi phí thực tế dự kiến = $1B/0.8 = $1.25B | Financial Metrics, Project Control |
| **Hard vs. Soft Data** | Hard data: output, time, quality, costs — dễ đo và tính bằng tiền. Soft data: morale, turnover, loyalty — khó đo nhưng phản ánh sức khỏe tổ chức | ROI chỉ dựa hard data bỏ qua nhiều giá trị thực; cần kết hợp cả hai để đánh giá toàn diện | Hard: số đơn hàng xử lý/giờ. Soft: mức độ hài lòng nhân viên sau triển khai ERP | ROI Calculation, Performance Measurement |

---

## 🌍 Ví dụ thực tế & Case Study

### Case Study 1: ERP Balanced Scorecard — Rosemann và Wiese

**Bối cảnh:** Triển khai ERP là một trong những dự án IT phức tạp và tốn kém nhất. Hầu hết tổ chức chỉ theo dõi tài chính và quy trình kinh doanh.

**Vấn đề:** Thiếu góc nhìn toàn diện dẫn đến bỏ qua các rủi ro quan trọng về khách hàng, đổi mới, và học hỏi trong suốt vòng đời ERP.

**Giải pháp:** Rosemann và Wiese thêm một góc nhìn thứ 5 — **Project Perspective** — vào Balanced Scorecard chuẩn. Kết quả: ERP Scorecard gồm 5 góc nhìn: Financial (Total Cost of Ownership), Project (Critical path, milestones), Internal Processes (Processing time trước/sau ERP), Customer (Linkage of customers to business processes), Innovation & Learning (Alternative process paths, qualification index of developers).

**Kết quả:** Mối quan hệ nhân quả rõ ràng: "Customer satisfaction" ảnh hưởng đến TCO, total project time, fit với ERP solution, và user suggestions cùng một lúc — cho phép phát hiện vấn đề sớm hơn.

**Bài học:** Không có one-size-fits-all scorecard — cần điều chỉnh theo loại dự án và bối cảnh tổ chức.

---

### Case Study 2: New York Stock Exchange — Nguy cơ của benchmarking theo phong trào

**Bối cảnh:** Tác giả chia sẻ kinh nghiệm khi làm việc tại NYSE. Chủ tịch thường xuyên yêu cầu đội ngũ làm theo "xu hướng quản lý mới nhất" từ Motorola, GE, Facebook, Google.

**Vấn đề:** Mỗi tổ chức có bối cảnh khác nhau. Áp dụng benchmark của Motorola hay GE vào NYSE mà không hiểu rõ môi trường kinh doanh cụ thể dẫn đến các chỉ số vô nghĩa hoặc gây hại.

**Giải pháp (đúng):** Trước khi benchmark, cần thực sự điều tra và hiểu rõ: (a) môi trường kinh doanh hiện tại, (b) tác động của các quy trình kinh doanh cụ thể đến hiệu suất tổng thể, (c) lý do tại sao các công ty hàng đầu kia thành công với metrics đó.

**Bài học:** Benchmarking là issue-specific — context matters. Chọn sai đối tượng benchmark hoặc áp dụng metric không phù hợp với bối cảnh sẽ lãng phí nguồn lực và gây nhầm lẫn chiến lược.

---

### Case Study 3: ROI phân tích cho hệ thống IT — Ứng dụng thực tế tại Việt Nam (🇻🇳)

**Bối cảnh:** Một ngân hàng Việt Nam muốn thay thế hệ thống xử lý khoản vay cũ bằng hệ thống mới hoặc thuê ngoài.

**Vấn đề:** Có 3 lựa chọn: viết lại từ đầu, sửa đổi hệ thống hiện tại, hoặc outsource. Mỗi lựa chọn có chi phí và lợi ích khác nhau — cả tangible (thời gian xử lý, số lỗi) và intangible (sự hài lòng khách hàng, compliance).

**Giải pháp:** Áp dụng 4 loại ROI worksheets: (1) Initial Benefits (tiết kiệm giờ học hệ thống, giảm giám sát), (2) Continuing Benefits (giảm giờ làm thêm, giảm lỗi), (3) Quality Benefits (ít giao dịch bị từ chối hơn), (4) Other Benefits (giảm nghỉ việc, tăng morale). Dùng EVM để theo dõi thực tế vs. kế hoạch trong suốt triển khai.

**Kết quả kỳ vọng:** Break-even point có thể tính chính xác cho từng lựa chọn — ban quản lý chọn phương án có break-even ngắn nhất.

**Bài học 🇻🇳:** Các ngân hàng và công ty fintech Việt Nam thường quyết định đầu tư IT dựa trên "cảm tính" hoặc so sánh giá ban đầu. Áp dụng ROI + NPV + EVM tạo ra ngôn ngữ chung giữa IT và Finance — tăng khả năng được phê duyệt ngân sách IT chiến lược.

---

## 📊 Sơ đồ & Bảng tổng hợp

### Bảng 1: IT Service Provider vs. Strategic Partner

| Chiều | Service Provider | Strategic Partner |
|---|---|---|
| Mục đích IT | Hiệu quả vận hành | Tăng trưởng kinh doanh |
| Ngân sách IT | Dựa trên benchmark bên ngoài | Dựa trên chiến lược kinh doanh |
| Mối quan hệ | IT có thể tách rời khỏi kinh doanh | IT không thể tách rời khỏi kinh doanh |
| Nhìn nhận chi tiêu | Chi phí cần kiểm soát | Đầu tư cần quản lý |
| Vai trò IT Manager | Chuyên gia kỹ thuật | Người giải quyết vấn đề kinh doanh |

### Bảng 2: Các kỹ thuật tính ROI

| Kỹ thuật | Phạm vi | Ưu điểm | Nhược điểm |
|---|---|---|---|
| Simple ROI | Một dự án, ngắn hạn | Dễ tính, trực quan | Bỏ qua time value of money |
| NPV | Nhiều năm | Tính đến giá trị thời gian của tiền | Cần ước tính discount rate chính xác |
| IRR | So sánh nhiều dự án | Hữu ích khi ngân sách hạn chế | Không cung cấp tiêu chí quyết định rõ ràng |
| EVM (CPI) | Dự án đang chạy | Cảnh báo sớm khi vừa 20% hoàn thành | Chủ yếu dùng cho dự án chính phủ |
| TCO | Chi phí toàn vòng đời | Bộc lộ chi phí ẩn (support, maintenance) | Phức tạp, cần dữ liệu dài hạn |

### Sơ đồ: AHP Global Outcome Worksheet (ví dụ rút gọn)

```
Mục tiêu chiến lược: Differentiation Strategy

Category Weights:         Local Weight × Category = Global Weight
Innovation & Learning     Market Share: 0.40 × 0.32 = 0.128  ← cao nhất
(0.32)                    New Products: 0.35 × 0.32 = 0.112

Financial (0.22)          Cash Flow ROI: 0.40 × 0.22 = 0.088
                          Residual Income: 0.32 × 0.22 = 0.070

Customer (0.21)           QFD Score: 0.42 × 0.21 = 0.088
                          Revenue: 0.20 × 0.21 = 0.042  ← thấp nhất
```

---

## ❓ Câu hỏi ôn tập

**Câu 1 (Nhớ lại):** Kể 5 trong số 10 tiêu chí của một metric hiệu quả và giải thích ngắn gọn từng tiêu chí.

💡 *Gợi ý: Metric tốt phải đo đúng thứ, đo được, hữu ích, rẻ để thu thập, và có thể so sánh.*

📝 *Đáp án:* Năm tiêu chí tiêu biểu: (1) **Results-oriented** — tập trung vào kết quả mong muốn, không chỉ đầu ra; (2) **Reliable** — thông tin chính xác, nhất quán theo thời gian; (3) **Cost-effective** — giá trị của metric đủ để biện minh cho chi phí thu thập dữ liệu; (4) **Comparable** — có thể dùng để benchmark với tổ chức khác, cả nội bộ và bên ngoài; (5) **Credible** — người dùng tin tưởng vào tính hợp lệ của dữ liệu. Thiếu bất kỳ tiêu chí nào, metric có thể dẫn đến quyết định sai hoặc bị từ chối bởi người dùng.

---

**Câu 2 (Nhớ lại):** Phân biệt Hard Data và Soft Data trong phân tích ROI. Cho 2 ví dụ mỗi loại.

💡 *Gợi ý: Hard data có thể đếm và quy ra tiền trực tiếp; soft data liên quan đến con người và tâm lý.*

📝 *Đáp án:* **Hard data** là dữ liệu định lượng trực tiếp, dễ thu thập và quy đổi thành giá trị tiền tệ. Ví dụ: số đơn vị sản phẩm lắp ráp/giờ, thời gian hoàn thành dự án so với kế hoạch. **Soft data** là dữ liệu liên quan đến hành vi, thái độ, và tâm lý — khó đo và khó quy đổi thành tiền. Ví dụ: mức độ hài lòng nhân viên (employee satisfaction score), tần suất vắng mặt (absenteeism). Một ROI đầy đủ cần kết hợp cả hai: hard data cung cấp bằng chứng tài chính, soft data phản ánh sức khỏe tổ chức dài hạn. Bỏ qua soft data có thể dẫn đến đầu tư IT "thành công trên giấy" nhưng thất bại về mặt con người.

---

**Câu 3 (Hiểu):** Tại sao IT cần định vị mình là "Strategic Partner" thay vì "Service Provider"? Điều này ảnh hưởng như thế nào đến cách thiết kế IT Scorecard?

💡 *Gợi ý: So sánh cách ngân sách được quyết định và cách IT managers được nhìn nhận trong hai vai trò.*

📝 *Đáp án:* Khi IT là Service Provider, ngân sách bị giới hạn bởi benchmark bên ngoài, IT bị coi là chi phí cần cắt giảm, và IT managers chỉ là chuyên gia kỹ thuật — không có tiếng nói trong chiến lược kinh doanh. Khi IT là Strategic Partner, ngân sách được dẫn dắt bởi chiến lược kinh doanh, IT được coi là đầu tư sinh lời, và IT managers là người giải quyết vấn đề kinh doanh ngồi cùng bàn với C-suite. Ảnh hưởng đến IT Scorecard: thay vì 4 góc nhìn truyền thống (Financial, Customer, Internal Process, Learning/Growth), IT Scorecard điều chỉnh thành: User Orientation (end-user view), Business Value (management view), Internal Processes (operations view), và Future Readiness (innovation view) — tất cả đều nhấn mạnh đóng góp cho kinh doanh, không chỉ vận hành kỹ thuật.

---

**Câu 4 (Hiểu):** Giải thích Earned Value Management (EVM) và tại sao CPI là chỉ số quan trọng. Nếu CPI = 0.75 khi dự án hoàn thành 25%, điều đó có nghĩa gì và CIO nên làm gì?

💡 *Gợi ý: CPI đo "giá trị kiếm được" so với "tiền đã chi" — CPI < 1 là dấu hiệu xấu.*

📝 *Đáp án:* EVM đo hiệu suất dự án bằng cách so sánh giá trị công việc thực sự hoàn thành ("earned value") với chi phí thực tế đã bỏ ra. CPI = Earned Value / Actual Cost — nếu CPI < 1, bạn đang chi nhiều hơn giá trị tạo ra. Nếu CPI = 0.75 khi dự án hoàn thành 25%, điều này có nghĩa: với mỗi $1 chi ra, chỉ tạo ra $0.75 giá trị. Nếu ngân sách ban đầu là $2M, tổng chi phí thực tế dự kiến = $2M / 0.75 = ~$2.67M — vượt $670K. Đây là cảnh báo sớm có giá trị: CIO còn thời gian điều chỉnh (cắt giảm scope, tối ưu resources, hoặc đàm phán lại deadline) thay vì phát hiện quá muộn khi dự án 90% hoàn thành.

---

**Câu 5 (Áp dụng):** Một công ty FMCG Việt Nam muốn đánh giá đầu tư vào hệ thống WMS (Warehouse Management System) trị giá $300K. Hệ thống được kỳ vọng giảm 30% lỗi xuất hàng và 15% thời gian làm thêm. Thiết kế framework ROI cơ bản cho dự án này.

💡 *Gợi ý: Phân loại lợi ích thành Initial (ban đầu) và Continuing (liên tục), bao gồm cả tangible và intangible.*

📝 *Đáp án:* **Costs:** $300K triển khai + ước tính $30K/năm maintenance = TCO. **Initial Benefits** (6 tháng đầu): giảm thời gian đào tạo nhân viên kho (ước tính $20K), giảm giám sát cần thiết ($10K). **Continuing Benefits** (hàng năm): tiết kiệm từ giảm 30% lỗi xuất hàng (tính: số lỗi/tháng × chi phí xử lý lỗi × 12), tiết kiệm từ giảm 15% overtime ($X/giờ × giờ OT giảm × 52 tuần). **Quality Benefits:** giảm hàng trả về và chi phí xử lý khiếu nại. **Soft Benefits (intangible):** tăng uy tín với retailers (khó quy thành tiền nhưng quan trọng). **Break-even:** ROI = (tổng lợi ích − $300K) / $300K. Nếu tổng lợi ích năm 1 = $180K, tiết kiệm liên tục = $200K/năm → break-even tại tháng 18–20. Dùng NPV để điều chỉnh cho 3 năm tiếp theo với discount rate 10%.

---

## 💡 Ghi nhớ nhanh

- ✅ Mọi thứ đều có thể đo lường nếu có đủ động lực và sáng tạo — lý do "không thể đo" thường là lý do tránh trách nhiệm
- ✅ AHP biến quá trình chọn metrics từ "cảm tính" thành "khoa học" — minh bạch, nhất quán, và có sự tham gia của nhiều bên
- ✅ CPI trong EVM là "đèn cảnh báo sớm" — giá trị nhất khi dự án còn 20–25% hoàn thành
- ✅ IT phải trở thành Strategic Partner để có tiếng nói trong chiến lược — ngôn ngữ chung là business value, không phải technical specs
- ⚠️ Benchmark metrics của Motorola/GE không tự động phù hợp với công ty của bạn — context and industry matter
- ⚠️ ROI chỉ dựa trên hard data bỏ qua morale, turnover, loyalty — những thứ thường quyết định thành bại dài hạn
- 🔗 Chương tiếp theo (Chapter 4) đi sâu vào việc **xây dựng chương trình đo lường phần mềm** — áp dụng GQM paradigm và SEI CMM để thiết lập metrics gắn với mục tiêu tổ chức

---

## 📖 Giải thích thuật ngữ chuyên ngành

**Analytic Hierarchy Process (AHP)** — Quy trình phân tích thứ bậc  
Framework logic sử dụng so sánh cặp đôi (pairwise comparisons) theo thang 1–9 để tính trọng số tương đối của các lựa chọn trong một quyết định phức tạp.  
*Ví dụ:* Nhóm quản lý dùng AHP để quyết định metrics nào quan trọng nhất trong Balanced Scorecard của công ty — kết quả là trọng số toàn cục (global weight) cho mỗi metric.  
*Tại sao quan trọng:* Ngăn chặn việc loại bỏ metrics quan trọng quá sớm và đảm bảo sự đồng thuận có căn cứ khoa học trong nhóm.

---

**Performance Gap** — Khoảng cách hiệu suất  
Sự chênh lệch giữa hiệu suất hiện tại (where you are) và hiệu suất mong muốn (where you want to be), được phân loại theo nguyên nhân: người, quy trình, công nghệ, hoặc văn hóa.  
*Ví dụ:* Thời gian phát triển ứng dụng hiện tại là 6 tháng, mục tiêu là 3 tháng → gap 3 tháng do thiếu automation và quy trình CI/CD (technology & process gap).  
*Tại sao quan trọng:* Không xác định đúng nguyên nhân gap dẫn đến action plan sai — đầu tư vào training khi vấn đề thực sự là quy trình.

---

**Earned Value Management (EVM)** — Quản lý giá trị kiếm được  
Phương pháp đo lường hiệu suất dự án bằng cách so sánh giá trị công việc thực sự hoàn thành với chi phí thực tế và kế hoạch ban đầu. Chỉ số chính: CPI = Earned Value / Actual Cost.  
*Ví dụ:* Dự án ngân sách $1B, CPI = 0.8 khi hoàn thành 20% → dự báo tổng chi phí = $1.25B. Microsoft Project hỗ trợ tính EVM.  
*Tại sao quan trọng:* Phát hiện vấn đề chi phí khi còn 80% dự án còn lại để điều chỉnh — thay vì phát hiện khi đã quá muộn.

---

**Total Cost of Ownership (TCO)** — Tổng chi phí sở hữu  
Chi phí đầy đủ của một hệ thống IT bao gồm không chỉ chi phí mua ban đầu mà còn cả chi phí hỗ trợ, bảo trì, đào tạo, và vận hành trong suốt vòng đời.  
*Ví dụ:* Một máy chủ giá $10K nhưng TCO trong 5 năm = $35K khi tính thêm điện, hỗ trợ kỹ thuật, bảo trì, và chi phí downtime.  
*Tại sao quan trọng:* Quyết định IT dựa trên giá mua ban đầu thường bị "sốc" vì chi phí ẩn — TCO cho bức tranh thực sự.

---

**Benefit-Cost Ratio (BCR)** — Tỷ lệ lợi ích trên chi phí  
BCR = Benefits / Costs. Nếu BCR > 1, dự án tạo ra nhiều lợi ích hơn chi phí và được chấp nhận; nếu BCR < 1, chi phí vượt lợi ích.  
*Ví dụ:* Hệ thống CRM $200K mang lại $350K lợi ích (giảm churning + tăng cross-sell) → BCR = 1.75 → nên đầu tư.  
*Tại sao quan trọng:* Đơn giản hơn ROI để so sánh nhiều dự án cùng lúc trong portfolio management.

---

**Net Present Value (NPV)** — Giá trị hiện tại ròng  
Tổng giá trị hiện tại của tất cả dòng tiền tương lai (lợi ích trừ chi phí) được chiết khấu về thời điểm hiện tại bằng một tỷ lệ chiết khấu phù hợp. NPV > 0 = dự án khả thi.  
*Ví dụ:* $1 nhận được sau 3 năm chỉ có giá trị hiện tại ~$0.75 nếu discount rate 10%/năm. NPV tính tổng hợp tất cả các năm.  
*Tại sao quan trọng:* Bắt buộc khi đầu tư IT kéo dài nhiều năm — simple ROI bỏ qua fact rằng tiền hôm nay có giá trị hơn tiền ngày mai.

---

**ERP Balanced Scorecard** — Thẻ điểm cân bằng cho ERP  
Phiên bản Balanced Scorecard được mở rộng bởi Rosemann và Wiese để đánh giá cả quá trình triển khai ERP (thêm Project Perspective) lẫn vận hành liên tục sau triển khai.  
*Ví dụ:* Trong quá trình triển khai: số lỗi nhập liệu, thời gian xử lý đơn hàng trước/sau ERP, số giờ đào tạo người dùng. Sau triển khai: average system uptime, tỷ lệ giao dịch không hoàn thành đúng lịch.  
*Tại sao quan trọng:* ERP là khoản đầu tư lớn nhất của nhiều doanh nghiệp — đo lường sai hoặc thiếu dẫn đến không phát hiện được ROI thực sự.


---

!!! info "Nguồn gốc"
    `pdf_md/managing-it-performance-to-create-business-value/guide_ai/06_chapter-3-designing-metrics_guide.md`
