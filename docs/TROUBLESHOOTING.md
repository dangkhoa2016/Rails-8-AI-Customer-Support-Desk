# Troubleshooting

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](TROUBLESHOOTING.vi.md)

[Home](../README.md) · [Operations](OPERATIONS.md) · [Testing](TESTING.md)

## Rails cannot connect to PostgreSQL

Check `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and `PGDATABASE`. Confirm the server is running and the database exists. Development, test and restricted platform sandbox must not be silently pointed to the same database.

Do not print passwords in logs or set them in committed YAML files.

## Unknown PostgreSQL type `vector`

Confirm pgvector is installed and `CREATE EXTENSION vector` is available in the intended database. The project has a migration from a 1024-dimensional column to 2560 dimensions; running only some migrations can cause schema mismatch.

An Active Record warning about an unknown vector OID may occur in a generic client; it is not proof that vectors are invalid. Validate actual column type and pgvector operations against PostgreSQL.

## `db:prepare` reports permission denied

Some limited roles cannot create databases. Use a dedicated existing test database owned by a permitted role, prepare the extension and migrate into it. Do not grant production-wide `CREATEDB` privileges to an application account solely for a test.

## AI search is unavailable

The core support UI works without GPU inference. Optional AI search requires configured endpoints, credentials, model metadata and approved knowledge. A disabled search gate should remain disabled rather than inventing an inference response.

Do not publish model API tokens or turn on a paid GPU just to fix a documentation preview.

## Tenant access denied

Verify the user is active, the membership belongs to the selected organization, its role permits the action, and the organization is active. A Platform Admin is not a tenant member.

## Local preview redirects to sign-in

The synthetic demo selector is for localhost. Remote previews require an additional password gate, a matching trusted host and a session cookie. Repeated redirects can indicate missing cookies or an invalid preview hostname.

## Public preview POST returns HTTP 405

This is expected for business writes and AI searches in read-only mode. Do **not** remove the gate to make demonstrations easier. Platform Admin must never be placed behind the public tunnel.

## CI discrepancies

Verify that `Gemfile.lock`, `.ruby-version`, PostgreSQL and pgvector match the workflow. A local PASS is not a GitHub CI PASS. Inspect actual workflow logs and avoid changing dependency versions without running tests.

## Still blocked?

Open a sanitized issue using [GitHub issue templates](../.github/ISSUE_TEMPLATE/bug_report.yml) or read [Support](../.github/SUPPORT.md). Report security concerns privately.
