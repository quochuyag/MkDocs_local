---
title: Chương 14 — IT Nên Quản Lý Rủi Ro Như Thế Nào?
course: 07-sach-va-tai-lieu
source: pdf_md/the-business-value-of-it-managing-risks-optimizing-performance-and-measuring-results-auerbach-publications-2008/guide_ai/23_chapter-14-how-should-it-manage-risk_guide.md
---

# Chương 14 — IT Nên Quản Lý Rủi Ro Như Thế Nào?

**Sách:** The Business Value of IT — Managing Risks, Optimizing Performance, and Measuring Results (Auerbach Publications, 2008)
**Ngày tạo:** 2026-04-26
**Thời gian học ước tính:** 40–50 phút

---

## 🎯 Mục tiêu học tập

- Hiểu định nghĩa rủi ro và phân biệt các loại rủi ro chính trong môi trường IT
- Mô tả quy trình risk assessment và các thành phần cơ bản của nó
- Áp dụng khái niệm vulnerability/threat pair để xác định rủi ro cụ thể
- Phân biệt physical security và information security trong bối cảnh IT
- Đánh giá tác động của SOX, HIPAA, và GLB Act đối với yêu cầu quản lý rủi ro của IT

---

## 📋 Tóm tắt nội dung chính

Chapter 14 cung cấp framework toàn diện về quản lý rủi ro IT, bao gồm: tại sao cần lập kế hoạch rủi ro, cách thực hiện risk assessment, mối liên hệ giữa rủi ro và bảo mật, và các luật pháp quan trọng đã định hình yêu cầu quản lý rủi ro ngày nay.

**Tại sao IT phải quản lý rủi ro?**

Trong thập kỷ qua, IT Providers đã trở thành người chịu trách nhiệm chính về rủi ro doanh nghiệp. Nguyên nhân: dữ liệu khách hàng và quyền riêng tư được lưu trữ bởi IT; tự động hóa khiến IT trở thành người bảo vệ tài sản then chốt; luật pháp mới yêu cầu hệ thống giám sát compliance; giao dịch internet tạo ra mối đe dọa mới hàng ngày.

Ví dụ điển hình: Vụ TJX Companies (2006) — kẻ tấn công đã xâm nhập hệ thống từ năm 2003 mà không bị phát hiện suốt 3 năm, đánh cắp dữ liệu thẻ tín dụng của hàng nghìn khách hàng. Vụ việc tiêu tốn nguồn lực khổng lồ để xử lý và phục hồi niềm tin.

**Năm loại rủi ro chính**

Rủi ro tài chính (Financial risk): tổn thất tiền tệ — ví dụ Microsoft phải dự trữ $1 tỷ cho lỗi Xbox 360. Rủi ro pháp lý (Legal risk): kiện tụng, arbitration. Rủi ro danh tiếng (Reputation risk): mất niềm tin của khách hàng — khó lấy lại hơn là tổn thất tiền tệ. Rủi ro nhân sự (Personnel risk): mất nhân viên chủ chốt và kiến thức quan trọng. Rủi ro vật lý/môi trường (Physical/Environmental risk): thiên tai, mất điện, an ninh vật lý.

**Quy trình Risk Assessment**

Risk assessment bắt đầu bằng việc xác định: chức năng của department là gì? Tài sản nào quan trọng? Lỗ hổng (vulnerability) nào tồn tại? Mối đe dọa (threat) nào có thể khai thác lỗ hổng đó? Kết quả là các cặp vulnerability/threat pair, được đánh giá theo likelihood of occurrence và potential impact. Rủi ro được biểu diễn trên ma trận 2x2 (impact vs probability) để ưu tiên xử lý. Những rủi ro có high impact + high probability cần được xử lý với risk mitigation plans chi tiết.

**Security và Risk Planning**

Security (bảo mật) là triển khai các biện pháp để giảm thiểu rủi ro đã xác định. Gồm hai mảng: Physical security (khóa cửa, rào cản, access control, camera) và Information security (bảo mật thông tin — confidentiality, integrity, availability). Điểm thường bị bỏ qua nhất là account/password management — đây là rào cản đơn giản nhất nhưng thường bị xem nhẹ nhất.

