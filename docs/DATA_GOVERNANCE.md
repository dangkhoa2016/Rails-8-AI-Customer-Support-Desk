# Synthetic data and policy provenance

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](DATA_GOVERNANCE.vi.md)

[Home](../README.md) · [Demo data](DEMO_DATA.md) · [Testing](TESTING.md)

## Why there are two blueprint files

The business fixtures have an **original specification** and an **approved specification**. They are intentionally distinct; one is not a redundant backup of the other.

| File | Meaning |
| --- | --- |
| [`data/policy/source_blueprint.json`](../data/policy/source_blueprint.json) | Reference snapshot used to detect accidental changes to the original synthetic business terms and cases |
| [`data/policy/canonical_blueprint.json`](../data/policy/canonical_blueprint.json) | Approved baseline with additional `policy_approval`, `policy_version`, and `implementation_clarifications` metadata |

The source and approved snapshots have the same business organizations, core reference cases, policy links and fixture blueprints. The approved version contains **explicit changes to metadata and clarifications**; this does not imply it is byte-identical to the source.

The files were moved from `docs/` to `data/policy/` to separate data artifacts from public user-facing documentation. Their file contents were preserved during the move.

## Validation rules

`script/validate_approved_blueprint.py` checks:

- Two fictional organizations with distinct policies.
- Twenty policy IDs and twenty reference cases.
- Fifty knowledge catalogue titles per tenant.
- Target quotas and evaluation splits for each fictional organization.
- Equality of original business rules between source and approved data.
- Approved metadata, bilingual clarifications and human-approval defaults.

These checks are **static policy-fixture validation**, not actual customer-policy approval, production data integrity, model accuracy or a PostgreSQL smoke test.

## Other synthetic fixtures

`data/` and `db/seeds/` contain reproducible business and knowledge fixtures. Separate evaluations and runtime logs are not canonical policy sources. Never replace a reviewed policy with an LLM-generated guess.

## Privacy, retention and publication

Use fictional names and synthetic records only. Do not import real personally identifying information, secrets or vendor production exports into the sample corpus. Actual customer deployments need an independently reviewed privacy policy, retention schedule, access logging and approved data-processing basis.

## Changes to the policy baseline

Policy changes should be deliberate, reviewed and documented in both languages. Update relevant validators, tests and seeded fixtures together; do not silently change the source snapshot to make a validator pass. Maintain an auditable reason for every policy revision.
