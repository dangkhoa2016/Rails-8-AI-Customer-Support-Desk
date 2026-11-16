# Khắc phục sự cố

> 🌐 Language / Ngôn ngữ: [English](TROUBLESHOOTING.md) | **Tiếng Việt**

[Trang chính](../README.vi.md) · [Vận hành](OPERATIONS.vi.md) · [Kiểm thử](TESTING.vi.md)

## Rails không kết nối được PostgreSQL

Kiểm tra `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`. Xác nhận PostgreSQL đang chạy và database tồn tại. Development, test và sandbox quản trị giới hạn không được tự trỏ chung một database.

Không in password vào log hoặc commit cấu hình thật trong YAML.

## PostgreSQL không nhận kiểu `vector`

Kiểm tra pgvector và extension `vector` có sẵn trên đúng database. Dự án có migration chuyển cột embedding từ 1024 sang 2560 chiều; thiếu migration sẽ gây lệch schema.

Đôi khi Active Record generic client báo không nhận OID vector; điều đó chưa chứng minh dữ liệu vector lỗi. Hãy kiểm tra kiểu cột và truy vấn pgvector thực tế trong PostgreSQL.

## `db:prepare` báo thiếu quyền

Một số role giới hạn không được tạo database. Hãy tạo test database riêng bằng tài khoản được phép, cài extension rồi migrate. Không cấp quyền `CREATEDB` rộng cho tài khoản ứng dụng production chỉ để test.

## AI search chưa sẵn sàng

Giao diện support hoạt động được khi không có GPU. AI search tùy chọn yêu cầu endpoint, credential, metadata model và kiến thức đã duyệt. Nếu readiness gate đang chặn, phải giữ nguyên thay vì tự sinh câu trả lời không có chứng cứ.

Không công khai token hoặc bật GPU có tính phí chỉ để xem giao diện.

## Không có quyền tenant

Kiểm tra user đang hoạt động, membership thuộc đúng organization, role cho phép thao tác và organization còn active. Platform Admin không phải một tenant membership.

## Preview chuyển về trang đăng nhập

Chọn tài khoản demo chỉ dành cho localhost. Remote preview cần lớp mật khẩu riêng, Host được tin cậy và session cookie. Redirect lặp có thể do cookie hoặc hostname không khớp.

## HTTP 405 khi POST trên preview công khai

Đây là hành vi mong muốn ở chế độ chỉ đọc với business writes và AI search. **Không bỏ gate chỉ để demo dễ hơn.** Tuyệt đối không expose Platform Admin qua tunnel công khai.

## Lệch giữa local và CI

Kiểm tra `Gemfile.lock`, `.ruby-version`, PostgreSQL và pgvector khớp workflow. Test local PASS không chứng minh GitHub CI PASS. Cần xem logs thực của workflow và chạy test sau khi thay dependency.

## Cần trợ giúp?

Tạo issue đã ẩn dữ liệu nhạy cảm theo [mẫu](../.github/ISSUE_TEMPLATE/bug_report.vi.yml), hoặc đọc [Hỗ trợ](../.github/SUPPORT.vi.md). Báo cáo bảo mật cần gửi riêng.
