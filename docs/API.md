# HTTP routes and integration boundaries

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](API.vi.md)

[Home](../README.md) · [Architecture](ARCHITECTURE.md) · [Security](SECURITY.md)

## Interface contract

The application is a **server-rendered Rails support desk**. Routes below are internal application interfaces and **not a guaranteed, versioned public REST API**. Authentication, CSRF protection and tenant-role policy apply. Client code must not assume that a controller action can be invoked anonymously.

| Area | Representative routes | Notes |
| --- | --- | --- |
| Health | `GET /healthz` | Operational health response; not a security audit |
| Synthetic local demo | `GET /demo/sign_in`, `POST /demo/sign_in` | Development-only membership selection |
| Password sessions | `GET /auth/sign_in`, `POST /auth/sign_in` | Tenant password authentication |
| Dashboard | `GET /` | Tenant-scoped support overview |
| Tickets | `GET /tickets`, `GET /tickets/:id`, `POST /tickets` | Authorized ticket read/create |
| Ticket messages | `POST /tickets/:ticket_id/ticket_messages` | Human-public or internal content checks |
| Ticket workflow | `PATCH /tickets/:id/status`, `PATCH /tickets/:id/assign` | Role-gated state changes |
| Customers | `/customers` resource routes | Tenant-scoped CRUD and archive |
| Staff | `/staff_members` | Role management with owner/admin safeguards |
| Knowledge | `GET /knowledge_articles/:id`, `POST /knowledge_articles/:id/approve` | Versioned knowledge and human editorial approval |
| AI-assisted knowledge | `GET /kb/ai-search`, `POST /kb/ai-search` | Requires explicit readiness and tenant authorization |
| Business records | `GET /records/teamflow/invoice`, `GET /records/novamart/order` | Fictional reference records |
| Organization settings | `GET /settings`, `PATCH /settings` | Tenant-authorized settings changes |
| Platform | `/platform/*` | **Separate identity and restricted admin boundary** |

See `config/routes.rb` for the exact authoritative route and HTTP verb definitions.

## Authentication and authorization

A support user must have an active session, membership and organization. A request cannot gain access merely by passing another organization's ID. The role-specific `SupportDeskAccessPolicy` is enforced server-side.

Platform operators authenticate independently and must not inherit customer/ticket permissions.

## Optional model integration

The embedding and reranking connectors use authenticated, externally configured services and validate model metadata. They are not unauthenticated public APIs. See [Model licenses](MODEL_LICENSES.md) and [Operations](OPERATIONS.md).

## Errors, behavior and compatibility

HTTP status codes depend on authentication, CSRF, business rules and feature gates. Unauthenticated requests may redirect to sign-in, while disallowed operations are rejected. Do not build a public client against unversioned internal controller routes without a separate, reviewed API contract.
