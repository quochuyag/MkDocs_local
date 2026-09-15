---
title: Giới thiệu về OCI và DevSecOps
course: 07-sach-va-tai-lieu
source: pdf_md/devsecops-in-oracle-cloud-securing-and-automating-oracle-cloud-infrastructure-for-sebastian-hassinger/guide_ai/12_1-introduction-to-oci-and-devsecops_guide.md
---

# Giới thiệu về OCI và DevSecOps

| Trường        | Nội dung                                                        |
|---------------|-----------------------------------------------------------------|
| 📚 Nguồn      | DevSecOps in Oracle Cloud — Chapter 1 (File 12)                 |
| 📅 Ngày tạo   | 2026-04-27                                                      |
| ⏱ Thời gian   | ~30 phút                                                        |
| 🔢 Phiên bản  | Guide v1.1                                                      |

---

## 🎯 Mục tiêu học tập

Sau khi học xong chapter này, bạn có thể:

- **Hiểu** được DevSecOps là gì và tại sao nó khác với DevOps truyền thống về thời điểm và cách tích hợp bảo mật
- **Phân biệt** được vai trò của 7 thành viên trong đội DevSecOps và tầm quan trọng của văn hóa chia sẻ trách nhiệm
- **Mô tả** được cách OCI hỗ trợ DevSecOps qua ba trụ cột, đồng thời giải quyết hai thách thức lớn: Shared Responsibility và Complexity & Visibility
- **Áp dụng** được chu trình DevSecOps mở rộng (Scan → Analyze → Remediate → Threat Management) vào pipeline CI/CD thực tế
- **Đánh giá** được lợi thế chi phí của OCI: flexible compute, storage SLA, zero intra-region fees, và 10 TB egress miễn phí
- **Nhận biết** được toàn bộ danh mục 7 nhóm dịch vụ OCI Free Tier và điều kiện đăng ký tài khoản

---

## 📋 Tóm tắt nội dung chính

### Thách thức khi chuyển lên cloud

Khi tổ chức chuyển lên cloud, giả định phổ biến nhất là "cloud sẽ giúp tiết kiệm chi phí" — điều này vừa đúng vừa sai. Hai nguyên nhân chính gây lãng phí là: (1) định cỡ tài nguyên không chính xác do kiến trúc sư không hiểu rõ workload, và (2) đội vận hành cố ý cấp phát dư để tránh phàn nàn về hiệu năng. Thêm vào nhu cầu bảo mật và vận hành hằng ngày, cloud project trở nên phức tạp nghiêm trọng. DevSecOps là phương pháp luận giải quyết toàn bộ những thách thức này.

### DevSecOps là gì?

DevSecOps (Development, Security, Operations) tích hợp bảo mật vào toàn bộ vòng đời phát triển phần mềm (SDLC — Software Development Lifecycle), thay vì chỉ kiểm tra ở cuối như cách truyền thống. Bảo mật được "shift left" — đưa vào ngay từ giai đoạn thiết kế, xuyên suốt coding, testing, deployment, đến maintenance. Mọi kiểm tra bảo mật được tự động hóa trong CI/CD: automated testing, static code analysis, vulnerability scanning, compliance check, và automated policy enforcement để đảm bảo áp dụng đồng nhất mà không làm chậm tốc độ phát triển.

DevSecOps giữ nguyên quy trình DevOps cơ bản (Plan → Code → Build → Test → Release → Deploy → Operate → Monitor) nhưng bổ sung bốn bước bảo mật: **Scan** (quét lỗ hổng code và hạ tầng bằng Vulnerability Scanning Service), **Analyze** (phân tích kết quả), **Remediate** (vá lỗi — OS patching tự động qua OS Management Hub), và **Threat Management** (sử dụng OCI Threat Intelligence và Cloud Guard Threat Detector).

IaC (Infrastructure as Code) — thực hiện qua Ansible, Terraform, hoặc kết hợp hai công cụ — đảm bảo security policy áp dụng đồng nhất mọi môi trường. OCI còn hỗ trợ IaC native như auto-scaling của Autonomous Database Service. Compliance requirements được tích hợp thẳng vào CI/CD pipeline, với automated policy enforcement tại mỗi bước.

> **Lưu ý:** "CD" trong CI/CD có thể là Continuous Delivery hoặc Continuous Deployment — cả hai đều đúng và được dùng thay thế cho nhau.

Xây dựng đội DevSecOps đòi hỏi văn hóa cộng tác thực sự. Cross-functional teams phải làm việc chặt chẽ, phá vỡ silo giữa dev, security, và ops. Regular feedback loops đảm bảo kết quả security findings được trả về cho developer để cải thiện liên tục. Security Champions trong từng squad giúp thúc đẩy best practices không cần security engineer can thiệp từng task. Thành viên cần cập nhật mối đe dọa mới qua đào tạo và học tập liên tục.

