# Doanh nghiệp và dữ liệu giả lập

[English](DEMO_DATA_EN.md) · [Tiếng Việt](DEMO_DATA_VI.md) · [README](../README_VI.md)

## Giới thiệu bộ dữ liệu

Dự án mô phỏng hai **doanh nghiệp hoàn toàn giả lập**. Giá, chính sách, tài khoản, gói dịch vụ, đơn hàng và cuộc trò chuyện hỗ trợ chỉ nhằm kiểm thử ứng dụng multi-tenant, **không phải điều khoản của bất kỳ doanh nghiệp thật nào**.

| Thuộc tính | TeamFlow Cloud | NovaMart Store |
| --- | --- | --- |
| Lĩnh vực | B2B SaaS | Thương mại điện tử |
| Trọng tâm | Gói thuê bao, kích hoạt, hóa đơn | Đơn hàng, giao nhận, đổi trả, bảo hành |
| Các loại dữ liệu | Workspace, subscription, invoice, activation, incident | Product, order, payment, shipment, return, warranty |
| Danh mục kiến thức | 50 tiêu đề bài viết giả lập | 50 tiêu đề bài viết giả lập |
| Bộ ticket mở rộng | 120, chia VI/EN | 120, chia VI/EN |

Snapshot database development dùng để nghiệm thu tháng 11/2026 có **2 doanh nghiệp, 8 users, 8 memberships, 240 tickets, 440 tin nhắn, 12 knowledge versions được duyệt và 84 embeddings**. Đây là số liệu của bản dữ liệu mẫu, **không phải giới hạn cố định** trong code.

## Những tình huống hỗ trợ minh họa

### TeamFlow Cloud

- Khách đã thanh toán hóa đơn nhưng gói nâng cấp chưa kích hoạt.
- Gói được yêu cầu thay đổi nhưng thời điểm hiệu lực khác thời điểm yêu cầu.
- Nhân viên cần đối soát billing mà không tự thay đổi quyền sử dụng.
- Service incident hoặc export job cần giải thích dựa trên dữ liệu có thật trong hệ thống demo.

### NovaMart Store

- Đơn hàng chỉ được giao một phần.
- Thanh toán thành công nhưng một số mặt hàng chưa xuất kho.
- Đổi trả hoặc bảo hành phụ thuộc vào mặt hàng và thời điểm giao cụ thể.
- Nhân viên phải phân biệt yêu cầu hoàn tiền với quyết định hoàn tiền đã được duyệt.

Mỗi tình huống khuyến khích kiểm tra hồ sơ nghiệp vụ được xác minh trước khi phản hồi.

## Kho kiến thức

Dự án có dữ liệu kiến thức song ngữ được tạo theo quy tắc có thể tái lập. Các phiên bản bài viết chứa trạng thái editorial và những chunk liên quan; kiến thức đã duyệt có thể liên kết embedding để tìm kiếm vector.

84 giá trị `vector(2560)` trong snapshot database được gắn với chunk đã duyệt. Điều này minh họa luồng dữ liệu retrieval, **không chứng minh mọi bài viết đã được duyệt, mọi câu hỏi trả lời được hoặc GPU endpoint đang hoạt động**.

## Ranh giới dữ liệu và phân quyền

Mỗi bản ghi nghiệp vụ thuộc một `Organization`; quyền truy cập dựa vào `Membership`. Không được hiển thị hóa đơn/đơn hàng của tenant khác chỉ vì request hoặc AI cung cấp một ID.

Nhân viên có quyền xem ngữ cảnh phù hợp, nhưng **AI không được tự thay đổi dữ liệu nghiệp vụ hoặc gửi phản hồi công khai**. Mọi thao tác cần con người kiểm tra và xác nhận đúng quyền.

## Tái lập dữ liệu

Dữ liệu nguồn nằm trong `data/`, script seed/import ở `db/seeds/`; các công cụ validation dùng một bản blueprint chính sách mẫu đã được ghi phiên bản. Cần kiểm tra và dùng database riêng trước khi nhập.

Hai JSON fixture chuẩn vẫn giữ trong `docs/` vì các script validation/seed hiện tham chiếu trực tiếp:

- `RAILS8_AI_SUPPORT_DESK_CANONICAL_BLUEPRINT_2026-10-28.json`
- `source_snapshot/RAILS8_AI_SUPPORT_DESK_CANONICAL_BLUEPRINT_2026-10-28.json`

Hai file chứa **đặc tả dữ liệu giả lập**, không chứa khóa runtime, credential khách hàng hay hướng dẫn triển khai nội bộ.

Các log lịch sử, handoff notebook và cấu hình máy cá nhân không thuộc tài liệu phát hành công khai.

## Giới hạn

Kết quả đánh giá và ví dụ chính sách giả lập không chứng minh tính đúng đắn cho doanh nghiệp thật. Trước khi triển khai với khách hàng, cần thay bằng nguồn chính sách đã xác minh, hoàn thiện xác thực/bảo mật vận hành và kiểm tra độc lập về lưu trữ, quyền riêng tư, thông báo và quy trình hỗ trợ.
