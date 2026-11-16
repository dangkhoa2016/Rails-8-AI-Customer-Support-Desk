# Pull request

> 🌐 Language / Ngôn ngữ: [English](PULL_REQUEST_TEMPLATE.md) | **Tiếng Việt**

## Tóm tắt
Mô tả sửa đổi, lý do và issue liên quan (nếu có).

## Phạm vi và tương thích
- [ ] Thay đổi có một mục đích rõ ràng, không lẫn refactor không liên quan
- [ ] Giữ cách ly tenant và Platform Admin
- [ ] Không thêm token, weights, dữ liệu khách hàng thật hoặc log nội bộ
- [ ] Migrations và fixture dữ liệu giả lập không bị hỏng

## Kiểm thử
- [ ] Đã chạy Rails tests (ghi rõ lệnh/kết quả thực tế)
- [ ] Đã kiểm tra tài liệu công khai và cặp ngôn ngữ
- [ ] Đã cập nhật cả EN và VI khi cần
- [ ] Đã xem xét giấy phép model và thư viện bên thứ ba

## Bằng chứng và giới hạn
Tóm tắt kết quả xác minh, phần chưa kiểm tra và đánh giá thủ công cần thiết. Không ghi PASS nếu kiểm thử chưa chạy.
