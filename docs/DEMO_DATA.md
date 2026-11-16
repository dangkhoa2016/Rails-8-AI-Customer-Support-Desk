# Synthetic business data and evaluation fixtures

[English](DEMO_DATA.md) · [Tiếng Việt](DEMO_DATA.vi.md) · [Back to README](../README.md)

## About the dataset

This project models two **entirely fictional organizations**. Their prices, policies, people, subscriptions, orders and support conversations exist only to exercise a multi-tenant support application. They are not the terms of service of real businesses.

| Aspect | TeamFlow Cloud | NovaMart Store |
| --- | --- | --- |
| Industry | B2B SaaS | E-commerce |
| Focus | Subscription, activation and billing support | Orders, shipments, returns and warranty support |
| Example entity types | Workspace, subscription, invoice, activation, incident | Product, order, payment, shipment, return, warranty |
| Knowledge catalog | 50 synthetic article titles | 50 synthetic article titles |
| Ticket target for expanded fixture | 120, split VI/EN | 120, split VI/EN |

The restored development snapshot used for November 2026 acceptance included **2 organizations, 8 users, 8 memberships, 240 tickets, 440 ticket messages, 12 reviewed knowledge versions and 84 embeddings**. These are measurements of that snapshot, **not** hardcoded software limits.

## Example support scenarios

### TeamFlow Cloud

- An invoice is paid but the associated subscription upgrade is not active.
- A plan change is scheduled but its effective date differs from the requested date.
- A support agent must inspect billing records without changing entitlements.
- A service incident or export job requires a contextual explanation.

### NovaMart Store

- A customer reports a partially delivered order.
- A payment is received but some items have not shipped.
- A return or warranty question depends on the relevant item and delivery record.
- A support agent must distinguish a refund request from an approved refund.

Each scenario encourages the operator to inspect verified business records before composing a response.

## Knowledge content

The repository includes a deterministic bilingual knowledge corpus. Article versions have editorial state and associated chunks, and reviewed knowledge can be connected to vector embeddings.

The 84 stored `vector(2560)` values in the restored database were linked to reviewed chunks. They demonstrate a working retrieval data path, but are not proof that every article is approved, every question is answerable or every model deployment is currently available.

## Data ownership and permissions

Business records belong to one `Organization`; user access is determined by `Membership`. A sample customer's order or invoice must never be disclosed to a different tenant just because its identifier was supplied by a request or an LLM.

Support agents can inspect authorized context, but **AI cannot autonomously modify business entities or send a public answer**. The intended flow is human review and an explicit authorized action.

## Reproducibility

The project contains versioned source data in `data/`, seed/import scripts under `db/seeds/`, and an approval-aware synthetic blueprint used by offline validation. Review these files and use a disposable database before importing.

Two canonical fixture JSONs are retained under `docs/` because current validation and seed tooling reference them directly:

- `../data/policy/canonical_blueprint.json`
- `../data/policy/source_blueprint.json`

They contain **synthetic reference specifications**, not runtime keys, customer credentials or private deployment instructions.

Historical evaluation logs, notebook handoffs and local environment details are deliberately excluded from public project documentation.

## Limitations

Synthetic performance and policy examples cannot establish correctness for actual companies. Before adopting this system with real customers, replace these fixtures with reviewed policy sources, implement operational identity/security requirements, and validate retention, privacy and delivery processes independently.
