# Security model and responsible evaluation

[English](SECURITY_EN.md) · [Tiếng Việt](SECURITY_VI.md) · [Back to README](../README_EN.md)

This document describes **security boundaries implemented or exercised in the source**, not a certification of production readiness. The included users and organizations are synthetic. Real-world deployment needs a separate security review and infrastructure design.

## Trust boundaries

1. **Tenant identity:** A tenant `User` operates through a verified `Membership` and active `Organization`. The `SupportDeskAccessPolicy` governs each business action; the organization must be derived from trusted session state.
2. **Platform identity:** A `PlatformAdmin` is a separate account class. Platform privileges do not imply membership in any tenant and do not confer customer/ticket access.
3. **Knowledge provenance:** Approved article versions are distinct from drafts and inference responses. A model output is not a security policy or entitlement authority.
4. **Human control:** Public replies, approvals and business mutations must be deliberate, authorized server-side actions.
5. **Preview boundary:** Synthetic passwordless sign-in is local-development-only. Any temporary external preview needs an additional password layer and deny-by-default business-write restrictions.

## Role-based access control

The application models tenant roles `owner`, `admin`, `agent` and `viewer`. Examples of controlled actions include reading/creating/updating tickets, publishing replies, reading private notes, assigning staff, managing customers, approving knowledge and changing organization settings.

The exact permission matrix is defined in the application's `SupportDeskAccessPolicy`. Controllers must check privileges regardless of whether a button is shown or hidden.

## Separate platform authentication

The platform implementation includes a dedicated password session and TOTP MFA flow, sign-in throttling/lockout behavior and session revocation. Platform lifecycle actions and sensitive events are audited separately from ordinary support work.

The local isolated sandbox is not exposed through a public tunnel. **No real Platform Admin account is provisioned by the repository**, and the source's hardening does not imply that externally managed MFA recovery, network perimeters or offsite immutable audit storage have been approved or deployed.

## Storage and audit

PostgreSQL is used for organization-scoped business and knowledge records. Security tests and an isolated sandbox demonstrate role separation and a dedicated ownership boundary for privileged audit records. Such local checks do not eliminate the need for offsite audit retention, operator access procedures, recovery drills and external review in a real deployment.

## AI retrieval safety

AI endpoints are optional integrations. Private endpoint credentials must never be committed, serialized to the browser or copied into issue reports. Input safety checks, tenant filtering, reviewed knowledge state and relevance gates help limit unsupported or cross-tenant results.

**An AI recommendation cannot create a subscription change, refund, shipment, ticket reply or policy approval by itself.**

## Responsible local use

- Use fictional data only.
- Do not expose local demo passwordless sign-in to the public Internet.
- Keep database credentials, session keys and model tokens out of source control.
- Treat user-provided messages and model output as untrusted.
- Do not publish private operator URLs, real credentials, security decision records or internal deployment runbooks.
- Run tests with a disposable test database, not production data.

## What this repository does not guarantee

The project is **not represented as penetration-tested, certified, SOC 2 compliant or production-ready**. External SSO, physical host access, key escrow, immutable offsite audit, real operational MFA custodians, privacy compliance and incident response require their own designs and independent checks.

If you discover a vulnerability, use a private reporting channel to contact the maintainer rather than publishing working exploit details or credentials in an issue.

See [Architecture](ARCHITECTURE_EN.md) for technical relationships and [Local development](LOCAL_DEVELOPMENT_EN.md) for the safe demo setup.
