# HTTP routes và ranh giới tích hợp

> 🌐 Language / Ngôn ngữ: [English](API.md) | **Tiếng Việt**

[Trang chính](../README.vi.md) · [Kiến trúc](ARCHITECTURE.vi.md) · [Bảo mật](SECURITY.vi.md)

## Giao diện ứng dụng

Đây là **hệ thống Rails render tại server**. Những route bên dưới là giao diện bên trong ứng dụng, **không phải REST API công khai đã có version và cam kết tương thích**. Các quy tắc xác thực, CSRF và phân quyền theo tenant đều áp dụng.

| Nhóm | Route đại diện | Lưu ý |
| --- | --- | --- |
| Health | `GET /healthz` | Kiểm tra tình trạng ứng dụng, không thay thế đánh giá bảo mật |
| Demo local giả lập | `GET /demo/sign_in`, `POST /demo/sign_in` | Chọn membership chỉ dùng cho development |
| Password sessions | `GET /auth/sign_in`, `POST /auth/sign_in` | Đăng nhập nhân viên tenant |
| Dashboard | `GET /` | Tổng quan hỗ trợ của tenant |
| Ticket | `GET /tickets`, `GET /tickets/:id`, `POST /tickets` | Đọc/tạo theo quyền |
| Tin nhắn ticket | `POST /tickets/:ticket_id/ticket_messages` | Kiểm tra quyền và nội dung public/internal |
| Quy trình ticket | `PATCH /tickets/:id/status`, `PATCH /tickets/:id/assign` | Thay đổi trạng thái/phân công theo quyền |
| Khách hàng | Resource `/customers` | CRUD và lưu trữ trong đúng tenant |
| Nhân viên | `/staff_members` | Quản lý vai trò có giới hạn owner/admin |
| Kho kiến thức | `GET /knowledge_articles/:id`, `POST /knowledge_articles/:id/approve` | Phiên bản và phê duyệt bởi con người |
| Tìm kiến thức AI | `GET /kb/ai-search`, `POST /kb/ai-search` | Cần điều kiện sẵn sàng và phân quyền |
| Dữ liệu tham chiếu | `GET /records/teamflow/invoice`, `GET /records/novamart/order` | Hồ sơ giả lập |
| Settings | `GET /settings`, `PATCH /settings` | Thay đổi theo quyền tenant |
| Platform | `/platform/*` | **Danh tính quản trị độc lập, hạn chế truy cập** |

Định nghĩa route và HTTP verb chính xác nằm tại `config/routes.rb`.

## Xác thực và phân quyền

Nhân viên phải có session, membership và organization hợp lệ. Chỉ truyền ID tổ chức khác không được phép làm lộ dữ liệu. `SupportDeskAccessPolicy` quyết định quyền tại server.

Platform operator xác thực riêng, không thừa hưởng quyền của nhân viên chăm sóc khách hàng.

## Model integration tùy chọn

Client embedding/reranking dùng dịch vụ ngoài có xác thực và kiểm tra metadata model. Chúng không phải public API không cần token. Xem [Model licenses](MODEL_LICENSES.vi.md) và [Vận hành](OPERATIONS.vi.md).

## Xử lý lỗi và tương thích

HTTP status phụ thuộc vào phiên, CSRF, business rules và các gate. Khi chưa xác thực có thể chuyển về trang đăng nhập; thao tác không hợp lệ sẽ bị từ chối. Không nên viết client công khai dựa trên controller chưa có hợp đồng API riêng.
