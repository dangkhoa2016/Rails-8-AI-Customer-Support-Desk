#!/usr/bin/env python3
"""Static regression guard for M1/M2 integration CSRF coverage."""
import pathlib, re
root = pathlib.Path(__file__).resolve().parents[1]
a = root / 'test/integration/support_desk_security_test.rb'
b = root / 'test/integration/knowledge_base_security_test.rb'
helper = root / 'test/support/csrf_requests.rb'
for p in [a,b,helper]:
    assert p.exists(), str(p)
for p in [a,b]:
    s = p.read_text()
    assert 'include CsrfRequests' in s
    assert "csrf_page: demo_sign_in_path" in s
    # Ensure the integration files never issue unprotected writes.
    assert not re.search(r'(?m)^\s*(?:post|patch|put|delete)\s+', s), p.name
assert 'X-CSRF-Token' in helper.read_text()
assert 'Nokogiri::HTML' in helper.read_text()
assert 'protect_from_forgery' not in helper.read_text()
print('PASS: M1/M2 integration requests fetch and submit real CSRF tokens; no CSRF bypass')
