# Local operations and maintenance

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](OPERATIONS.vi.md)

[Home](../README.md) · [Local development](LOCAL_DEVELOPMENT.md) · [Testing](TESTING.md)

## Operating profile

This repository is a **development and synthetic evaluation application**. It does not ship a ready-made production deployment. Keep a separation between local tenant demo, PostgreSQL data, optional model inference, and the restricted Platform Admin console.

## Startup checklist

1. Verify the current checkout and review `git status --short`.
2. Use a compatible Ruby version and `bundle install` with `Gemfile.lock`.
3. Start a dedicated local PostgreSQL instance with pgvector available.
4. Configure `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE` and a separate test database.
5. Run `bin/rails db:migrate` against **the intended local database only**.
6. Bind the tenant demo to `127.0.0.1` and verify `GET /healthz`.
7. Keep model inference disabled unless endpoint credentials and budget have been explicitly approved.

## Background jobs

The project includes a PostgreSQL-backed Solid Queue integration for optional asynchronous AI search. A web server alone does **not** prove that a background worker is running. Verify the configured queue adapter, worker process and job status when enabling background tasks.

Never initiate paid GPU inference automatically during a documentation smoke test. Request/response logs must not contain raw tokens or tenant data outside approved storage.

## Data maintenance

- Maintain backups of database content separately from Git source.
- Use `pg_dump`/`pg_restore` only with authorization and a verified target database.
- Do not assume portable dumps preserve PostgreSQL ownership and grants.
- Retain audit integrity and role separation on any restored privileged sandbox.
- Do not commit machine-specific `.env` files, external secrets or private infrastructure URLs.

## Observability

Use application health endpoints, Rails error logs, database checks and supported job-status pages for diagnostics. Report measured latency, model usage and readiness with their actual environment and sample size. Do not interpret a successful application boot as proof of production capacity or AI quality.

## Security boundary

A local passwordless demo must never be exposed publicly. Any remote preview requires a password gate and read-only request restrictions; the Platform Admin sandbox remains local-only. See [Security](SECURITY.md).

## Recovery

Restore Git source, then restore the matching PostgreSQL data and permissions. Verify migrations, fixtures, authentication boundaries and Rails tests before re-enabling model inference. For common issues, see [Troubleshooting](TROUBLESHOOTING.md).
