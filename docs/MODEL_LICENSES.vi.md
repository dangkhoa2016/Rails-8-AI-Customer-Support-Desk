# Giấy phép model và ghi nhận bên thứ ba

> 🌐 Language / Ngôn ngữ: [English](MODEL_LICENSES.md) | **Tiếng Việt**

[Trang chính](../README.vi.md) · [Giấy phép ứng dụng](../LICENSE) · [Văn bản Apache 2.0](../THIRD_PARTY_LICENSES/Apache-2.0.txt)

## Phạm vi cấp phép

Mã nguồn Rails 8 AI Customer Support Desk được phát hành theo **MIT License**. MIT **không thay thế** giấy phép riêng của các mô hình AI, pretrained weights, dataset, thư viện hoặc runtime inference bên ngoài.

Ứng dụng có các client tích hợp tùy chọn cho hai mô hình:

| Mục đích | Model chính thức | Giấy phép được công bố | Nguồn chính thức |
| --- | --- | --- | --- |
| Text embedding | `Qwen/Qwen3-Embedding-4B` | **Apache License 2.0** | [Hugging Face](https://huggingface.co/Qwen/Qwen3-Embedding-4B) |
| Reranking | `Qwen/Qwen3-Reranker-4B` | **Apache License 2.0** | [Hugging Face](https://huggingface.co/Qwen/Qwen3-Reranker-4B) |

**Qwen là đơn vị công bố model gốc.** Dự án không nhận quyền sở hữu model, không đóng gói model weights, tập dữ liệu huấn luyện, tokenizer hay toàn bộ gói model bên thứ ba. Người sử dụng tải chúng từ nguồn của đơn vị phát hành.

## Các thành phần được cung cấp

- `THIRD_PARTY_LICENSES/Apache-2.0.txt`: toàn văn Apache License 2.0 để tham khảo.
- Model ID và revision pin trong mã nguồn tích hợp.
- Link model card chính thức để kiểm tra điều kiện và thông báo riêng của model.
- Tài liệu ghi nhận bản quyền/giấy phép song ngữ này.

**Giấy phép Apache-2.0 không có nghĩa được bỏ qua các thông báo bản quyền, NOTICE, giấy phép dataset, quy định xuất khẩu hay điều khoản nhà cung cấp inference.** Điều khoản đi kèm đúng phiên bản model được tải cần được kiểm tra trước khi phân phối.

## Nếu cần phân phối kèm weights

1. Kiểm tra chính xác repository, revision và giấy phép của weights.
2. Giữ nguyên copyright, license và NOTICE do tác giả model cung cấp.
3. Ghi rõ model ID/revision trong gói deploy riêng.
4. Kiểm tra giấy phép của thư viện và runtime inference.
5. Không đưa weights hoặc token lên repository này khi chưa có đánh giá cấp phép/bảo mật phù hợp.

## Phân tách phạm vi

| Thành phần | Điều khoản áp dụng |
| --- | --- |
| Mã nguồn Rails do dự án viết | [MIT License của dự án](../LICENSE) |
| Weights Qwen embedding/reranking | Apache License 2.0 và thông báo từ upstream |
| Ruby gems, JS packages, runtime inference | Giấy phép riêng của từng thư viện |
| Dữ liệu nghiệp vụ giả lập | Fixture của dự án; không phải chính sách doanh nghiệp thật |
| Model inference có hosting | Điều khoản của nhà cung cấp, cấu hình tách biệt |

Việc bổ sung giấy phép và nguồn model giúp minh bạch nguồn gốc, **không tự bảo đảm tuân thủ pháp lý trong mọi trường hợp**. Cần kiểm tra nguồn cung và điều khoản ở đúng artifact trước khi deploy.

## Nguồn tham khảo

- [Model card chính thức Qwen3-Embedding-4B](https://huggingface.co/Qwen/Qwen3-Embedding-4B)
- [Model card chính thức Qwen3-Reranker-4B](https://huggingface.co/Qwen/Qwen3-Reranker-4B)
- [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0)

Rà soát gần nhất: tháng 11/2026.
