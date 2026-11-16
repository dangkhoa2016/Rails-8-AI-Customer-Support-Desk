# Cài đặt và kiểm thử trên máy phát triển

[English](LOCAL_DEVELOPMENT.md) · [Tiếng Việt](LOCAL_DEVELOPMENT.vi.md) · [README](../README.vi.md)

Tài liệu này hướng dẫn chạy **demo local với dữ liệu giả lập**. Đây không phải hướng dẫn triển khai Platform Console production hay cấu hình GPU inference công khai.

## Yêu cầu

- Ruby 3.3 và Bundler. File `.ruby-version` hiện khai báo **3.3.8**; bộ test trên Colab được khôi phục cũng đã PASS với **3.3.13**.
- PostgreSQL và extension **pgvector**.
- Một PostgreSQL role có quyền sử dụng **database development/test riêng biệt**.
- Git và terminal.

Không chạy importer demo vào database chứa dữ liệu khách hàng. Hãy sử dụng cơ sở dữ liệu thử nghiệm tách biệt và tự bảo quản bản sao nếu cần giữ dữ liệu.

## 1. Tải mã nguồn

```bash
git clone https://github.com/dangkhoa2016/Rails-8-AI-Customer-Support-Desk.git
cd Rails-8-AI-Customer-Support-Desk
bundle install
```

Chọn Ruby tương thích trước khi chạy Bundler. Có thể tra cứu dependency cụ thể trong `Gemfile` và `Gemfile.lock`.

## 2. Cấu hình PostgreSQL

Ứng dụng đọc các biến môi trường thông thường. Đặt giá trị qua **cơ chế lưu secrets riêng trên máy**, không commit:

| Biến | Mục đích |
| --- | --- |
| `PGHOST` / `PGPORT` | Máy chủ và cổng PostgreSQL |
| `PGUSER` / `PGPASSWORD` | Tài khoản PostgreSQL chỉ dành cho local |
| `PGDATABASE` | Database development |
| `PGTESTDATABASE` | Database test riêng |
| `RAILS_ENV` | `development` khi xem demo |
| `M1_SYNTHETIC_DEMO` | `YES` để bật luồng dữ liệu giả lập dành cho dev |

Hãy chọn database local chưa sử dụng và xuất các biến môi trường tại terminal. **Không copy mật khẩu từ ảnh chụp màn hình, notebook, JSON trong repository hoặc tài khoản demo.**

Các migrations sử dụng một số chức năng riêng của PostgreSQL và pgvector. Máy chủ cần có extension `vector` sẵn để thực thi đủ migrations.

## 3. Tạo database và nhập dữ liệu cơ bản

```bash
export RAILS_ENV=development
export M1_SYNTHETIC_DEMO=YES

bin/rails db:create
bin/rails db:migrate
bin/rails runner db/seeds/m1_full_business_records.rb
```

Importer M1 tạo dữ liệu giả lập có thể tái lập cho hai doanh nghiệp. Các bộ knowledge và ticket mở rộng có script nhập/kiểm thử riêng; chỉ chạy khi bạn thực sự cần mở rộng demo.

Trước khi chạy, hãy kiểm tra `db/seeds/` và `script/` để chắc chắn đúng database. **Không chạy `db:reset` hoặc xóa database hiện tại** chỉ để làm lại demo.

## 4. Chạy Rails localhost

```bash
bin/rails server --binding 127.0.0.1 --port 3000
```

Mở `http://127.0.0.1:3000/demo/sign_in`. Màn hình chọn membership demo chỉ dành cho kiểm thử local với dữ liệu giả lập; **không được công bố trực tiếp lên Internet**.

Bạn có thể xem ticket, khách hàng, bài viết, quyền nhân viên và thông tin nghiệp vụ. Số lượng dữ liệu thực tế tùy thuộc các bộ sample đã nhập.

## 5. Chạy kiểm thử

Cấu hình `PGTESTDATABASE` trỏ tới database test độc lập rồi chạy:

```bash
RAILS_ENV=test bin/rails db:migrate
RAILS_ENV=test bin/rails test
```

Bộ Rails regression trước khi làm sạch tài liệu đã chạy **184 tests và 5.888 assertions, không failures/errors** vào ngày 16/11/2026. Bộ test bao phủ nhiều tình huống tenant isolation và nghiệp vụ mẫu, nhưng **không thay thế một cuộc đánh giá bảo mật production**.

Các script kiểm tra dataset và kết nối model nằm dưới `script/`, `test/`. Một số cần credential riêng hoặc bằng chứng thử nghiệm lịch sử và **không thuộc quy trình cài đặt Rails cơ bản**.

## AI integration tùy chọn

Giao diện AI Search có điều kiện kích hoạt rõ ràng. Nếu cần inference, phải cấu hình endpoint, token theo model và xác thực proxy một cách riêng biệt. Xem `ModalEmbeddingClient`, `ModalRerankerClient`, `KnowledgeAISearchController` để biết hợp đồng biến môi trường.

Không ghi khóa API vào Git, notebook công khai, browser response hoặc README. Không mặc định tạo job GPU; cần kiểm tra quyền và ngân sách trước. Demo chăm sóc khách hàng cơ bản không yêu cầu GPU.

## Giới hạn bảo mật

- **Không** mở màn hình demo không cần mật khẩu ra Internet.
- Không expose sandbox Platform Admin/localhost operator trong demo tenant.
- Tách biệt danh tính tenant và nền tảng; kiểm tra membership ở server.
- Không coi gợi ý AI là chính sách đã duyệt hoặc quyền sửa dữ liệu.
- Không đưa dữ liệu khách hàng thật vào fixture giả lập nếu chưa có thiết kế bảo mật/quyền riêng tư riêng.

Đọc [Bảo mật](SECURITY.vi.md), [Kiến trúc](ARCHITECTURE.vi.md) và [Dữ liệu demo](DEMO_DATA.vi.md).