### Tại sao cần DevSecOps?

DevSecOps mang lại sáu lợi ích cụ thể:

1. **Faster Time-to-Market** — Phát hiện lỗ hổng sớm, tránh delay trước ngày release; automated monitoring duy trì security posture mạnh trong khi tăng tốc.
2. **Cost Efficiency** — Phát hiện và vá lỗi sớm rẻ hơn nhiều so với sau khi deploy. Auto-scaling chỉ dùng đúng tài nguyên cần, giảm chi phí cloud.
3. **Improved Compliance** — Automated compliance check và continuous monitoring đảm bảo ứng dụng luôn đáp ứng tiêu chuẩn quy định và ngành.
4. **Increased Collaboration** — Văn hóa chia sẻ trách nhiệm phá vỡ silo giữa dev, security, và ops; dẫn đến giao tiếp tốt hơn và hiểu biết lẫn nhau sâu hơn.
5. **Cost Savings** — Giải quyết vấn đề bảo mật sớm trong development rẻ hơn gấp nhiều lần so với fix trong production. Cloud-native scaling giảm chi phí bằng cách không provisioning tài nguyên khi không cần.
6. **Compliance (Policy Enforcement)** — Automated policy enforcement đảm bảo mọi bước của quy trình đều tuân thủ regulatory standards.

### Đội DevSecOps gồm những ai?

Một đội DevSecOps tiêu chuẩn có bảy vai trò: **Developer**, **Security Engineer**, **Operations Engineer**, **QA Engineer**, **Security Champion** (người cầu nối giữa developer và security expert, thúc đẩy best practices trong team), **Release Manager**, và **Cloud Architect**. Văn hóa cộng tác là yếu tố then chốt — đội phải làm việc chặt chẽ, chia sẻ trách nhiệm bảo mật, duy trì feedback loop thường xuyên, và cập nhật kiến thức liên tục về mối đe dọa mới.

### OCI hỗ trợ DevSecOps như thế nào?

OCI hỗ trợ DevSecOps qua ba trụ cột:

- **Scalability and Flexibility** — Tách biệt CPU và RAM, cấp phát chính xác theo nhu cầu; nhanh chóng provision và scale tài nguyên.
- **Automation** — Terraform, Ansible, và Oracle Linux Automation Manager (OLAM — AWX-based) tích hợp sẵn không tốn thêm phí; hỗ trợ CI/CD pipeline và IaC hoàn chỉnh kể cả auto-scaling Autonomous Database.
- **Integrated Services** — Managed database, logging, monitoring, security tích hợp chặt chẽ với nhau, đặc biệt với database; giảm overhead vận hành thủ công.

OCI cũng giải quyết hai thách thức lớn: **Shared Responsibility** được xử lý bằng nhiều chứng chỉ tuân thủ, cung cấp nền tảng bảo mật cho cloud workload của khách hàng. **Complexity & Visibility** được giải quyết bằng Observability & Management services — đặc biệt Log Analytics — cho phép phân tích, tự động tương quan, và cảnh báo từ gần như tất cả sự kiện và log.

### Lợi thế chi phí của OCI so với AWS/Azure

OCI thường rẻ hơn cho từng dịch vụ. Ví dụ storage: khi so sánh 1 TB high-performance LUN, OCI rẻ hơn đáng kể và quan trọng hơn — **OCI cung cấp SLA cho storage IOPS performance**. AWS io2 không có SLA IOPS, chi phí tăng nhanh theo performance. Nếu CSP hứa 120,000 IOPS nhưng không có SLA, thực tế có thể chỉ nhận 12,000 IOPS mà không có chỗ khiếu nại. Khi so sánh CSP, phải nhìn vào tổng chi phí: performance, SLA, và các phụ phí ẩn.

Điểm khác biệt lớn nhất là **Flexible Compute**: AWS/Azure bán theo shape cố định (1 core → 4 GB RAM, 2 core → 8 GB RAM…). Nếu cần 11 core thì phải mua 16-core; nếu cần 7 core + 100 GB RAM thì phải mua 32-core + 128 GB RAM. Với 50 VM, lãng phí cộng dồn có thể vượt 25% chi phí — chưa kể licensing thường tính theo số core mua, không phải số core dùng. OCI cho phép chọn chính xác: 3 core + 187 GB RAM, hay 32 core + 32 GB RAM — CPU và RAM là hai line item riêng.