**Luật pháp quan trọng**

Ba luật định hình yêu cầu quản lý rủi ro IT hiện đại: Sarbanes-Oxley Act 2002 (SOX) yêu cầu executives của công ty đại chúng xác nhận hàng quý rằng internal controls đang hoạt động hiệu quả. HIPAA 1996 thiết lập tiêu chuẩn quốc gia về bảo vệ thông tin y tế cá nhân. Gramm-Leach-Bliley Act 1999 (GLB) bảo vệ thông tin tài chính cá nhân qua Financial Privacy Rule, Safeguards Rule, và chống pretexting.

---

## 🔑 Khái niệm quan trọng

| Khái niệm | Định nghĩa | Tại sao quan trọng | Ví dụ | Liên quan đến |
|---|---|---|---|---|
| Risk | Khả năng xảy ra sự kiện không mong muốn gây tổn thất | Mọi quyết định IT đều có rủi ro cần được xem xét | Mất dữ liệu khách hàng | Risk Assessment, Threat |
| Vulnerability | Điểm yếu trong hệ thống có thể bị khai thác | Là "cửa hậu" mà threat có thể xâm nhập | Cựu nhân viên vẫn có access vào hệ thống | Threat, Security |
| Threat | Nguy cơ có thể khai thác vulnerability để gây tổn thất | Không phải mọi vulnerability đều bị exploit, nhưng mọi threat đều cần một vulnerability | Hacker tấn công database | Vulnerability/Threat Pair |
| Risk Assessment | Quy trình đánh giá toàn diện các rủi ro của tổ chức | Là bước đầu tiên và bắt buộc trong risk management | Lập bảng đánh giá tất cả threats của một department | Risk Plan, Mitigation |
| Disaster Recovery Plan | Kế hoạch chi tiết các bước phục hồi hệ thống sau sự kiện thảm họa | Đảm bảo business có thể tiếp tục sau sự cố nghiêm trọng | Kế hoạch khôi phục data center sau lũ lụt | Risk Mitigation, BCP |
| SOX (Sarbanes-Oxley) | Luật Mỹ yêu cầu công ty đại chúng chứng minh internal controls hoạt động | Executives phải ký xác nhận hàng quý — rủi ro cá nhân cao | CEO/CIO ký quarterly attestation | Compliance, Governance |
| HIPAA | Luật bảo vệ thông tin y tế cá nhân tại Mỹ | Mọi tổ chức xử lý dữ liệu y tế phải tuân thủ | Bệnh viện phải mã hóa hồ sơ bệnh nhân | Privacy, Compliance |
| Information Security | Bảo vệ thông tin khỏi truy cập, sử dụng, tiết lộ trái phép | Dữ liệu là tài sản — mất dữ liệu = mất tiền + mất niềm tin | Mã hóa dữ liệu thẻ tín dụng | CIA triad |

---

## 🌍 Ví dụ thực tế & Case Study

### Case Study 1: TJX Companies — Bài học về hậu quả của việc thiếu risk planning

**Bối cảnh:** TJX Companies (sở hữu T.J. Maxx, Marshalls, Home Goods) là một trong các chuỗi bán lẻ lớn nhất nước Mỹ, xử lý hàng triệu giao dịch thẻ tín dụng mỗi ngày.

**Vấn đề:** Tháng 12/2006, TJX phát hiện kẻ tấn công đã xâm nhập hệ thống và đánh cắp dữ liệu thẻ tín dụng của khách hàng. Điều tra cho thấy breach đã xảy ra từ tháng 1/2003 — suốt 3 năm không bị phát hiện. Dữ liệu bị truy cập không được mã hóa, controls không đủ mạnh.

**Giải pháp (phản ứng):** TJX công bố thông tin minh bạch, thay CEO, tăng cường security, lập hotline tại 3 quốc gia cho khách hàng bị ảnh hưởng.

