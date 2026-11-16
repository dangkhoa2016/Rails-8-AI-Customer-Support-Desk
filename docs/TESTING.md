# Verification and test strategy

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](TESTING.vi.md)

[Home](../README.md) · [Local setup](LOCAL_DEVELOPMENT.md) · [CI](../.github/workflows/ci.yml)

## What can be verified locally

The repository includes Rails/Minitest regression tests, Python-based policy and knowledge validation, and optional external inference probes. These test families have different guarantees and requirements; do not combine their results into a single claimed model-quality score.

| Suite | Command | Purpose |
| --- | --- | --- |
| Rails application | `RAILS_ENV=test bundle exec rails test` | Controllers, authorization, ticket/customer/knowledge behavior |
| Autoloading | `bundle exec rails zeitwerk:check` | Rails class discovery |
| Synthetic policy baseline | `python3 script/validate_approved_blueprint.py` | Original vs approved policy invariants |
| Knowledge validation | `python3 -m unittest discover -s test -p 'test_m2_knowledge.py' -v` | Offline knowledge fixture consistency |
| Public documentation | `python3 script/check_public_docs.py` | Bilingual pairs, references and sensitive patterns |
| Optional model probes | Explicitly selected scripts under `script/` and `modal_app/` | Requires reviewed endpoints and budget |

## Required local environment

- A disposable PostgreSQL database for tests with pgvector installed.
- Ruby compatible with `.ruby-version`; Bundler dependencies from `Gemfile.lock`.
- No real tenant data or production credentials.
- A known code revision and documented migration state.

Prepare the test database separately: `RAILS_ENV=test bundle exec rails db:migrate`. Some environments use `db:prepare` when role permissions allow it. Do not grant excessive database privileges to resolve a test failure without reviewing the permission boundary.

## Baseline evidence

The restored synthetic environment reported **184 Rails tests, 5,888 assertions, 0 failures, 0 errors, 0 skips** on November 16, 2026. The documentation cleanup also passed 14 offline knowledge tests and blueprint validation. These numbers are historical local observations, not a claim that a future CI run has already passed.

## Security expectations

A valid regression plan must cover:

1. Tenant membership cannot access another organization's customer or ticket.
2. Viewer/agent/admin/owner have different allowed actions.
3. Platform Admin cannot inherit tenant data access.
4. Public preview rejects business writes and AI job creation.
5. Audit records and privileged roles remain isolated.
6. AI results cannot become automatic business mutations.

## Reporting outcomes

Use PASS/FAIL/NOT_RUN for **the exact command and environment tested**. Record the failure mode, whether an external GPU was active, and whether the dataset was synthetic. Never mark tests or production acceptance as complete because a previous run passed.

CI is described in [`.github/workflows/ci.yml`](../.github/workflows/ci.yml). It becomes authoritative only after GitHub executes the workflow against the published commit.
