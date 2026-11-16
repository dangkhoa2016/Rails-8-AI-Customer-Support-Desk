# Lộ trình phát triển

> 🌐 Language / Ngôn ngữ: [English](ROADMAP.md) | **Tiếng Việt**

[Trang chính](../README.vi.md) · [Phạm vi](PRODUCT_SCOPE.vi.md) · [Kiểm thử](TESTING.vi.md)

Lộ trình này phân biệt **chức năng đã triển khai** với việc còn cần bằng chứng nghiệm thu. Các mục là thứ tự ưu tiên, không cam kết ngày hoàn thành.

## Nền tảng đã kiểm tra

- Giao diện Rails 8 tenant với ticket, khách hàng, nhân viên và knowledge giả lập.
- Phân quyền theo organization và danh tính Platform Admin riêng.
- Fixture chính sách/kiến thức giả lập có phiên bản song ngữ.
- PostgreSQL với pgvector và client embedding/reranking tùy chọn có xác thực.
- Rails regression và validation fixture offline.
- Cơ chế bảo vệ demo chỉ đọc bằng mật khẩu.

## Tiếp theo: chất lượng ứng dụng

- Mở rộng kiểm tra accessibility và responsive trên browser thực.
- Bổ sung acceptance case cho settings nhân viên/khách hàng và phân quyền.
- Giảm các script cũ vẫn phụ thuộc evidence lịch sử không công khai.
- Cải thiện hướng dẫn chạy local và import fixture có thể tái lập.

## Tiếp theo: chất lượng retrieval

- Mở rộng đánh giá độc lập các câu hỏi và câu trả lời tiếng Việt/Anh.
- Đo tenant isolation, answerability, grounding và latency.
- Tách trạng thái model online khỏi tính đúng đắn của dữ liệu/vector local.
- Chỉ báo cáo chi phí/GPU utilization theo execution evidence thực tế.

## Tiếp theo: sẵn sàng production

- Thiết kế và phê duyệt độc lập mạng riêng cho operator.
- Thiết lập lưu trữ audit bền vững và quản lý khóa an toàn.
- Kiểm tra role separation, khôi phục MFA, backup/restore và monitoring.
- Hoàn thiện privacy/retention và hợp đồng tích hợp gửi thông báo.

Không có mục nào trong nhóm production được tuyên bố đã deploy hoặc chứng nhận bảo mật.
