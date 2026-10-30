#!/usr/bin/env python3
"""Read-only HTTPS checks for P0-P3 synthetic demo after server restart.

No GPU calls, customer writes, credentials or message bodies in evidence.
"""
import json
import os
from bs4 import BeautifulSoup
import requests

origin = os.environ['P0_P3_PREVIEW_ORIGIN'].rstrip('/')
assert origin.startswith('https://') and origin.endswith('.trycloudflare.com')
password = os.environ['RAILS_PRIVATE_PREVIEW_PASSWORD']
assert len(password) >= 30


def new_session(tenant, role, locale='vi'):
    session = requests.Session()
    gate = session.get(origin + '/__private_preview/sign_in', timeout=20)
    assert gate.status_code == 200
    nonce = BeautifulSoup(gate.text, 'html.parser').select_one('input[name=nonce]')['value']
    resp = session.post(origin + '/__private_preview/sign_in',
        data={'nonce': nonce, 'preview_password': password},
        allow_redirects=False, timeout=20)
    assert resp.status_code == 303
    landing = session.get(origin + '/demo/sign_in', timeout=20)
    assert landing.status_code == 200
    doc = BeautifulSoup(landing.text, 'html.parser')
    matches = [o for o in doc.select('optgroup option')
               if o.parent.get('label') == tenant and
               o.get_text(strip=True).lower().startswith(role.lower() + ' ·')]
    assert len(matches) == 1, (tenant, role, len(matches))
    csrf = doc.select_one('meta[name=csrf-token]')['content']
    resp = session.post(origin + '/demo/sign_in',
        data={'membership_id': matches[0]['value'], 'locale': locale,
              'authenticity_token': csrf},
        headers={'X-CSRF-Token': csrf}, allow_redirects=False, timeout=20)
    assert resp.status_code == 303
    return session


def read(session, path, status=200):
    resp = session.get(origin + path, timeout=20, allow_redirects=False)
    assert resp.status_code == status, (path, resp.status_code)
    return BeautifulSoup(resp.text, 'html.parser')


checks = []
owner = new_session('TeamFlow Cloud', 'Owner')
for path in ['/staff_members', '/settings', '/customers/new', '/tickets/117',
             '/tickets?assignee_user_id=me', '/customers']:
    read(owner, path)
checks.append({'role': 'owner', 'tenant': 'TeamFlow Cloud', 'staff': 200,
               'settings': 200, 'customer_new': 200, 'ticket': 200})
assert read(owner, '/auth/sign_in', 403) is not None
ticket = read(owner, '/tickets/117')
assert ticket.select_one('form[action="/tickets/117/assign"]')
assert ticket.select_one('.message.internal')
viewer = new_session('TeamFlow Cloud', 'Viewer')
for path in ['/staff_members', '/settings', '/customers/new']:
    read(viewer, path, 403)
viewer_ticket = read(viewer, '/tickets/117')
assert not viewer_ticket.select('.message.internal')
assert not viewer_ticket.select_one('form[action="/tickets/117/assign"]')
checks.append({'role': 'viewer', 'tenant': 'TeamFlow Cloud', 'internal_notes_visible': False,
               'staff_settings_customer_write': 403})
agent = new_session('TeamFlow Cloud', 'Agent')
read(agent, '/staff_members', 403)
read(agent, '/settings', 403)
read(agent, '/customers')
read(agent, '/tickets/117')
checks.append({'role': 'agent', 'tenant': 'TeamFlow Cloud', 'staff_access': 403})
admin = new_session('TeamFlow Cloud', 'Admin')
staff = read(admin, '/staff_members')
assert staff.select_one('form[action="/staff_members"]')
settings = read(admin, '/settings')
assert not settings.select('input[type=submit]')
checks.append({'role': 'admin', 'tenant': 'TeamFlow Cloud', 'staff': 200,
               'settings_read': 200, 'settings_update_ui': False})
nova = new_session('NovaMart Store', 'Owner')
nova_staff = read(nova, '/staff_members')
assert 'NovaMart Admin (Synthetic)' in nova_staff.get_text(' ', strip=True)
assert 'TeamFlow Admin (Synthetic)' not in nova_staff.get_text(' ', strip=True)
checks.append({'role': 'owner', 'tenant': 'NovaMart Store', 'staff': 200, 'cross_tenant_staff': False})
for path in ['/settings', '/customers', '/tickets/117/assign']:
    resp = owner.patch(origin + path, timeout=15, allow_redirects=False)
    assert resp.status_code == 405, (path, resp.status_code)
checks.append({'public_preview': 'business_writes_blocked', 'patch_routes': 3, 'http': 405})
print(json.dumps({'status': 'PASS_P0_P3_PRIVATE_HTTPS_RBAC_UI', 'checks': checks,
                  'gpu_calls': 0, 'business_writes': 0, 'sealed80': 'BLOCKED'},
                 ensure_ascii=False))
