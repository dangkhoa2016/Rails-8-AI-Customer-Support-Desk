# Engineering roadmap

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](ROADMAP.vi.md)

[Home](../README.md) · [Product scope](PRODUCT_SCOPE.md) · [Testing](TESTING.md)

This roadmap distinguishes **implemented functionality** from work that still needs evidence. Items are priorities, not promised delivery dates.

## Current verified foundation

- Rails 8 tenant workspace with fictional tickets, customers, staff and knowledge.
- Organization-scoped authorization and a separate Platform Admin identity.
- Versioned bilingual synthetic policy and knowledge fixtures.
- PostgreSQL with pgvector, optional authenticated embedding/reranker clients.
- Local Rails regression plus offline fixture validation.
- Password-gated read-only synthetic preview controls.

## Next work: application quality

- Expand accessibility and responsive UI testing with real browser devices.
- Add documented acceptance cases for staff/customer settings and authorization.
- Remove remaining legacy scripts that require non-public historical evidence.
- Improve developer onboarding and reproducible local fixture import.

## Next work: retrieval quality

- Establish broader independent bilingual question/answer reviews.
- Measure tenant isolation, answerability, source grounding and retrieval latency.
- Separate online-model availability from local storage/retrieval correctness.
- Record cost and GPU utilization only from actual execution evidence.

## Next work: production readiness

- Design and independently approve the private operator network perimeter.
- Establish durable audit retention and secure key escrow.
- Validate role separation, MFA recovery, backup/restore and monitoring.
- Add privacy/data retention and outbound communications integration contracts.

No item in the final section is represented as already deployed or security-certified.