**Kết quả:** Giá cổ phiếu đi ngang trong khi trước đó tăng 20% trong 6 tháng. Chi phí xử lý khổng lồ — thời gian, tiền bạc, danh tiếng. Tính đến tháng 7/2007, letter xin lỗi từ CEO vẫn còn active trên website.

**Bài học:** 🇻🇳 Tương tự các vụ lộ thông tin khách hàng tại Việt Nam (ngân hàng, sàn thương mại điện tử) — chi phí của breach LUÔN cao hơn chi phí phòng ngừa. Điều đáng sợ nhất không phải là tổn thất tài chính trực tiếp mà là mất niềm tin của khách hàng — rất khó lấy lại.

---

### Case Study 2: Microsoft Xbox 360 — Financial Risk Planning chủ động

**Bối cảnh:** Microsoft ra mắt Xbox 360 — một trong những sản phẩm game console lớn nhất lịch sử.

**Vấn đề:** Năm 2007, Microsoft phát hiện một lỗi hardware phổ biến (RROD — Red Ring of Death) ảnh hưởng đến hàng triệu máy Xbox 360.

**Giải pháp:** Microsoft đã chủ động dự trữ hơn $1 tỷ USD để chi trả chi phí sửa chữa và thay thế cho khách hàng bị ảnh hưởng.

**Kết quả:** Dù tốn kém, việc xử lý minh bạch và nhanh chóng giúp Microsoft giữ được lòng tin của người dùng Xbox.

**Bài học:** Financial risk planning (dự phòng ngân sách cho rủi ro) không phải là bi quan — đây là quản lý chuyên nghiệp. Tổ chức IT cần có contingency budget cho các rủi ro đã được xác định trong risk assessment.

---

### Case Study 3: Tuân thủ luật bảo vệ dữ liệu — Bài học cho IT Việt Nam

**Bối cảnh:** 🇻🇳 Nghị định 13/2023/NĐ-CP về bảo vệ dữ liệu cá nhân (PDPD) có hiệu lực tại Việt Nam từ tháng 7/2023, tương tự GDPR của châu Âu và các điều khoản trong GLB Act/HIPAA.

**Vấn đề:** Nhiều doanh nghiệp IT Việt Nam chưa có chính sách xử lý dữ liệu cá nhân rõ ràng, chưa có data breach notification process, và chưa thực hiện risk assessment theo yêu cầu pháp lý.

**Giải pháp:** Áp dụng framework risk assessment trong chương này: xác định loại dữ liệu đang lưu trữ, ai có quyền truy cập, vulnerability nào tồn tại, lập vulnerability/threat pairs, và xây dựng risk mitigation plans.

**Kết quả/Bài học:** Legal risk từ vi phạm PDPD có thể dẫn đến phạt tiền và ảnh hưởng danh tiếng. Việc proactive thực hiện risk assessment giúp doanh nghiệp vừa tuân thủ pháp luật, vừa xây dựng nền tảng bảo mật tốt hơn.

---

## 📊 Sơ đồ & Bảng tổng hợp

### Ma trận đánh giá rủi ro (Risk Evaluation Matrix)

| | Probability thấp | Probability cao |
|---|---|---|
| **Impact cao** | Lập risk plan — có thể xảy ra bất ngờ | Ưu tiên cao nhất — cần kế hoạch chi tiết và đội chuyên trách |
| **Impact thấp** | Chấp nhận hoặc chỉ theo dõi | Kiểm soát để giảm tần suất xảy ra |

### So sánh ba luật pháp quan trọng

| Luật | Năm | Đối tượng áp dụng | Yêu cầu chính với IT |
|---|---|---|---|
| SOX | 2002 | Công ty đại chúng Mỹ | Internal controls, quarterly attestation, audit trail |
| HIPAA | 1996 | Tổ chức y tế và đối tác xử lý PHI | Bảo vệ PHI, Privacy Rule, kiểm soát truy cập |
| GLB Act | 1999 | Tổ chức tài chính | Financial Privacy Rule, Safeguards Rule, chống pretexting |

### Quy trình Risk Assessment — Tóm tắt các bước

