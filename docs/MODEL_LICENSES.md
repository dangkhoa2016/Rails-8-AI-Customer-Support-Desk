# Model licenses and third-party attribution

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](MODEL_LICENSES.vi.md)

[Home](../README.md) · [Licensing](../LICENSE) · [Third-party Apache 2.0 text](../THIRD_PARTY_LICENSES/Apache-2.0.txt)

## Scope

The Rails 8 AI Customer Support Desk source code is distributed under the **MIT License**. This does **not** change the licenses of external machine-learning models, libraries, pretrained weights, datasets, or model-serving runtimes.

The application has optional integration clients for the following third-party models:

| Purpose | Official model | Reported upstream license | Official model page |
| --- | --- | --- | --- |
| Text embedding | `Qwen/Qwen3-Embedding-4B` | **Apache License 2.0** | [Hugging Face](https://huggingface.co/Qwen/Qwen3-Embedding-4B) |
| Text reranking | `Qwen/Qwen3-Reranker-4B` | **Apache License 2.0** | [Hugging Face](https://huggingface.co/Qwen/Qwen3-Reranker-4B) |

**Qwen is the upstream model publisher.** This repository neither claims ownership of these models nor redistributes the weights, training corpora, tokenizer assets, or full third-party model packages. Users obtain such assets from their respective publishers.

## What is included

- `THIRD_PARTY_LICENSES/Apache-2.0.txt`: complete Apache License 2.0 terms for reference.
- Model IDs and pinned revision references in the application integration code.
- Links to official model cards, where model-specific conditions and notices can be reviewed.
- This bilingual attribution and distribution policy.

**A model's Apache-2.0 designation must not be interpreted as permission to bypass third-party notices, copyright statements, dataset licenses, export controls, or the terms of a particular inference provider.** The model card and upstream license at the exact version downloaded take precedence for their own assets.

## Before packaging model weights

1. Verify the exact upstream repository, revision and license accompanying the weights.
2. Preserve copyright, license and NOTICE files supplied with the model.
3. Record the model identifier/revision in any separate deployment bundle.
4. Check all additional dependencies and serving runtimes for their own obligations.
5. Keep external model weights and tokens out of this application's source distribution unless separately reviewed and permitted.

## Separation of responsibilities

| Asset | Governing terms |
| --- | --- |
| Original Rails application code | [Project MIT License](../LICENSE) |
| Qwen embedding and reranker weights | Apache License 2.0 and applicable upstream notices |
| Ruby gems, JS packages and inference runtimes | Their individual upstream licenses |
| Synthetic business data | Project fixture material; do not treat as real-business policies |
| Hosted model inference | Provider terms and authentication, separately configured |

The inclusion of an Apache license text and model attributions supports compliance documentation; it is **not a guarantee of legal compliance** in every jurisdiction. Review the exact artifact supply chain before a public model deployment.

## Sources

- [Official Qwen3-Embedding-4B model card](https://huggingface.co/Qwen/Qwen3-Embedding-4B)
- [Official Qwen3-Reranker-4B model card](https://huggingface.co/Qwen/Qwen3-Reranker-4B)
- [Apache License version 2.0](https://www.apache.org/licenses/LICENSE-2.0)

Last reviewed: November 2026.
