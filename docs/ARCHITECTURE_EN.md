# Architecture — Rails 8 AI Customer Support Desk

[English](ARCHITECTURE_EN.md) · [Tiếng Việt](ARCHITECTURE_VI.md) · [Back to README](../README_EN.md)

## Architectural approach

The project is a server-rendered, multi-tenant Rails application with PostgreSQL as the transactional system of record. It brings customer support workflow, curated knowledge and optional AI retrieval into one application rather than treating the model as a substitute for an agent.

The architectural invariants are:

- A request acts on exactly one organization established through a verified membership, **not a tenant ID suggested by the browser or model**.
- Tenant identities and platform operators use **separate authentication and authorization paths**.
- Business writes are explicit actions by an authorized person. AI output is informational and cannot authorize a write.
- Approved knowledge and policy references are distinguishable from drafts, model-generated text and unverified retrieved content.
- Internal security events and public-facing support messages have different visibility and authorization rules.

## Application components

| Layer | Responsibility | Example implementation |
| --- | --- | --- |
| Presentation | SSR pages and incremental updates | Rails ERB, Turbo and Stimulus |
| Controller boundary | Session identity, request validation, action authorization | Application controller, ticket/customer/knowledge controllers |
| Tenant domain | Tickets, customers, staff, messages and settings | Active Record models with organization associations |
| Business references | SaaS and commerce records used as customer-support context | TeamFlow/NovaMart models and read-only lookup services |
| Knowledge domain | Article versions, approval state, content chunks and embeddings | Knowledge article and embedding models |
| Retrieval | Scoped search, relevance selection and optional reranking | Search services and optional Modal clients |
| Background work | Optional asynchronous search runs | Active Job / Solid Queue |
| Platform boundary | Organization lifecycle, separate platform account and security audit | Platform controllers, PlatformAdmin, audit models |
| Persistence | Relational data, integrity constraints and vectors | PostgreSQL and pgvector |

### Tenant-scoped workflow

```text
Request
  → resolve signed-in tenant session
  → verify active User + Membership + Organization
  → apply role-specific permissions
  → query records within the authorized organization
  → validate state transition / human approval if writing
  → persist change + audit event
  → render scoped response
```

Role capabilities are centralized in `SupportDeskAccessPolicy`. The implemented roles are `owner`, `admin`, `agent` and `viewer`, each with its own permissions. UI affordances are not the security boundary; controllers and policies must reject unauthorized actions.

### Platform operations are separate

A `PlatformAdmin` is **not** an `User` or `Membership`. The platform console is designed for global organization administration, not customer-support impersonation. Operator authentication includes password and TOTP MFA flows, session invalidation and security event recording; it must not be inferred from an ordinary tenant account.

The platform's isolated local sandbox and its security hardening are development/evaluation capabilities, **not evidence that a production operator console has been deployed or independently audited**. No production admin credentials are supplied.

## Ticket lifecycle and customer messages

The Rails workflow separates inbound and outbound messages, staff-only notes and ticket metadata. Tickets can be created, assigned and transitioned with permission checks and auditable actions. The user interface displays the conversation alongside business and knowledge context.

An AI search result is a possible **reference for a human agent**. It is not an instruction to send a public reply, authorize a refund or change an order/subscription.

## Business context

The sample businesses exercise different relationships and policies:

- **TeamFlow Cloud:** subscription and effective plan, invoices, activation events, service incidents, workspaces and API/export events.
- **NovaMart Store:** orders and immutable item snapshots, payments, shipments, per-item fulfillment, return requests and warranty records.

Both businesses are fictional. Their sample policies exist to test correctness and authorization rather than represent real commercial terms.

## Knowledge and AI retrieval

```text
Staff query + permitted tenant
      |
      v
Input/privacy checks
      |
      v
Qwen3-Embedding-4B (optional model endpoint)
      |
      v
Tenant-filtered pgvector candidate lookup
      |
      v
Qwen3-Reranker-4B (optional model endpoint)
      |
      v
Source/relevance/answerability checks
      |
      v
Evidence-linked results for human review
```

The evaluated embedding column uses `vector(2560)`. Integration clients validate the pinned model metadata. An approved content record is distinguishable from a draft; fallback and failure conditions must never silently elevate an unapproved candidate into a policy decision.

Model endpoints and credentials must be configured separately. A local Rails boot or passing unit test **does not prove external GPU availability**.

## Data boundaries and integrity

- PostgreSQL transactions and record associations are scoped to the tenant; relational checks help prevent cross-organization references.
- Staff-facing audit events and privileged platform security events serve different purposes.
- Private previews are password-gated and prohibit business mutations; the platform sandbox binds only to localhost.
- The reference business-policy JSON documents are synthetic fixtures, not secret environment configuration.

## What remains outside the demonstrated scope

Production perimeter networking, real operator enrollment, cross-service delivery channels, infrastructure key management, broader model-quality acceptance and external penetration testing have not been established by these source tests. See [Security](SECURITY_EN.md) and [Local development](LOCAL_DEVELOPMENT_EN.md).
