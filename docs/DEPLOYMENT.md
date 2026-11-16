# Deployment boundaries and portability

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](DEPLOYMENT.vi.md)

[Home](../README.md) · [Operations](OPERATIONS.md) · [Security](SECURITY.md)

## Supported deployment profile

The available source demonstrates a **local Rails development/evaluation application with synthetic business data**. No public production deployment, permanent operator credentials, independent security signoff or immutable audit store is bundled.

Avoid copying temporary notebook/Colab ports, machine paths or Quick Tunnel URLs into permanent configuration.

## Components

- Rails 8 application and Active Record/Hotwire UI.
- PostgreSQL 16+ in the evaluated environment, with the pgvector extension.
- Optional Solid Queue process for asynchronous AI search.
- Optional authenticated embedding/reranking model services running outside Rails.
- Separate restricted Platform Admin identity and audit boundary.

## Before a new host

1. Verify Ruby/Bundler and `Gemfile.lock` compatibility.
2. Provision an isolated PostgreSQL cluster/role and review extension availability.
3. Provide secrets using a host secret manager or protected runtime environment, not Git.
4. Apply migrations on a **known, backed-up** database and verify tenant isolation.
5. Establish TLS, access controls and trusted proxy/host validation before any public traffic.
6. Deploy read-only synthetic previews separately from private operator interfaces.
7. Enable background workers and model endpoints only after operational approval.
8. Validate logs, backups, restore drills, monitoring and operator MFA independently.

## Preview versus production

A temporary Cloudflare Quick Tunnel is suitable only for a password-gated, **read-only** synthetic demonstration when the preview code enforces write denial. Its generated URL is not a stable service endpoint.

Platform Admin must stay behind a separately reviewed private access boundary; exposing its sandbox on the Internet is **not** a supported deployment shortcut.

## Completion criteria

Before real customers, require verified tenant isolation, account provisioning, database/audit role hardening, durable backup and key management, privacy compliance, incident handling, monitoring, accessible UI review and independent penetration testing.

**Do not treat a passing local test suite as production authorization.**
