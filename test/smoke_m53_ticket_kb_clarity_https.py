#!/usr/bin/env python3
"""Read-only HTTPS acceptance for ticket reply clarity and tenant-scoped KB priorities.

Uses synthetic demo sign-in; no ticket or KB writes, no Modal calls.
"""
import json
import os
from pathlib import Path
from bs4 import BeautifulSoup
import requests
from urllib.parse import urljoin

ORIGIN = os.environ.get('M53_PRIVATE_ORIGIN', '')
PASSWORD = os.environ.get('RAILS_PRIVATE_PREVIEW_PASSWORD', '')
assert ORIGIN.startswith('https://') and ORIGIN.endswith('.trycloudflare.com')
assert len(PASSWORD) >= 30


def login(tenant, locale):
    session = requests.Session()
    gate = session.get(ORIGIN + '/__private_preview/sign_in', timeout=20)
    assert gate.status_code == 200
    page = BeautifulSoup(gate.text, 'html.parser')
    nonce = page.select_one('input[name=nonce]')
    assert nonce
    result = session.post(ORIGIN + '/__private_preview/sign_in',
        data={'nonce': nonce['value'], 'preview_password': PASSWORD},
        allow_redirects=False, timeout=20)
    assert result.status_code == 303, f'private login: {result.status_code}'
    landing = session.get(ORIGIN + '/demo/sign_in', timeout=20)
    assert landing.status_code == 200
    doc = BeautifulSoup(landing.text, 'html.parser')
    owner = [x for x in doc.select('optgroup option')
             if x.parent.get('label') == tenant and x.get_text(strip=True).startswith('Owner ·')]
    assert len(owner) == 1
    csrf = doc.select_one('meta[name=csrf-token]')
    assert csrf
    result = session.post(ORIGIN + '/demo/sign_in',
        data={'membership_id': owner[0]['value'], 'locale': locale,
              'authenticity_token': csrf['content']},
        headers={'X-CSRF-Token': csrf['content']},
        allow_redirects=False, timeout=20)
    assert result.status_code in (302, 303)
    return session


def page_text(session, path):
    response = session.get(ORIGIN + path, timeout=20)
    assert response.status_code == 200, (path, response.status_code)
    return BeautifulSoup(response.text, 'html.parser')


checks = []
tf = login('TeamFlow Cloud', 'vi')
kb_tf = page_text(tf, '/knowledge_articles')
heading = [x.get_text(' ', strip=True) for x in kb_tf.select('h2')
           if 'Bài KB ưu tiên' in x.get_text(' ', strip=True)]
assert heading == ['Bài KB ưu tiên — TeamFlow Cloud (2 bài)'], heading
rows = kb_tf.select('.priority-language-status')
assert len(rows) == 2
assert all('VI: Đã duyệt' in x.get_text(' ', strip=True) and
           'EN: Đã duyệt' in x.get_text(' ', strip=True) for x in rows)
assert not any(x in kb_tf.get_text(' ', strip=True) for x in
               ['6 bài ưu tiên cần rà soát', 'Modal NOT_RUN', 'NM-KB-014'])
checks.append({'tenant': 'TeamFlow Cloud', 'priority': 2,
               'vi_en_status': 'approved/approved'})

ticket = page_text(tf, '/tickets/117')
assert ticket.select_one('#ticket_reply_form h2').get_text(' ', strip=True) == 'Ghi chú và phản hồi (demo)'
options = {o['value']: o.get_text(' ', strip=True)
           for o in ticket.select('#ticket_reply_form select[name=visibility] option')}
assert 'chỉ nhân viên xem' in options['internal']
assert 'chỉ lưu trong demo' in options['public']
assert ticket.select_one('input[name=review_confirmed]')
assert 'Không gửi email, SMS hoặc thông báo ra ngoài' in ticket.get_text(' ', strip=True)
checks.append({'ticket': 117, 'internal_and_public_modes': 'clear',
               'external_delivery': False})

nm = login('NovaMart Store', 'vi')
kb_nm = page_text(nm, '/knowledge_articles')
heading = [x.get_text(' ', strip=True) for x in kb_nm.select('h2')
           if 'Bài KB ưu tiên' in x.get_text(' ', strip=True)]
assert heading == ['Bài KB ưu tiên — NovaMart Store (4 bài)'], heading
rows = kb_nm.select('.priority-language-status')
assert len(rows) == 4
assert all('VI: Đã duyệt' in x.get_text(' ', strip=True) and
           'EN: Đã duyệt' in x.get_text(' ', strip=True) for x in rows)
assert all(key in kb_nm.get_text(' ', strip=True)
           for key in ['NM-KB-014', 'NM-KB-020', 'NM-KB-029', 'NM-KB-030'])
assert not any(key in kb_nm.get_text(' ', strip=True) for key in ['TF-KB-012', 'TF-KB-015'])
checks.append({'tenant': 'NovaMart Store', 'priority': 4,
               'vi_en_status': 'approved/approved'})
print(json.dumps({'status': 'PASS_M53_PRIVATE_HTTPS_TICKET_KB_COPY',
                  'checks': checks, 'business_writes': 0, 'gpu_calls': 0,
                  'sealed80': 'BLOCKED'}, ensure_ascii=False))
