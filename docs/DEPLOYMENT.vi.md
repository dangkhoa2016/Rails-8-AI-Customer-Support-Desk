# Giới hạn triển khai và khả năng di chuyển

> 🌐 Language / Ngôn ngữ: [English](DEPLOYMENT.md) | **Tiếng Việt**

[Trang chính](../README.vi.md) · [Vận hành](OPERATIONS.vi.md) · [Bảo mật](SECURITY.vi.md)

## Hồ sơ triển khai được minh chứng

Mã nguồn hiện thể hiện **ứng dụng Rails local development/evaluation với dữ liệu nghiệp vụ giả lập**. Repository không đóng gói production công khai, credential operator thật, nghiệm thu an ninh độc lập hoặc lưu trữ audit offsite bất biến.

Không dùng đường dẫn Colab, port notebook hay Quick Tunnel tạm làm cấu hình cố định.

## Thành phần

- Rails 8 và giao diện Active Record/Hotwire.
- PostgreSQL có pgvector (môi trường đánh giá đã dùng PostgreSQL 16).
- Solid Queue tùy chọn cho AI search bất đồng bộ.
- Dịch vụ embedding/reranking có xác thực và chạy ngoài Rails.
- Danh tính Platform Admin độc lập và ranh giới audit riêng.

## Trước khi chuyển host

1. Kiểm tra Ruby/Bundler tương thích `Gemfile.lock`.
2. Chuẩn bị PostgreSQL và role riêng; kiểm tra extension.
3. Cấp secret qua secret manager/runtime bảo vệ, không lưu Git.
4. Chạy migration trên **database đã biết và đã backup**, sau đó kiểm tra tenant isolation.
5. Hoàn thiện TLS, access control, trusted proxy/host validation trước khi nhận public traffic.
6. Tách preview giả lập chỉ đọc khỏi giao diện operator riêng.
7. Chỉ bật worker và model endpoints sau khi phê duyệt vận hành.
8. Độc lập kiểm tra log, backup, restore, monitoring và MFA của operator.

## Demo và production khác nhau

Quick Tunnel tạm chỉ phù hợp với **demo giả lập có mật khẩu, chặn ghi** bằng mã nguồn. URL tạo ra không phải endpoint ổn định.

Platform Admin phải ở sau mạng riêng đã được review; expose sandbox ra Internet **không phải cách triển khai được hỗ trợ**.

## Điều kiện đưa khách hàng thật vào

Cần xác minh cách ly tenant, provisioning tài khoản, DB/audit roles, backup bền vững và quản lý khóa, quyền riêng tư, ứng phó sự cố, giám sát, khả năng tiếp cận giao diện và pentest độc lập.

**Rails test local PASS không đồng nghĩa đã được cho phép production.**