Ngoài ra OCI không tính phí data transfer trong region, và cho 10 TB egress đầu tiên miễn phí (giữa regions hoặc Internet). Giá OCI đồng nhất mọi region — US East/West, DoD, FedRAMP, quốc tế cùng một mức, giúp budgeting dễ dự đoán.

### OCI Free Services — Danh mục đầy đủ

OCI cung cấp hơn hai chục dịch vụ always-free mỗi tháng, chia thành 7 nhóm:

- **Compute:** 2 AMD-based VMs (mỗi VM: 1/8 OCPU + 1 GB RAM) + 3,000 giờ A1 compute và 18,000 GB-giờ A1 RAM (~4 core A1 + 24 GB RAM/tháng)
- **Storage:** 2 block volumes (tổng 200 GB) + 20 GB Object Storage (Standard + Infrequent Access + Archival) + 50,000 Object Storage API requests/tháng
- **Networking:** 10 TB egress + 1 Network Load Balancer (Layer 3/4) + 10 Mbps Load Balancer + 2 Service Connector Hubs + 10 GB VCN Flow Logs + 2 VCN + 50 IPsec site-to-site VPN connections
- **Observability & Management:** 1,000 tracing events và 10 synthetic monitoring runs/giờ + 100 emails/tháng + 10 GB logs + 1 tỷ data points giám sát (retrieval) + 500 triệu data points (ingestion) + 1 triệu HTTPS notifications/tháng
- **Database:** 2 Autonomous Databases (mỗi DB: 20 GB storage) + 133 triệu NoSQL reads + 25 GB NoSQL storage
- **Security:** 5 Bastion hosts + 5 private CAs + 150 private TLS certs + 1 Vault (20 keys + 150 secrets)
- **Developer:** 744 giờ APEX (~1 OCPU) + 100 cloud dashboards

**Để đăng ký:** Cần email công việc/tổ chức (không dùng Gmail, outlook.com, yahoo.com), thẻ tín dụng (chỉ để xác minh danh tính — không bị tính phí khi dùng always-free), và số điện thoại (MFA). Mỗi số điện thoại và email chỉ dùng được một tài khoản free tier.

---

## 🔑 Khái niệm quan trọng

| Khái niệm | Định nghĩa | Tại sao quan trọng | Ví dụ thực tế |
|-----------|------------|-------------------|---------------|
| **DevSecOps** | Phương pháp tích hợp bảo mật vào toàn bộ vòng đời DevOps, từ thiết kế đến vận hành, bảo mật là trách nhiệm chia sẻ toàn đội | Phát hiện lỗ hổng sớm, giảm chi phí vá lỗi, tăng tốc độ ra thị trường | Quét lỗ hổng tự động trong pipeline CI/CD trước khi merge code |
| **Shift Left** | Đưa kiểm tra bảo mật về phía đầu quy trình phát triển thay vì cuối | Phát hiện và sửa lỗi sớm rẻ hơn gấp nhiều lần so với sau khi triển khai | Lập trình viên chạy static code analysis ngay khi viết code |
| **CI/CD** | Continuous Integration/Delivery — tự động hóa build, test, deploy kèm security check và compliance enforcement | Xương sống của DevSecOps, đảm bảo kiểm tra bảo mật nhất quán mọi lần deploy | Mỗi lần push code tự động chạy unit test + vulnerability scan + compliance check |
| **IaC (Infrastructure as Code)** | Quản lý và cấp phát hạ tầng bằng code, đảm bảo môi trường nhất quán và security policy áp dụng đồng đều | Tránh cấu hình sai thủ công dẫn đến lỗ hổng bảo mật | Terraform tạo VCN, subnet, security list trong OCI; Autonomous DB tự auto-scale |
| **Shared Responsibility Model** | Phân chia trách nhiệm bảo mật: CSP bảo vệ hạ tầng, khách hàng bảo vệ dữ liệu và ứng dụng | Hiểu sai mô hình này là nguyên nhân phổ biến gây breach trong cloud | OCI bảo vệ hạ tầng vật lý; khách hàng tự bảo vệ cấu hình và data |
| **SLA (Service Level Agreement)** | Cam kết chính thức của CSP về mức hiệu năng tối thiểu được bảo đảm; nếu không đạt phải bồi thường | Không có SLA IOPS — CSP hứa 120K IOPS nhưng chỉ cho 12K mà không chịu trách nhiệm | OCI cam kết SLA storage IOPS; AWS io2 không có cam kết tương đương |
| **OCPU / ECPU** | OCPU = 1 physical core đầy đủ (≈ 2 vCPU); ECPU ≈ 1/4 core dùng cho Autonomous DB | So sánh sai đơn vị CPU dẫn đến ước tính chi phí sai | 1 OCPU OCI ≈ 2 vCPU AWS — mua 1 OCPU thực chất tương đương 2 vCPU |
| **OCI Free Tier** | 7 nhóm dịch vụ miễn phí hàng tháng bao gồm cả Compute, Database, Security (Bastion, Vault, Certs) | Cho phép xây lab DevSecOps hoàn chỉnh không cần ngân sách ban đầu | 4 A1 core + 5 Bastion + 2 Autonomous DB + Vault miễn phí mỗi tháng |
| **Security Champion** | Thành viên đội dev được chỉ định cầu nối với security team, thúc đẩy best practices trong squad | Lan tỏa bảo mật mà không cần security engineer can thiệp từng task | Senior developer tự review security của PR trước khi gửi security team |

