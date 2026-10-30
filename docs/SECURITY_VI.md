# Bảo mật và nguyên tắc đánh giá

[English](SECURITY_EN.md) · [Tiếng Việt](SECURITY_VI.md) · [README](../README_VI.md)

Tài liệu mô tả **các ranh giới bảo mật đã triển khai hoặc kiểm thử trong mã nguồn**, không phải chứng nhận hệ thống đã sẵn sàng production. Tenant và tài khoản mẫu đều là giả lập. Triển khai thực tế cần thiết kế hạ tầng và kiểm toán bảo mật độc lập.

## Các ranh giới tin cậy

1. **Danh tính tenant:** `User` chỉ thao tác thông qua `Membership` hợp lệ của `Organization` đang hoạt động. `SupportDeskAccessPolicy` xác định quyền của từng hành động; tenant lấy từ phiên đã xác thực, không tin dữ liệu do client tự gửi.
2. **Danh tính nền tảng:** `PlatformAdmin` là loại tài khoản riêng, không tự có membership hay quyền xem khách hàng/ticket của tenant.
3. **Nguồn kiến thức:** Bài đã duyệt, bản nháp và kết quả mô hình là ba loại nội dung khác nhau. Đầu ra AI không phải chính sách bảo mật hoặc quyền sử dụng dịch vụ.
4. **Con người kiểm soát:** Public reply, approval và thao tác ghi nghiệp vụ phải là hành động rõ ràng do người có quyền thực hiện.
5. **Giới hạn preview:** Đăng nhập demo không mật khẩu chỉ dành cho local development. Preview bên ngoài phải có thêm mật khẩu bảo vệ và từ chối các thao tác ghi nghiệp vụ theo mặc định.

## Phân quyền theo vai trò

Ứng dụng có các role tenant `owner`, `admin`, `agent`, `viewer`. Quyền được kiểm tra đối với đọc/tạo/sửa ticket, trả lời công khai, xem ghi chú nội bộ, phân công nhân sự, quản lý khách hàng, duyệt kiến thức và đổi cấu hình.

Ma trận quyền thực tế nằm trong `SupportDeskAccessPolicy`. Server phải kiểm tra quyền ngay cả khi UI đã ẩn nút thao tác.

## Platform Admin độc lập

Luồng quản trị nền tảng có password session riêng, TOTP MFA, giới hạn đăng nhập/lockout và khả năng thu hồi phiên. Các thao tác vòng đời tổ chức và security events được audit tách khỏi nghiệp vụ hỗ trợ thông thường.

Sandbox quản trị local không được mở qua public tunnel. **Repository không cung cấp tài khoản Platform Admin thật**, và kiểm thử local không chứng minh việc khôi phục MFA bởi người giám sát độc lập, mạng riêng hay audit offsite bất biến đã được triển khai.

## Lưu trữ và nhật ký kiểm tra

PostgreSQL lưu dữ liệu theo organization. Các bài test và sandbox độc lập thể hiện phân tách role và ownership của bảng audit đặc quyền. Tuy nhiên vận hành thật vẫn cần chính sách lưu giữ audit bên ngoài, quy trình cấp quyền, diễn tập khôi phục và đánh giá độc lập.

## An toàn AI retrieval

Endpoint AI là tích hợp tùy chọn. Credential inference phải được quản lý bên ngoài Git và không bao giờ gửi sang browser hoặc báo cáo lỗi công khai. Kiểm tra input, giới hạn tenant, trạng thái duyệt kiến thức và relevance gate giúp hạn chế kết quả sai nguồn hoặc vượt phạm vi doanh nghiệp.

**Đề xuất của AI không thể tự thay đổi gói dịch vụ, hoàn tiền, giao hàng, gửi public reply hay phê duyệt chính sách.**

## Hướng dẫn sử dụng an toàn

- Chỉ dùng dữ liệu giả lập.
- Không công bố màn hình demo không cần mật khẩu lên Internet.
- Không commit mật khẩu DB, khóa phiên hoặc model token.
- Xem tin nhắn người dùng và đầu ra AI là dữ liệu không đáng tin cậy cho đến khi kiểm tra.
- Không đăng URL quản trị riêng, credential thật, quyết định bảo mật nội bộ hoặc runbook vận hành.
- Chạy test bằng database riêng; không sử dụng dữ liệu production.

## Những điều chưa thể cam kết

Repository **không tự nhận đã pentest, chứng nhận bảo mật, đạt SOC 2 hoặc sẵn sàng production**. SSO doanh nghiệp, bảo vệ máy chủ, quản lý khóa, immutable audit offsite, người giám sát MFA, tuân thủ quyền riêng tư và ứng phó sự cố cần thiết kế/kiểm thử riêng.

Nếu phát hiện lỗ hổng, hãy liên hệ maintainer bằng kênh riêng thay vì công khai mã khai thác hoặc credentials trong issue.

Đọc [Kiến trúc](ARCHITECTURE_VI.md) và [Cài đặt local](LOCAL_DEVELOPMENT_VI.md) để hiểu thêm.
