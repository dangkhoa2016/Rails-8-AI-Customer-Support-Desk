# Chính sách bảo mật

> 🌐 Language / Ngôn ngữ: [English](SECURITY.md) | **Tiếng Việt**

## Phạm vi được hỗ trợ

Repository là dự án development đã kiểm thử trên dữ liệu giả lập, không phải dịch vụ production được chứng nhận. Báo cáo bảo mật nên tập trung vào nhánh `main` hiện hành và lỗi có thể tái lập.

## Báo cáo lỗ hổng riêng tư

**Email: i.am@dangkhoa.dev**

Hãy cung cấp commit bị ảnh hưởng, cách tái hiện tối thiểu với dữ liệu giả lập, tác động bảo mật và log đã ẩn thông tin nhạy cảm. Không đăng access token, dữ liệu cá nhân, dữ liệu khách hàng thực hoặc mã khai thác lên public issue.

## Ranh giới tin cậy

- `User`/`Membership` tenant và `PlatformAdmin` nền tảng là hai loại danh tính độc lập.
- Server luôn phải kiểm tra tenant; chỉ ẩn UI không cấp hoặc thu hồi được quyền.
- AI không tự duyệt kiến thức, gửi reply hoặc thay đổi dữ liệu nghiệp vụ.
- Không mở sandbox Platform Admin local qua public tunnel.
- Chọn tài khoản demo không mật khẩu chỉ dành cho local và dữ liệu giả lập.

## Kỳ vọng xử lý

Maintainer xem xét báo cáo theo khả năng; không cam kết thời gian phản hồi hay SLA bảo mật production. Khắc phục có thể gồm sửa mã nguồn, cập nhật tài liệu hoặc cấu hình.

Xem [Mô hình bảo mật](../docs/SECURITY.vi.md) để hiểu chi tiết.