---

## 🌍 Ví dụ thực tế & Case Study

### Case Study 1: Startup Việt Nam chuyển lên cloud gặp bài toán overspend 🇻🇳

- **Bối cảnh:** Một startup fintech tại TP.HCM triển khai 20 microservice trên AWS, mỗi service dùng instance c5.4xlarge (16 vCPU, 32 GB RAM). Database dùng io2 storage để đảm bảo IOPS cao.
- **Vấn đề:** Sau 3 tháng hóa đơn cloud tăng vọt. Monitoring thực tế cho thấy mỗi service chỉ dùng 3–4 vCPU và 8 GB RAM — trả tiền cho 60% tài nguyên không dùng đến. Thêm nữa, AWS io2 không có SLA IOPS, thỉnh thoảng latency database tăng đột biến vào giờ cao điểm mà không có cơ sở khiếu nại.
- **Giải pháp:** Chuyển sang OCI Flexible Shapes: cấu hình chính xác 4 OCPU + 8 GB RAM mỗi service. Dùng OCI Block Volume (có SLA IOPS) cho database production. Triển khai Autonomous Database với auto-scaling.
- **Kết quả:** Giảm 40% chi phí cloud. Database latency ổn định nhờ storage SLA. Autonomous DB tự scale vào giờ cao điểm không cần can thiệp thủ công.
- **Bài học:** So sánh cloud phải tính cả model phân bổ CPU/RAM, SLA performance của storage, và chi phí ẩn — không chỉ giá niêm yết mỗi giờ.

### Case Study 2: Ngân hàng tích hợp bảo mật vào pipeline CI/CD

- **Bối cảnh:** Một ngân hàng khu vực tại Đông Nam Á, đội dev 50 người, deploy thủ công 2 tuần/lần. Một team security tập trung review code ở cuối sprint — không có feedback loop về kết quả review cho developer.
- **Vấn đề:** Security review là nút cổ chai — phát hiện lỗ hổng nghiêm trọng ngay trước release, buộc phải delay hoặc deploy với rủi ro. Developer không nhận được feedback về lý do reject, không học được gì, lặp lại lỗi tương tự sprint sau.
- **Giải pháp:** Áp dụng DevSecOps đầy đủ: tích hợp SAST vào CI/CD, OCI Vulnerability Scanning tự động sau mỗi build, bổ nhiệm Security Champion mỗi squad, thiết lập feedback loop tự động — kết quả scan gửi thẳng về ticket của developer trong sprint.
- **Kết quả:** Release cycle rút từ 2 tuần xuống 3 ngày. 80% lỗ hổng phát hiện và sửa trong sprint. Developer dần hiểu security hơn qua feedback loop liên tục.
- **Bài học:** Shift left kết hợp feedback loop không chỉ tìm lỗi sớm mà còn giúp cả đội học bảo mật theo thời gian — đây là yếu tố văn hóa lâu dài.

### Case Study 3: Tổ chức chính phủ xây lab DevSecOps bằng OCI Free Tier 🇻🇳

- **Bối cảnh:** Một cơ quan nhà nước muốn đào tạo 15 kỹ sư IT về DevSecOps nhưng ngân sách cloud bằng 0.
- **Vấn đề:** Không có môi trường thực hành. Máy local không phản ánh thực tế cloud; không thể thực hành Bastion host, Vault secrets, hay IaC trên cloud thật.
- **Giải pháp:** Đăng ký OCI Free Tier với email tổ chức. Xây lab dùng: 4 A1 core + 24 GB RAM (compute), 200 GB block volume (storage), 2 Autonomous DB, 5 Bastion hosts, Vault (20 keys), Terraform + Ansible/OLAM. Toàn bộ không tốn phí.
- **Kết quả:** Lab chạy miễn phí 3 tháng. Kỹ sư thực hành IaC, OCI DevOps Service, Vulnerability Scanning, Cloud Guard, và Bastion host trong môi trường cloud thực.
- **Bài học:** OCI Free Tier bao gồm cả security services (Bastion, Vault, Certs) chứ không chỉ compute và storage — đủ để xây lab DevSecOps hoàn chỉnh mà không cần ngân sách.

