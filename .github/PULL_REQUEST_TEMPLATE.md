# Pull request

> 🌐 Language / Ngôn ngữ: **English** | [Tiếng Việt](PULL_REQUEST_TEMPLATE.vi.md)

## Summary
Describe what changes and why. Link a relevant issue, if any.

## Scope and compatibility
- [ ] Single focused purpose; no unrelated refactor
- [ ] Tenant and Platform Admin boundaries preserved
- [ ] No private tokens, model weights, real customer information or internal logs
- [ ] Existing database migrations and synthetic fixtures remain compatible

## Verification
- [ ] Rails tests run locally (record exact command/result)
- [ ] Public documentation/language-pair checks pass
- [ ] Both EN and VI docs updated when appropriate
- [ ] Upstream model and third-party license implications checked

## Evidence and limitations
Summarize verified results, remaining limits and any manual review required. Do not claim a test was run unless it actually completed.
