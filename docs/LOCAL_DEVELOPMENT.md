# Local development and verification

[English](LOCAL_DEVELOPMENT.md) · [Tiếng Việt](LOCAL_DEVELOPMENT.vi.md) · [Back to README](../README.md)

This guide sets up a **disposable local demo**. It does not deploy a production operator console or configure external GPU inference.

## Prerequisites

- Ruby 3.3 and Bundler. The tracked `.ruby-version` is **3.3.8**; the project's restored Colab environment also passed tests using **3.3.13**.
- PostgreSQL with the **pgvector** extension available.
- A local PostgreSQL role that can create/use an **isolated development and test database**.
- Git, a terminal and basic Rails familiarity.

Do not point the sample importers at an existing customer database. Use separate, disposable databases and back up any data you want to keep.

## 1. Get the project

```bash
git clone https://github.com/dangkhoa2016/Rails-8-AI-Customer-Support-Desk.git
cd Rails-8-AI-Customer-Support-Desk
bundle install
```

Choose your installed Ruby version before running Bundler. Review `Gemfile` and `Gemfile.lock` for exact dependencies.

## 2. Configure PostgreSQL

The application reads standard environment variables. Set them using a **private local secrets mechanism**, not committed files:

| Name | Purpose |
| --- | --- |
| `PGHOST` / `PGPORT` | PostgreSQL hostname and port |
| `PGUSER` / `PGPASSWORD` | Dedicated local development database identity |
| `PGDATABASE` | Development database name |
| `PGTESTDATABASE` | Separate test database name |
| `RAILS_ENV` | `development` for the interactive demo |
| `M1_SYNTHETIC_DEMO` | `YES` to explicitly enable development-only synthetic workflows |

For example, choose an unused local database and set the variables in your terminal. **Do not copy credentials from screenshots, notebooks, committed JSON or example accounts.**

The database migration set includes PostgreSQL-specific functionality and pgvector support. PostgreSQL must have the `vector` extension installed/available before all migrations can succeed.

## 3. Prepare the development database

```bash
export RAILS_ENV=development
export M1_SYNTHETIC_DEMO=YES

bin/rails db:create
bin/rails db:migrate
bin/rails runner db/seeds/m1_full_business_records.rb
```

The M1 importer provides deterministic, fictional records for both organizations. The full knowledge and ticket datasets are managed by additional scripts; run and validate those importers only when you need the extended demonstration.

Before running data scripts, inspect `db/seeds/` and `script/` to ensure you are operating on the correct database. Do not run `db:reset` or delete an existing database to reproduce a demo.

## 4. Start the local application

```bash
bin/rails server --binding 127.0.0.1 --port 3000
```

Visit `http://127.0.0.1:3000/demo/sign_in`. The demo membership selector is designed for local synthetic validation only; it must not be exposed as a public website.

Explore tickets, customers, knowledge articles, team roles and business references. Available records depend on which sample datasets have been imported.

## 5. Prepare and run tests

Configure `PGTESTDATABASE` to a separate disposable database, then run:

```bash
RAILS_ENV=test bin/rails db:migrate
RAILS_ENV=test bin/rails test
```

The baseline full Rails suite completed **184 tests and 5,888 assertions without failures or errors** on November 16, 2026. Tests cover much of the tenant isolation and synthetic workflow behavior, but they are **not proof of production deployment security**.

Additional offline dataset checks and model integration probes exist under `script/` and `test/`. Some require optional credentials or historical evaluation artifacts and are **not part of the basic Rails setup**.

## Optional AI integrations

The AI search UI has a deliberately explicit readiness gate. For optional inference, both model endpoints, model-scoped tokens and proxy authentication must be configured independently. See `ModalEmbeddingClient`, `ModalRerankerClient` and `KnowledgeAISearchController` for the supported environment contracts.

Never put keys in source control, a public notebook, a browser response or a README. Do not turn on GPU jobs by default; verify authorization and budget first. The core customer-support demo does not require GPU access.

## Security and scope

- **Never** deploy passwordless synthetic login to a publicly reachable service.
- Do not expose the Platform Admin sandbox/localhost operator service as part of the tenant demo.
- Keep tenant and platform identities separate and always validate organization membership server-side.
- Do not treat an AI candidate as a verified policy or permission to change business records.
- Do not import real customer data into the synthetic fixtures without a separate privacy and security design.

Refer to [Security](SECURITY.md), [Architecture](ARCHITECTURE.md) and [Demo data](DEMO_DATA.md) for additional context.
