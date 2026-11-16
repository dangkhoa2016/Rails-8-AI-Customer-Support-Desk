# Phạm vi sản phẩm và giới hạn

> 🌐 Language / Ngôn ngữ: [English](PRODUCT_SCOPE.md) | **Tiếng Việt**

[Trang chính](../README.vi.md) · [Kiến trúc](ARCHITECTURE.vi.md) · [Lộ trình](ROADMAP.vi.md)

## Mục tiêu

Xây dựng không gian chăm sóc khách hàng trên Rails, nơi nhân viên có thể xem hồ sơ nghiệp vụ trong đúng quyền, xử lý ticket và tra cứu kho kiến thức song ngữ đã được duyệt. AI giúp tìm nguồn tham khảo; con người chịu trách nhiệm quyết định tác động đến khách hàng.

## Chức năng đã triển khai

| Nhóm | Khả năng minh họa |
| --- | --- |
| Tenant | Dashboard, ticket, hội thoại và khách hàng theo organization |
| Support | Phân công, trạng thái ticket, tin nhắn công khai/nội bộ và kiểm tra quyền |
| Nhân viên | Vai trò membership `owner`, `admin`, `agent`, `viewer` |
| Kiến thức | Bài viết có phiên bản, duyệt editorial và tìm kiếm chunk |
| AI retrieval | Embedding/reranking tùy chọn, pgvector và tìm kiếm kèm bằng chứng |
| Dữ liệu nghiệp vụ | TeamFlow billing/activation và NovaMart order/fulfillment giả lập |
| Platform | Danh tính PlatformAdmin độc lập, vòng đời tổ chức và audit local |
| Ngôn ngữ | Giao diện và dữ liệu mẫu Anh/Việt |
| Kỹ thuật | Rails regression, kiểm tra chính sách offline và fixture tái lập được |

## Dữ liệu minh họa

Snapshot database đánh giá có hai tenant giả lập và 240 ticket. Đây không phải giới hạn số lượng hoặc cam kết benchmark. Dự án không cung cấp dữ liệu khách hàng thật.

## Những gì chưa cam kết

- SaaS production công khai có SLA.
- Tích hợp thanh toán thật, email, tổng đài hoặc đơn vị vận chuyển.
- AI tự hoàn tiền, đổi gói, gửi phản hồi hoặc duyệt kiến thức.
- Triển khai Platform Console công khai hoặc tạo operator thật.
- GPU luôn sẵn sàng, đảm bảo chất lượng inference hoặc benchmark model đã nghiệm thu toàn diện.
- Chứng nhận bảo mật bên ngoài hay đánh giá tuân thủ pháp lý.

## Con người phải phê duyệt

Nguồn truy xuất giúp nhân viên quyết định, không phải lệnh thay đổi nghiệp vụ. Phân quyền, provenance, chuyển trạng thái và tenant boundary được kiểm tra độc lập với model.

Đọc thêm [Bảo mật](SECURITY.vi.md) và [Triển khai](DEPLOYMENT.vi.md).