---

## 📊 Sơ đồ & Bảng tổng hợp

### Bảng 1 — So sánh DevOps và DevSecOps

| Tiêu chí | DevOps | DevSecOps |
|----------|--------|-----------|
| Bảo mật | Kiểm tra cuối quy trình | Tích hợp từ đầu (shift left) |
| Trách nhiệm bảo mật | Chỉ đội security | Chia sẻ toàn đội |
| Tự động hóa | CI/CD, IaC | CI/CD + security scan + compliance check + policy enforcement |
| Feedback loop | Dev → Ops | Dev ↔ Security ↔ Ops (hai chiều, liên tục) |
| Văn hóa | Dev + Ops hợp tác | Dev + Sec + Ops — Security Champion cầu nối |

### Bảng 2 — So sánh Compute và chi phí: OCI vs AWS/Azure

| Tiêu chí | AWS / Azure | OCI |
|----------|-------------|-----|
| Đơn vị CPU | vCPU (1 thread) | OCPU (1 physical core = ~2 vCPU) |
| Model mua | Shape cố định (CPU + RAM gắn nhau) | Flexible: CPU và RAM riêng biệt |
| Ví dụ lãng phí | Cần 7 core + 100 GB → phải mua 32 core + 128 GB | Mua chính xác 7 OCPU + 100 GB |
| Định giá region | Khác nhau theo region | Đồng nhất mọi region (kể cả DoD, FedRAMP) |
| Egress miễn phí | Thường tính phí | 10 TB/tháng miễn phí |
| Phí trong region | Có tính phí | Miễn phí |
| SLA storage IOPS | Thường không có (AWS io2) | Có SLA cam kết |

### Bảng 3 — OCI Free Tier theo nhóm dịch vụ

| Nhóm | Dịch vụ miễn phí hàng tháng |
| --- | --- |
| **Compute** | 2 AMD VMs (1/8 OCPU + 1 GB RAM mỗi VM) + ~4 A1 core + 24 GB RAM |
| **Storage** | 2 block volumes (200 GB) + 20 GB Object Storage + 50K API requests |
| **Networking** | 10 TB egress + Load Balancer + 2 VCN + 50 IPsec VPN + 2 Service Connector Hubs |
| **Observability** | 10 GB logs + 1B monitoring data points + 500M ingestion + 1M HTTPS notifications |
| **Database** | 2 Autonomous DB (20 GB/DB) + NoSQL (133M reads + 25 GB) |
| **Security** | 5 Bastion hosts + 5 private CAs + 150 TLS certs + Vault (20 keys + 150 secrets) |
| **Developer** | 744 giờ APEX + 100 cloud dashboards |

### Bảng 4 — Chu trình DevSecOps mở rộng

| Giai đoạn | Hoạt động chính | Công cụ OCI tương ứng |
|-----------|-----------------|----------------------|
| Plan → Code → Build → Test | Phát triển + static code analysis | OCI DevOps Service, SAST |
| **Scan** | Quét lỗ hổng code, OS image, hạ tầng | Vulnerability Scanning Service |
| **Analyze** | Phân tích, phân loại, tương quan kết quả | Log Analytics |
| **Remediate** | Vá lỗi code, patch OS tự động | OS Management Hub |
| Release → Deploy → Operate | Triển khai + compliance enforcement | OCI DevOps, Terraform, Ansible/OLAM |
| Monitor + **Threat Management** | Giám sát realtime + phản ứng mối đe dọa | Cloud Guard, OCI Threat Intelligence |

---

## ❓ Câu hỏi ôn tập

**Câu 1 (Recall):** DevSecOps khác gì so với DevOps truyền thống về cách tích hợp bảo mật? Kể tên bốn bước bảo mật bổ sung trong chu trình DevSecOps.

💡 **Gợi ý:** Nghĩ về thời điểm bảo mật được đưa vào và những giai đoạn nào được thêm vào sau bước Monitor.

📝 **Đáp án:** Trong DevOps truyền thống, bảo mật chỉ được kiểm tra ở cuối quy trình do một team security riêng biệt. DevSecOps "shift left" — đưa bảo mật vào ngay từ giai đoạn thiết kế và tự động hóa toàn bộ SDLC, biến bảo mật thành trách nhiệm chia sẻ của toàn đội. Bốn bước bảo mật bổ sung: (1) **Scan** — quét lỗ hổng code và hạ tầng bằng Vulnerability Scanning Service; (2) **Analyze** — phân tích kết quả quét; (3) **Remediate** — vá lỗi và patch OS tự động qua OS Management Hub; (4) **Threat Management** — theo dõi mối đe dọa bằng OCI Threat Intelligence và Cloud Guard Threat Detector.

