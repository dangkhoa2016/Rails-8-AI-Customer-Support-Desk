# Kiến trúc — Rails 8 AI Customer Support Desk

[English](ARCHITECTURE_EN.md) · [Tiếng Việt](ARCHITECTURE_VI.md) · [README](../README_VI.md)

## Tư duy kiến trúc

Ứng dụng Rails đa tenant, render giao diện tại server; PostgreSQL lưu dữ liệu nghiệp vụ, còn AI retrieval là chức năng hỗ trợ. Mô hình không được thay thế quyết định của nhân viên hỗ trợ.

Các nguyên tắc quan trọng:

- Mỗi request chỉ thao tác trên tenant đã được xác minh từ membership, **không tin tenant ID do browser hoặc AI đề xuất**.
- Danh tính tenant và quản trị nền tảng có **hai luồng xác thực, phân quyền độc lập**.
- Thao tác ghi nghiệp vụ phải được người có quyền thực hiện/duyệt. Văn bản AI không tự cấp quyền ghi.
- Kiến thức được duyệt, bản nháp và nội dung do mô hình trả về cần được phân biệt rõ ràng.
- Audit bảo mật, ghi chú nhân viên và tin nhắn công khai có các quyền đọc/ghi khác nhau.

## Các lớp chính

| Lớp | Vai trò | Thành phần |
| --- | --- | --- |
| UI | Trang SSR và cập nhật từng phần | Rails ERB, Turbo, Stimulus |
| Controller | Kiểm tra phiên, dữ liệu request và quyền | Controller ticket, customer, knowledge |
| Nghiệp vụ tenant | Ticket, khách hàng, nhân viên, hội thoại, settings | Active Record và organization associations |
| Tham chiếu nghiệp vụ | Thông tin SaaS/e-commerce để hỗ trợ khách hàng | Model TeamFlow/NovaMart, lookup chỉ đọc |
| Kho kiến thức | Bài viết, version, trạng thái duyệt, chunk, embedding | Knowledge article và embedding models |
| AI retrieval | Tìm ứng viên đúng tenant, kiểm tra relevance và reranking | Service tìm kiếm và Modal client tùy chọn |
| Xử lý nền | Job tìm kiếm AI bất đồng bộ tùy chọn | Active Job / Solid Queue |
| Quản trị nền tảng | Vòng đời tổ chức, tài khoản quản trị riêng, audit | Platform controller, PlatformAdmin |
| Lưu trữ | Quan hệ, ràng buộc và vector | PostgreSQL, pgvector |

### Luồng tenant

```text
Request
  → xác định phiên đăng nhập tenant
  → kiểm tra User + Membership + Organization đang hoạt động
  → xác minh quyền theo role
  → đọc dữ liệu thuộc đúng tenant
  → kiểm tra chuyển trạng thái/xác nhận của con người nếu ghi
  → lưu thay đổi cùng audit
  → render kết quả có giới hạn truy cập
```

`SupportDeskAccessPolicy` định nghĩa quyền theo vai trò `owner`, `admin`, `agent` và `viewer`. Ẩn nút trên giao diện không đủ để bảo vệ dữ liệu: controller/policy phải từ chối thao tác không hợp lệ.

### Platform Admin độc lập

`PlatformAdmin` không phải `User` hoặc `Membership`. Mục đích của Platform Console là quản trị tổ chức ở cấp nền tảng, không phải truy cập thay nhân viên hỗ trợ khách hàng. Luồng operator có password, TOTP MFA, thu hồi phiên và security audit riêng.

Sandbox bảo mật là khả năng đang được triển khai/kiểm tra trong môi trường local; **không đồng nghĩa Platform Console đã được triển khai production hoặc vượt qua kiểm toán độc lập**. Repository không đi kèm credential quản trị thật.

## Ticket, hội thoại và xử lý hỗ trợ

Luồng hỗ trợ phân biệt tin nhắn inbound/outbound, ghi chú chỉ dành cho nhân viên và metadata của ticket. Người dùng có quyền có thể tạo ticket, phân công và thay đổi trạng thái; các hành động được kiểm tra quyền và có audit.

Kết quả tìm kiếm AI chỉ là **nguồn tham khảo cho nhân viên**; không phải lệnh gửi phản hồi, hoàn tiền hay sửa trạng thái đơn hàng/gói dịch vụ.

## Hai miền nghiệp vụ

- **TeamFlow Cloud:** gói thuê bao, effective plan, hóa đơn, sự kiện kích hoạt, sự cố, workspace và API/export.
- **NovaMart Store:** đơn hàng, snapshot mặt hàng, thanh toán, shipment, fulfillment, yêu cầu đổi trả và bảo hành.

Đây là doanh nghiệp giả lập; chính sách phục vụ kiểm thử logic và phân quyền, không đại diện cho điều khoản thương mại ngoài đời.

## Pipeline AI retrieval

```text
Câu hỏi của nhân viên + tenant được phép
      |
      v
Kiểm tra input/quyền riêng tư
      |
      v
Qwen3-Embedding-4B (endpoint tùy chọn)
      |
      v
Truy vấn ứng viên pgvector trong đúng tenant
      |
      v
Qwen3-Reranker-4B (endpoint tùy chọn)
      |
      v
Kiểm tra nguồn, relevance, answerability
      |
      v
Kết quả có dẫn chứng để con người xem xét
```

Embedding đánh giá sử dụng `vector(2560)`. Client xác minh metadata model đã pin. Bản nháp không được tự chuyển thành nguồn chính sách đã duyệt; các lỗi hoặc kết quả không đủ bằng chứng phải được xử lý theo hướng an toàn.

Endpoint và credential inference được cấu hình riêng. Rails chạy được hoặc unit tests PASS **không chứng minh GPU endpoint bên ngoài đang sẵn sàng**.

## Bảo vệ dữ liệu

- Truy vấn và quan hệ PostgreSQL giới hạn theo organization; các ràng buộc giúp giảm nguy cơ tham chiếu chéo tenant.
- Audit hỗ trợ nội bộ và audit bảo mật nền tảng tách biệt.
- Preview công khai có mật khẩu và chặn ghi; sandbox quản trị chỉ bind localhost.
- Hai JSON chính sách nghiệp vụ trong repository là fixture giả lập, không phải cấu hình secret.

## Ngoài phạm vi minh chứng

Thiết kế mạng production, cấp phát tài khoản operator thật, giao tiếp outbound, quản lý khóa hạ tầng, đánh giá AI ở quy mô lớn và pentest bên ngoài chưa được chứng minh bằng những kiểm thử hiện có. Xem [Bảo mật](SECURITY_VI.md) và [Cài đặt local](LOCAL_DEVELOPMENT_VI.md).
