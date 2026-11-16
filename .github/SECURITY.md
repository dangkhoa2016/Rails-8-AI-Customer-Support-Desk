# Security policy

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](SECURITY.vi.md)

## Supported scope

This repository is an evaluated synthetic-data development project, not a certified production service. Security reports should focus on the current `main` branch and reproducible behavior.

## Private vulnerability reporting

**Email: i.am@dangkhoa.dev**

Please include an affected commit, a minimized reproduction using fictional data, security impact and sanitized logs. Do not include actual access tokens, personal information, real customer data or exploitation details in public issues.

## Trust boundaries

- Tenant `User`/`Membership` and global `PlatformAdmin` are separate identities.
- Server-side tenant checks are mandatory; UI visibility alone cannot authorize data access.
- AI output cannot approve knowledge, send replies or mutate business entities by itself.
- The local Platform Admin sandbox must not be exposed through a public tunnel.
- Passwordless demo selection is exclusively for local synthetic testing.

## Response expectations

Reports are triaged by the maintainer as capacity permits. There is no guaranteed response time or production security SLA. Remediation may require a security update, documentation or configuration changes.

For secure deployment assumptions, read [Project security model](../docs/SECURITY.md).
