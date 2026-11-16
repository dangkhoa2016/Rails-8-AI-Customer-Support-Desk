# Chiến lược kiểm thử và nghiệm thu

> 🌐 Language / Ngôn ngữ: [English](TESTING.md) | **Tiếng Việt**

[Trang chính](../README.vi.md) · [Cài đặt local](LOCAL_DEVELOPMENT.vi.md) · [CI](../.github/workflows/ci.yml)

## Các nhóm kiểm thử

Repository có Rails/Minitest regression, Python validator cho dữ liệu chính sách/knowledge và các probe inference bên ngoài tùy chọn. Mỗi nhóm có phạm vi và điều kiện riêng; không được gộp thành một con số khẳng định chất lượng AI.

| Bộ test | Lệnh | Mục đích |
| --- | --- | --- |
| Ứng dụng Rails | `RAILS_ENV=test bundle exec rails test` | Controller, quyền truy cập và nghiệp vụ support |
| Autoloading | `bundle exec rails zeitwerk:check` | Kiểm tra các class Rails |
| Chính sách giả lập | `python3 script/validate_approved_blueprint.py` | Đối chiếu chính sách gốc và bản duyệt |
| Kho kiến thức | `python3 -m unittest discover -s test -p 'test_m2_knowledge.py' -v` | Tính nhất quán của fixture offline |
| Tài liệu công khai | `python3 script/check_public_docs.py` | Cặp ngôn ngữ, link và mẫu nội dung nhạy cảm |
| Inference tùy chọn | Script được chọn trong `script/`, `modal_app/` | Cần endpoint và ngân sách được cho phép |

## Yêu cầu môi trường

- Database PostgreSQL test riêng, có extension pgvector.
- Ruby tương thích `.ruby-version`, Bundler theo `Gemfile.lock`.
- Không dùng dữ liệu tenant thật hoặc credential production.
- Biết chính xác commit và trạng thái migration.

Chuẩn bị test database bằng `RAILS_ENV=test bundle exec rails db:migrate`; có thể dùng `db:prepare` nếu role có đủ quyền. Không tăng quyền DB quá mức chỉ để làm test PASS.

## Kết quả đã quan sát

Môi trường synthetic khôi phục từng ghi nhận **184 Rails tests, 5.888 assertions, 0 failures, 0 errors, 0 skips** ngày 16/11/2026. Quá trình dọn tài liệu cũng PASS 14 bài test knowledge offline và blueprint validation. Đây là số liệu thực tế local, **không phải tuyên bố CI của commit tương lai đã PASS**.

## Các tình huống bảo mật

1. Membership tenant không được đọc ticket hoặc khách hàng của tenant khác.
2. Viewer/agent/admin/owner có quyền khác nhau.
3. Platform Admin không mặc nhiên có quyền tenant.
4. Public preview chặn thao tác ghi và tạo job AI.
5. Audit và role đặc quyền phải được cách ly.
6. AI không được tự ghi dữ liệu nghiệp vụ.

## Báo cáo

Dùng PASS/FAIL/NOT_RUN cho **lệnh và môi trường đã kiểm tra thực sự**. Ghi rõ lỗi, tình trạng GPU ngoài và dữ liệu synthetic. Không kết luận production-ready chỉ vì test cũ từng thành công.

CI nằm tại [`.github/workflows/ci.yml`](../.github/workflows/ci.yml), chỉ có kết quả chính thức sau khi GitHub chạy workflow trên commit được công bố.