Xác định chức năng & tài sản → Liệt kê vulnerabilities → Xác định threats → Tạo Vulnerability/Threat Pairs → Đánh giá Likelihood & Impact → Vẽ Risk Matrix → Ưu tiên rủi ro → Lập Risk Mitigation Plans → Review hàng năm

---

## ❓ Câu hỏi ôn tập

**1. Định nghĩa vulnerability và threat. Cho một ví dụ về vulnerability/threat pair cụ thể.**

💡 Gợi ý: Vulnerability là điểm yếu, threat là nguy cơ khai thác điểm yếu đó. Hai yếu tố này cần có nhau để tạo thành rủi ro thực sự.

📝 Đáp án: Vulnerability (lỗ hổng) là điểm yếu trong hệ thống, quy trình, hoặc thiết kế có thể bị khai thác — ví dụ: "nhân viên đã nghỉ việc nhưng account chưa bị khóa." Threat (mối đe dọa) là tác nhân hoặc sự kiện có thể khai thác vulnerability đó — ví dụ: "cựu nhân viên truy cập dữ liệu proprietary từ mạng công ty." Cặp vulnerability/threat pair này chỉ ra một rủi ro cụ thể cần được kiểm soát. Ví dụ khác từ sách: Vulnerability = "internet application không xử lý opt-out của khách hàng" + Threat = "khách hàng không hài lòng tiếp tục nhận spam, vi phạm GLB Act" = rủi ro pháp lý.

---

**2. Tại sao risk management được coi là trách nhiệm chung của cả IT và business, không chỉ của IT?**

💡 Gợi ý: Ai là người hiểu rõ nhất quy trình và dữ liệu quan trọng của từng department?

📝 Đáp án: Risk management là trách nhiệm chung vì chỉ có người thực hiện công việc hàng ngày mới biết đầy đủ tài sản nào quan trọng, quy trình nào critical, và vulnerability nào tồn tại trong phạm vi của họ. IT có chuyên môn kỹ thuật về hệ thống, nhưng business departments biết rõ hơn về dữ liệu nào là mission-critical và việc mất access sẽ ảnh hưởng thế nào đến operations. Các tổ chức có risk management hiệu quả nhất (như Toyota, Johnson & Johnson theo sách) vận hành theo mô hình shared responsibility — mỗi department sở hữu và quản lý risk của mình, trong khi có một trung tâm tổng hợp và báo cáo lên board.

---

**3. Sarbanes-Oxley Act (SOX) đặt ra yêu cầu gì cụ thể cho IT Providers của các công ty đại chúng?**

💡 Gợi ý: SOX yêu cầu executives phải ký xác nhận điều gì hàng quý? Điều này tạo ra trách nhiệm như thế nào cho CIO?

📝 Đáp án: SOX yêu cầu executives (CEO, CFO) của các công ty đại chúng phải ký xác nhận hàng quý rằng internal controls của công ty đang hoạt động hiệu quả và "dưới sự kiểm soát." Đối với IT Providers, điều này có nghĩa là phải có audit trail đầy đủ cho các giao dịch tài chính, có risk/control matrices được lập và duy trì, self-assessment questionnaires, và audit programs. Thực tế là IT executives cũng phải ký xác nhận rằng IT operations đang under control — tạo ra accountability cá nhân trực tiếp. Nếu có vấn đề, executives có thể bị truy cứu trách nhiệm hình sự, không chỉ là trách nhiệm kinh doanh.

---

**4. Phân biệt physical security và information security. Tại sao một tổ chức cần cả hai?**

💡 Gợi ý: Một loại bảo vệ không gian vật lý, loại kia bảo vệ dữ liệu. Điều gì xảy ra nếu chỉ có một trong hai?

📝 Đáp án: Physical security bảo vệ không gian vật lý — ngăn chặn truy cập trái phép vào server rooms, data centers, và thiết bị phần cứng. Bao gồm: khóa cửa, fencing, electronic access control, camera giám sát, bảo vệ. Information security bảo vệ dữ liệu và hệ thống khỏi truy cập, sử dụng, hoặc tiết lộ trái phép — tập trung vào confidentiality, integrity, availability (CIA triad). Cần cả hai vì: physical security mà thiếu information security thì insider threat hoặc người được phép vào building vẫn có thể đánh cắp dữ liệu; information security mà thiếu physical security thì kẻ tấn công có thể lấy trộm ổ cứng trực tiếp, vô hiệu hóa mọi biện pháp phần mềm.

