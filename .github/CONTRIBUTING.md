# Contributing

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](CONTRIBUTING.vi.md)

Thank you for helping improve this synthetic, bilingual Rails support desk.

## Before a change

1. Read [Architecture](../docs/ARCHITECTURE.md), [Security](SECURITY.md) and [Model licenses](../docs/MODEL_LICENSES.md).
2. Open an issue for a significant feature or changes to policy data.
3. Reproduce the issue using **fictional data only**.
4. Keep tenant and Platform Admin authentication separate. AI assistance may not write business records.
5. Never submit tokens, model weights, private logs, personal data or screenshots containing secrets.

## Development

- Install Ruby 3.3, PostgreSQL/pgvector, Bundler and dependencies.
- Follow [Local development](../docs/LOCAL_DEVELOPMENT.md).
- Run `python3 script/check_public_docs.py`, `python3 script/validate_approved_blueprint.py` and `RAILS_ENV=test bundle exec rails test`.
- Keep changes focused and reviewed; avoid adding historical execution artifacts to public docs.
- Update **both English and Vietnamese** versions of any changed user-facing documentation.

## Pull requests

Explain motivation, scope, data migration or security impact, tests performed and remaining limitations. Link the issue when one exists. For source modifications affecting model interfaces, verify upstream licenses and note the exact model and revision.

Documentation-only pull requests must still pass link and language-pair checks. See [Pull request template](PULL_REQUEST_TEMPLATE.md).

## License

Contributions to original project code are offered under the [MIT License](../LICENSE). Model weights and other upstream assets retain their own licenses.