---

**Câu 2 (Recall):** OCI hỗ trợ DevSecOps qua ba trụ cột nào? Nêu một ví dụ công cụ/dịch vụ OCI cho mỗi trụ cột.

💡 **Gợi ý:** Ba trụ cột liên quan đến khả năng mở rộng, tự động hóa, và tích hợp dịch vụ.

📝 **Đáp án:** Ba trụ cột: (1) **Scalability and Flexibility** — OCI tách CPU và RAM để cấp phát chính xác, ví dụ chọn 4 OCPU + 8 GB RAM thay vì phải mua shape 8 OCPU + 16 GB RAM như AWS; (2) **Automation** — Terraform, Ansible, và Oracle Linux Automation Manager (OLAM) tích hợp sẵn không tốn thêm phí, hỗ trợ CI/CD pipeline và IaC kể cả auto-scaling của Autonomous Database; (3) **Integrated Services** — managed database, Log Analytics, Cloud Guard tích hợp chặt chẽ với nhau và với database, giảm overhead thiết lập thủ công.

---

**Câu 3 (Comprehension):** Tại sao SLA cho storage performance là tiêu chí quan trọng khi so sánh OCI với AWS? Điều gì xảy ra nếu không có SLA này?

💡 **Gợi ý:** Nghĩ về trường hợp CSP hứa 120,000 IOPS nhưng không có cam kết pháp lý.

📝 **Đáp án:** SLA (Service Level Agreement) là cam kết chính thức của cloud provider về mức hiệu năng tối thiểu được bảo đảm — nếu không đạt, provider phải bồi thường. Nếu không có SLA IOPS, CSP có thể quảng cáo 120,000 IOPS nhưng thực tế chỉ cung cấp 12,000 IOPS trong giờ cao điểm mà không có nghĩa vụ gì. Điều này cực kỳ nguy hiểm cho database production — latency tăng đột biến ảnh hưởng trực tiếp đến giao dịch và trải nghiệm người dùng. AWS io2 storage đặc biệt đắt khi cần performance cao và vẫn không có SLA tương ứng. OCI cung cấp SLA cho storage IOPS, đây là lợi thế quan trọng cho hệ thống production yêu cầu hiệu năng database ổn định và có thể cam kết với stakeholders.

---

**Câu 4 (Comprehension):** Giải thích tại sao OCI Flexible Compute tiết kiệm ít nhất 25% so với AWS/Azure. Dùng ví dụ số liệu cụ thể từ chapter.

💡 **Gợi ý:** Nhớ ví dụ: ứng dụng cần 7 core + 100 GB RAM — điều gì xảy ra trên AWS so với OCI?

📝 **Đáp án:** AWS và Azure bán compute theo shape cố định, gắn CPU và RAM theo tỷ lệ định sẵn. Ví dụ từ sách: ứng dụng cần 7 core + 100 GB RAM. Trên AWS, không có shape phù hợp — chọn 16-core/64 GB thì thiếu RAM; chọn 32-core/128 GB thì thừa 25 core và 28 GB RAM, nhưng vẫn phải trả tiền cho toàn bộ. Cộng thêm licensing thường tính theo số core mua, không phải số core dùng. Nhân với 50 VM, lãng phí vượt 25% tổng chi phí. OCI cho phép mua chính xác 7 OCPU + 100 GB RAM — CPU và RAM là hai line item riêng biệt, có thể điều chỉnh độc lập. Kết quả tiết kiệm tối thiểu 25% ngay cả khi giá mỗi giờ tương đương.

---

**Câu 5 (Application):** Công ty bạn xây hệ thống e-commerce trên OCI với ngân sách ban đầu bằng 0. Hãy thiết kế môi trường lab DevSecOps dùng OCI Free Tier: liệt kê ít nhất 4 nhóm dịch vụ và cách dùng từng nhóm.

💡 **Gợi ý:** Xem lại Bảng 3 — OCI Free Tier có tới 7 nhóm bao gồm cả Security (Bastion, Vault).

📝 **Đáp án:** Môi trường lab DevSecOps đầy đủ từ Free Tier: (1) **Compute** — 4 A1 core + 24 GB RAM làm app server và CI/CD runner; 2 AMD VMs làm jump server và monitoring node; (2) **Database** — 2 Autonomous DB (20 GB/cái): một production-like, một staging; Autonomous DB tự auto-scale theo tải; (3) **Security** — 5 Bastion hosts để kiểm soát truy cập vào tất cả VM (không SSH trực tiếp); Vault với 20 keys lưu DB password và API key; 5 private CAs cấp TLS cert nội bộ; (4) **Automation** — cài Ansible/OLAM trên A1 compute để thực hành IaC với Terraform; kết nối OCI DevOps Service (free) để dựng CI/CD pipeline với Vulnerability Scanning tự động mỗi build; (5) **Observability** — 10 GB logs và Log Analytics để phân tích kết quả security scan, cảnh báo khi có lỗ hổng Critical. Toàn bộ chạy miễn phí với always-free services.

