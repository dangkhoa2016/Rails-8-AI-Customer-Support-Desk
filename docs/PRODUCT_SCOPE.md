# Product scope and boundaries

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](PRODUCT_SCOPE.vi.md)

[Home](../README.md) · [Architecture](ARCHITECTURE.md) · [Roadmap](ROADMAP.md)

## Goal

Provide a realistic Rails customer-support workspace where a staff member can inspect authorized business records, handle tickets and consult an approved bilingual knowledge base. AI improves knowledge discovery while people remain accountable for customer-facing decisions.

## Implemented in this repository

| Workstream | Demonstrated behavior |
| --- | --- |
| Tenant workspace | Organization-scoped dashboards, tickets, conversations and customer records |
| Support operations | Assignment, ticket status, internal/public messages and role-specific controls |
| Team management | Membership-based `owner`, `admin`, `agent` and `viewer` permissions |
| Knowledge | Versioned articles, editorial approval and searchable chunks |
| AI retrieval | Optional embedding/reranking integration, pgvector storage and evidence-aware search |
| Business records | Synthetic TeamFlow billing/activation and NovaMart order/fulfillment |
| Platform | Dedicated PlatformAdmin authentication, local lifecycle and audit isolation |
| Localization | English/Vietnamese presentation and synthetic content |
| Engineering quality | Rails regression, offline policy checks, reproducible development fixtures |

## Sample data

The reference evaluation database included two fictional tenants and 240 support tickets. These counts are not tenant limits or benchmark population guarantees. The application does not bundle genuine customer data.

## Deliberately not promised

- A publicly operated multi-tenant SaaS product with production service-level commitments.
- Real-payment, email, telephony or shipping-provider integrations.
- Autonomous refunds, subscription changes, outgoing replies or article approvals by an LLM.
- Production provisioning, public access to the platform console or real operator enrollment.
- Continuously available GPU endpoints, external inference quality guarantees or completed model benchmark acceptance.
- External security certification or legal compliance assessment.

## Human review is a product requirement

Retrieval sources help agents decide; they do not become instructions to perform a business write. Role checks, source provenance, state transitions and tenant boundaries are enforced independently of model responses.

For operational assumptions, read [Security](SECURITY.md) and [Deployment](DEPLOYMENT.md).
