# Nguồn gốc chính sách và dữ liệu giả lập

> 🌐 Language / Ngôn ngữ: [English](DATA_GOVERNANCE.md) | **Tiếng Việt**

[Trang chính](../README.vi.md) · [Dữ liệu demo](DEMO_DATA.vi.md) · [Kiểm thử](TESTING.vi.md)

## Vì sao có hai file blueprint?

Fixture nghiệp vụ có **bản đặc tả gốc** và **bản đã phê duyệt**. Chúng khác mục đích, không phải hai bản sao dư thừa.

| File | Ý nghĩa |
| --- | --- |
| [`data/policy/source_blueprint.json`](../data/policy/source_blueprint.json) | Snapshot gốc để phát hiện việc tự ý sửa chính sách và tình huống nghiệp vụ giả lập |
| [`data/policy/canonical_blueprint.json`](../data/policy/canonical_blueprint.json) | Baseline đã duyệt, bổ sung metadata `policy_approval`, `policy_version` và `implementation_clarifications` |

Hai bản thống nhất ở doanh nghiệp, quy tắc nghiệp vụ gốc, tình huống tham chiếu, liên kết policy-knowledge và fixture. Bản duyệt **có bổ sung metadata và giải thích**, nên không được coi là giống hệt từng byte.

Các file được chuyển từ `docs/` sang `data/policy/` để tách artifact dữ liệu khỏi tài liệu hướng dẫn công khai. Nội dung JSON được giữ nguyên trong quá trình di chuyển.

## Những gì validator kiểm tra

`script/validate_approved_blueprint.py` kiểm tra:

- Hai tổ chức giả lập có chính sách khác nhau.
- Hai mươi policy ID và hai mươi reference cases.
- Năm mươi tiêu đề kiến thức cho mỗi tenant.
- Chỉ tiêu dữ liệu và evaluation split của hai doanh nghiệp.
- Chính sách nghiệp vụ gốc không tự thay đổi giữa hai bản.
- Metadata duyệt, giải thích song ngữ và mặc định cần human approval.

Đây là **kiểm tra fixture tĩnh**, không phải phê duyệt chính sách của doanh nghiệp thật, kiểm tra database production hoặc đánh giá độ chính xác AI.

## Các fixture khác

`data/` và `db/seeds/` chứa dữ liệu nghiệp vụ/kiến thức giả lập có thể tái lập. Log chạy thử không phải nguồn chính sách chuẩn. Không lấy đầu ra LLM thay thế chính sách đã duyệt.

## Quyền riêng tư

Chỉ sử dụng tên và dữ liệu giả lập. Không nhập PII thật, secret hoặc bản export của doanh nghiệp vào dataset mẫu. Nếu dùng với khách hàng thật, cần thiết kế độc lập về lưu trữ, truy cập, quyền riêng tư và cơ sở xử lý dữ liệu.

## Khi thay đổi policy

Thay đổi chính sách phải có lý do, được review và cập nhật tài liệu cả hai ngôn ngữ. Sửa validator, tests và fixture liên quan cùng lúc; không được tự chỉnh snapshot gốc chỉ để test PASS.