---

## 💡 Ghi nhớ nhanh

- ✅ DevSecOps = DevOps + bảo mật "shift left" — tích hợp từ đầu, tự động hóa, chia sẻ trách nhiệm toàn đội
- ✅ Bốn bước bảo mật bổ sung: **Scan → Analyze → Remediate → Threat Management**
- ✅ OCI Flexible Compute tách CPU và RAM: chọn chính xác theo nhu cầu, tiết kiệm tối thiểu 25% so với shape cố định
- ✅ OCI cam kết **SLA cho storage IOPS** — không phải tất cả CSP đều làm được điều này (AWS io2 không có)
- ✅ OCI Free Tier bao gồm **Security services** (Bastion, Vault, Certs) — không chỉ compute — đủ để xây lab DevSecOps hoàn chỉnh
- ⚠️ "Cloud tiết kiệm tiền" không tự động đúng — phải sizing đúng và áp dụng DevSecOps để tránh overspend
- ⚠️ Đừng nhầm vCPU (1 thread) với OCPU (1 physical core ≈ 2 vCPU) — so sánh sai đơn vị dẫn đến ước tính chi phí sai
- ⚠️ OCI Free Tier không chấp nhận Gmail, outlook.com, yahoo.com — cần email công việc/tổ chức
- 🔗 Chapter tiếp theo sẽ bàn về: **OCI Governance** — quản trị tài nguyên, tenancy structure, và policy control ở cấp tổ chức

---

## 📖 Giải thích thuật ngữ chuyên ngành

#### **DevSecOps** — Phát triển-Bảo mật-Vận hành tích hợp

**Định nghĩa:** Phương pháp luận kết hợp Development (phát triển), Security (bảo mật), và Operations (vận hành) thành một quy trình liên tục, trong đó bảo mật là trách nhiệm chia sẻ của toàn đội từ ngày đầu.

**Ví dụ/Tương tự:** Như xây nhà — thay vì xây xong rồi mới lắp cửa khóa, DevSecOps thiết kế hệ thống bảo mật (tường chịu lực, phòng cháy) ngay từ bản vẽ kiến trúc đầu tiên.

**Tại sao quan trọng trong chapter này:** Đây là nền tảng triết lý của toàn bộ cuốn sách — mọi dịch vụ OCI được giới thiệu sau đều phục vụ phương pháp này.

---

#### **Shift Left** — Dịch chuyển bảo mật sang trái (sớm hơn)

**Định nghĩa:** Đưa các hoạt động kiểm tra và bảo mật về sớm hơn trong timeline phát triển (vẽ từ trái sang phải theo thời gian), thay vì để cuối quy trình.

**Ví dụ/Tương tự:** Như khám sức khỏe định kỳ — phát hiện bệnh sớm dễ chữa và rẻ hơn nhiều so với chờ đến khi nhập viện cấp cứu.

**Tại sao quan trọng trong chapter này:** Triết lý cốt lõi phân biệt DevSecOps với cách tiếp cận bảo mật truyền thống.

---

#### **CI/CD** — Tích hợp liên tục / Phân phối liên tục

**Định nghĩa:** CI (Continuous Integration) tự động merge, build, và test code mỗi khi developer push thay đổi. CD (Continuous Delivery hoặc Deployment) tự động đưa code đã test lên staging hoặc production. Trong DevSecOps, mỗi bước đều kèm security check và compliance enforcement.

**Ví dụ/Tương tự:** Như dây chuyền sản xuất ô tô — mỗi chi tiết được kiểm tra ngay khi lắp vào, không chờ kiểm tra toàn bộ xe sau khi hoàn thiện.

**Tại sao quan trọng trong chapter này:** CI/CD là nơi tích hợp security scan, vulnerability check, và compliance enforcement tự động trong DevSecOps.

---

#### **IaC (Infrastructure as Code)** — Hạ tầng dưới dạng code

**Định nghĩa:** Quản lý và cấp phát hạ tầng IT (server, network, database) bằng code hoặc file cấu hình thay vì thao tác thủ công, đảm bảo môi trường nhất quán và có thể tái tạo.

**Ví dụ/Tương tự:** Như công thức nấu ăn chi tiết — mỗi lần nấu theo đúng công thức cho kết quả giống nhau, thay vì nấu theo trí nhớ mỗi lần một khác.