---

**5. Công ty bạn đang xử lý cả dữ liệu y tế bệnh nhân và dữ liệu tài chính khách hàng. Luật nào phải tuân thủ và IT cần làm gì trước tiên?**

💡 Gợi ý: Hai loại dữ liệu khác nhau → hai luật khác nhau. Nhưng bước đầu tiên trước khi tuân thủ bất kỳ luật nào là gì?

📝 Đáp án: Với dữ liệu y tế (Protected Health Information — PHI), phải tuân thủ HIPAA: kiểm soát ai được truy cập PHI, có audit trail cho mọi truy cập, tuân theo Privacy Rule về disclosure, và giới hạn aggregation dữ liệu y tế. Với dữ liệu tài chính, phải tuân thủ GLB Act: triển khai Safeguards Rule (bảo vệ thông tin tài chính khách hàng), Financial Privacy Rule (kiểm soát thu thập và chia sẻ dữ liệu), và có biện pháp chống pretexting. Nếu là công ty đại chúng, SOX cũng áp dụng thêm. Bước đầu tiên cho cả hai là thực hiện risk assessment toàn diện — xác định rõ dữ liệu nào đang lưu trữ ở đâu, ai có quyền truy cập, và vulnerability nào tồn tại. Từ đó mới lập được mitigation plans đúng trọng tâm.

---

## 💡 Ghi nhớ nhanh

- ✅ Rủi ro gồm 5 loại chính: Financial, Legal, Reputation, Personnel, Physical/Environmental
- ✅ Risk assessment = xác định vulnerability + threat pairs → đánh giá likelihood và impact → lập mitigation plan
- ✅ Disaster recovery plan là một loại risk mitigation plan — cần review và test ít nhất hàng năm
- ⚠️ Account/password management là biện pháp bảo mật cơ bản nhất nhưng thường bị xem nhẹ nhất — đừng để "cửa hàng xóm" trở thành lỗ hổng lớn nhất
- ⚠️ Chi phí của breach luôn lớn hơn chi phí phòng ngừa — TJX mất 3 năm không phát hiện là ví dụ điển hình
- ✅ SOX, HIPAA, GLB là ba luật quan trọng nhất định hình yêu cầu quản lý rủi ro IT tại Mỹ
- 🔗 Chapter tiếp theo (Chapter 15) sẽ đề cập đến quản lý nhân sự IT — personnel risk đã được giới thiệu trong chương này chính là cầu nối

---

## 📖 Giải thích thuật ngữ chuyên ngành

**Risk (Rủi ro)**
Khả năng xảy ra sự kiện không mong muốn gây thiệt hại. Không phải sự kiện đã xảy ra, mà là *tiềm năng* xảy ra. Như "nguy cơ cháy nhà" — không phải nhà đã cháy, mà là khả năng có thể cháy nếu không có biện pháp phòng ngừa. Quan trọng vì mọi quyết định IT đều mang rủi ro cần được định lượng và quản lý có hệ thống.

**Vulnerability (Lỗ hổng)**
Điểm yếu trong hệ thống, quy trình, hoặc thiết kế có thể bị khai thác. Như "cửa sổ để hở" trong nhà — bản thân nó chưa gây hại, nhưng tạo điều kiện cho kẻ xấu xâm nhập. Theo NIST, vulnerability là flaw hoặc weakness trong security procedures, design, hoặc internal controls.

**Threat (Mối đe dọa)**
Tác nhân hoặc sự kiện có khả năng khai thác vulnerability để gây tổn thất. Như "kẻ trộm" đối với "cửa sổ để hở." Cần có cả vulnerability lẫn threat mới tạo thành rủi ro thực sự — đây là lý do risk assessment luôn làm việc với vulnerability/threat pairs.

