# Hướng dẫn đóng góp

> 🌐 Language / Ngôn ngữ: [English](CONTRIBUTING.md) | **Tiếng Việt**

Cảm ơn bạn đã giúp cải thiện dự án support desk Rails song ngữ với dữ liệu giả lập.

## Trước khi sửa

1. Đọc [Kiến trúc](../docs/ARCHITECTURE.vi.md), [Bảo mật](SECURITY.vi.md) và [Model license](../docs/MODEL_LICENSES.vi.md).
2. Tạo issue cho tính năng lớn hoặc thay đổi dữ liệu chính sách.
3. Tái hiện lỗi bằng **dữ liệu giả lập**, không dùng thông tin khách hàng thực.
4. Giữ Platform Admin độc lập với tenant. AI không được tự ghi dữ liệu nghiệp vụ.
5. Không gửi token, weights, log nội bộ, dữ liệu cá nhân hoặc ảnh có secret.

## Phát triển

- Cài Ruby 3.3, PostgreSQL/pgvector, Bundler và dependencies.
- Làm theo [Cài đặt local](../docs/LOCAL_DEVELOPMENT.vi.md).
- Chạy `python3 script/check_public_docs.py`, `python3 script/validate_approved_blueprint.py` và `RAILS_ENV=test bundle exec rails test`.
- Mỗi thay đổi nên rõ phạm vi, dễ review; không đưa lại log chạy thử nội bộ vào docs.
- Cập nhật **đồng thời bản tiếng Anh và tiếng Việt** của tài liệu liên quan.

## Pull request

Trình bày lý do, phạm vi, thay đổi database/bảo mật, test đã chạy và giới hạn còn lại. Đính kèm issue nếu có. Nếu sửa phần tích hợp model, phải kiểm tra giấy phép upstream và ghi rõ model/revision.

PR chỉ sửa docs vẫn cần kiểm tra link và đủ cặp ngôn ngữ. Xem [mẫu pull request](PULL_REQUEST_TEMPLATE.vi.md).

## Giấy phép

Đóng góp cho mã nguồn gốc áp dụng [MIT License](../LICENSE). Model và các thành phần bên thứ ba giữ giấy phép riêng.