**Tại sao quan trọng trong chapter này:** IaC (Terraform + Ansible/OLAM) là công cụ chính tự động hóa hạ tầng và áp dụng security policy đồng nhất trong DevSecOps trên OCI.

---

#### **SLA (Service Level Agreement)** — Cam kết mức dịch vụ

**Định nghĩa:** Thỏa thuận chính thức giữa cloud provider và khách hàng quy định mức hiệu năng, availability, và response time tối thiểu được bảo đảm. Nếu không đạt, provider phải bồi thường theo điều khoản đã ký.

**Ví dụ/Tương tự:** Như hợp đồng vận chuyển cam kết giao hàng trong 2 ngày — nếu trễ thì hoàn tiền. Không có SLA giống như giao hàng "khi nào xong thì xong, không hoàn tiền".

**Tại sao quan trọng trong chapter này:** OCI cung cấp SLA cho storage IOPS — điều mà AWS io2 không có — là lợi thế quan trọng cho hệ thống production yêu cầu hiệu năng database ổn định.

---

#### **Shared Responsibility Model** — Mô hình trách nhiệm chia sẻ

**Định nghĩa:** Khung phân chia trách nhiệm bảo mật: cloud provider bảo vệ hạ tầng vật lý và nền tảng; khách hàng chịu trách nhiệm bảo vệ dữ liệu, ứng dụng, và cấu hình của mình.

**Ví dụ/Tương tự:** Như thuê căn hộ — chủ nhà bảo vệ tòa nhà (cửa chính, camera hành lang), bạn tự chịu trách nhiệm khóa cửa phòng và bảo vệ tài sản bên trong.

**Tại sao quan trọng trong chapter này:** Hiểu sai mô hình này — nghĩ OCI lo toàn bộ bảo mật — là một trong những nguyên nhân phổ biến nhất dẫn đến breach trong cloud.

---

#### **OCPU / ECPU** — Đơn vị tính CPU của Oracle

**Định nghĩa:** OCPU (Oracle CPU) = 1 physical core đầy đủ (≈ 2 vCPU của Intel/AMD với hyperthreading). ECPU (Elastic CPU) ≈ 1/4 core, dùng cho Autonomous Database. vCPU của AWS/Azure = 1 thread — không phải 1 core.

**Ví dụ/Tương tự:** Như đơn vị đo lường khác nhau — 1 dặm Mỹ ≠ 1 km Việt Nam. So sánh cloud mà không quy đổi đơn vị cho kết quả sai hoàn toàn.

**Tại sao quan trọng trong chapter này:** Nhầm OCPU = vCPU sẽ ước tính chi phí OCI cao hơn thực tế — dẫn đến quyết định sai về lựa chọn cloud provider.

---

#### **Security Champion** — Đại sứ bảo mật trong đội dev

**Định nghĩa:** Thành viên đội phát triển được chỉ định để thúc đẩy bảo mật best practices, cầu nối giữa developer và security expert, lan tỏa ý thức bảo mật trong squad mà không cần security engineer can thiệp từng task.

**Ví dụ/Tương tự:** Như đại diện an toàn lao động trong xưởng sản xuất — không phải chuyên gia bảo hộ, nhưng đảm bảo mọi công nhân tuân thủ quy trình an toàn hằng ngày.

**Tại sao quan trọng trong chapter này:** Security Champion là cơ chế thực tế giúp DevSecOps hoạt động ở quy mô tổ chức lớn — không cần tăng headcount security engineer mà vẫn đảm bảo bảo mật được thực thi.

---

#### **Bastion Host** — Máy chủ trung gian bảo mật

**Định nghĩa:** Server được cấu hình và giám sát chặt chẽ, đóng vai trò điểm truy cập duy nhất từ Internet vào hạ tầng nội bộ — mọi kết nối SSH/RDP vào production đều phải qua Bastion, không kết nối trực tiếp.

**Ví dụ/Tương tự:** Như phòng bảo vệ tòa nhà — mọi người phải đăng ký và được kiểm tra trước khi vào bên trong, không ai đi thẳng lên tầng.

**Tại sao quan trọng trong chapter này:** OCI cung cấp 5 Bastion hosts miễn phí trong Free Tier — đây là công cụ bảo mật thiết yếu cho DevSecOps khi quản lý truy cập vào production environment, đặc biệt có ý nghĩa khi xây lab với ngân sách bằng 0.


---

!!! info "Nguồn gốc"
    `pdf_md/devsecops-in-oracle-cloud-securing-and-automating-oracle-cloud-infrastructure-for-sebastian-hassinger/guide_ai/12_1-introduction-to-oci-and-devsecops_guide.md`