**Risk Assessment (Đánh giá rủi ro)**
Quy trình có hệ thống để xác định tất cả rủi ro của tổ chức — liệt kê vulnerabilities, threats, đánh giá likelihood và impact, ưu tiên xử lý. Như "kiểm tra an toàn nhà" trước khi lắp đặt hệ thống báo trộm — cần biết mọi điểm yếu trước, sau đó mới biết bảo vệ cái gì.

**Disaster Recovery Plan (Kế hoạch phục hồi thảm họa)**
Tài liệu chi tiết các bước để phục hồi hệ thống và hoạt động business sau một sự kiện thảm họa (thiên tai, mất điện kéo dài, tấn công mạng lớn). Như "kịch bản sơ tán khẩn cấp" — phải được luyện tập và cập nhật thường xuyên để thực sự có tác dụng khi cần.

**Sarbanes-Oxley Act (SOX)**
Luật Mỹ năm 2002 yêu cầu công ty đại chúng có internal controls mạnh và executives phải ký xác nhận tính chính xác của báo cáo tài chính. Ra đời sau các vụ bê bối Enron, Tyco, WorldCom. Quan trọng với IT vì CIO phải đảm bảo IT systems có đủ audit trail và controls đáp ứng yêu cầu — ký xác nhận sai có thể dẫn đến trách nhiệm hình sự cá nhân.

**HIPAA (Health Insurance Portability and Accountability Act)**
Luật Mỹ năm 1996 bảo vệ thông tin y tế cá nhân (PHI — Protected Health Information). Áp dụng cho tất cả tổ chức y tế và đối tác xử lý dữ liệu y tế. Yêu cầu IT phải kiểm soát chặt chẽ ai được truy cập PHI, cách dữ liệu được lưu trữ và truyền tải, và có Privacy Rule về disclosure.

**GLB Act (Gramm-Leach-Bliley Act)**
Luật tài chính Mỹ năm 1999 bảo vệ thông tin tài chính cá nhân của khách hàng. Ba thành phần chính: Financial Privacy Rule (thu thập và chia sẻ dữ liệu), Safeguards Rule (triển khai và duy trì biện pháp bảo vệ), và chống pretexting. Áp dụng cho ngân hàng, bảo hiểm, và bất kỳ tổ chức nào cung cấp dịch vụ tài chính cho người tiêu dùng.

**Pretexting**
Hành vi lấy thông tin của người khác bằng cách giả vờ là ai đó khác — ví dụ gọi điện giả làm nhân viên ngân hàng để lấy thông tin tài khoản. GLB Act có điều khoản riêng cấm pretexting vì nó là vector tấn công xã hội (social engineering) phổ biến nhắm vào tổ chức tài chính. Vụ bê bối HP board member dùng pretexting để điều tra rò rỉ thông tin là ví dụ nổi tiếng.

**Physical Security (Bảo mật vật lý)**
Các biện pháp bảo vệ tài sản IT và không gian vật lý — server rooms, data centers, thiết bị. Bao gồm khóa, camera, access control cards, guards, fencing. Là tầng bảo vệ đầu tiên — nếu kẻ tấn công có thể tiếp cận phần cứng trực tiếp, mọi biện pháp software security đều có thể bị vô hiệu hóa.

**Information Security (Bảo mật thông tin)**
Bảo vệ thông tin khỏi truy cập, sử dụng, tiết lộ, phá hoại trái phép. Tập trung vào CIA triad: Confidentiality (bí mật — chỉ người được phép mới xem được), Integrity (toàn vẹn — dữ liệu không bị thay đổi trái phép), Availability (khả dụng — dữ liệu sẵn sàng khi cần). Dữ liệu ngày càng là tài sản có giá trị nhất của doanh nghiệp, nên information security ngày càng quan trọng.


---

!!! info "Nguồn gốc"
    `pdf_md/the-business-value-of-it-managing-risks-optimizing-performance-and-measuring-results-auerbach-publications-2008/guide_ai/23_chapter-14-how-should-it-manage-risk_guide.md`
