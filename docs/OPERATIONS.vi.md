# Vận hành và bảo trì trên môi trường local

> 🌐 Language / Ngôn ngữ: [English](OPERATIONS.md) | **Tiếng Việt**

[Trang chính](../README.vi.md) · [Cài đặt local](LOCAL_DEVELOPMENT.vi.md) · [Kiểm thử](TESTING.vi.md)

## Phạm vi vận hành

Repository là **ứng dụng phát triển/đánh giá với dữ liệu giả lập**, không đóng gói môi trường production hoàn chỉnh. Cần tách biệt demo tenant, PostgreSQL, inference tùy chọn và Platform Console bị giới hạn truy cập.

## Checklist khởi động

1. Kiểm tra checkout và `git status --short`.
2. Sử dụng Ruby tương thích, cài dependencies theo `Gemfile.lock`.
3. Khởi động PostgreSQL local có pgvector.
4. Thiết lập `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` và test database riêng.
5. Chạy `bin/rails db:migrate` chỉ vào **đúng database local**.
6. Bind giao diện demo tenant vào `127.0.0.1`, kiểm tra `GET /healthz`.
7. Tắt inference mặc định khi endpoint, token và ngân sách chưa được cho phép.

## Background jobs

Ứng dụng có Solid Queue lưu trên PostgreSQL để hỗ trợ AI search bất đồng bộ tùy chọn. Web server chạy được **không có nghĩa worker đang hoạt động**. Khi bật background jobs cần kiểm tra queue adapter, worker và trạng thái job.

Không tự khởi chạy inference GPU có chi phí chỉ để test tài liệu. Log không được tiết lộ token hoặc dữ liệu tenant ra nơi chưa được phép.

## Quản lý dữ liệu

- Sao lưu database tách biệt với mã nguồn Git.
- Chỉ dùng `pg_dump`/`pg_restore` khi có quyền và đã xác minh database đích.
- Portable dump có thể không giữ nguyên owner và grants của PostgreSQL.
- Sau khi restore sandbox đặc quyền, phải duy trì quyền bảo vệ audit và role độc lập.
- Không commit `.env` riêng, secret hoặc URL hạ tầng nội bộ.

## Quan sát hoạt động

Dùng health endpoint, Rails logs, kiểm tra database và trạng thái job để chẩn đoán. Chỉ báo cáo số liệu timing/model usage có bằng chứng về môi trường và cỡ mẫu. Khởi động Rails thành công không chứng minh đã đủ năng lực production hay độ chính xác AI.

## Bảo mật

Không đưa đăng nhập demo không mật khẩu ra Internet. Remote preview cần thêm mật khẩu và chặn ghi; Platform Admin sandbox chỉ chạy nội bộ. Xem [Bảo mật](SECURITY.vi.md).

## Khôi phục

Khôi phục mã nguồn Git, database tương thích và quyền PostgreSQL, rồi kiểm tra migrations, fixture, auth boundary và Rails tests trước khi bật inference. Xem [Khắc phục sự cố](TROUBLESHOOTING.vi.md).
