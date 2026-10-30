#!/usr/bin/env python3
"""Read-only authenticated HTTPS smoke for active navigation and button CSS."""
import json
import os
import pathlib
import re
import requests
from bs4 import BeautifulSoup
from urllib.parse import urlparse

PASSWORD = os.environ.get('RAILS_PRIVATE_PREVIEW_PASSWORD', '')
assert len(PASSWORD) >= 30
log = pathlib.Path('/tmp/rails8_m3_cloudflared.log').read_text()
hosts = re.findall(r'https://([a-z0-9-]+\.trycloudflare\.com)', log)
assert hosts
ORIGIN = 'https://' + hosts[-1]
session = requests.Session()

landing = session.get(ORIGIN + '/__private_preview/sign_in', timeout=20)
assert landing.status_code == 200
nonce = re.search(r'name="nonce"\s+value="([^"]+)"', landing.text)
assert nonce
gate = session.post(ORIGIN + '/__private_preview/sign_in',
    data={'nonce': nonce.group(1), 'preview_password': PASSWORD},
    allow_redirects=False, timeout=20)
assert gate.status_code == 303

signin = session.get(ORIGIN + '/demo/sign_in', params={'locale':'en'}, timeout=20)
assert signin.status_code == 200
sign_doc = BeautifulSoup(signin.text, 'html.parser')
owner = [option for option in sign_doc.select('optgroup[label="TeamFlow Cloud"] option')
         if option.get_text(strip=True).startswith('Owner ·')]
assert len(owner) == 1
token = sign_doc.select_one('meta[name="csrf-token"]')['content']
selected = session.post(ORIGIN + '/demo/sign_in',
    data={'membership_id': owner[0]['value'], 'locale':'en',
          'authenticity_token':token}, headers={'X-CSRF-Token':token},
    allow_redirects=False, timeout=20)
assert selected.status_code in (302, 303)

checks = []

def check(path, href):
    response = session.get(ORIGIN + path, timeout=20)
    assert response.status_code == 200, (path, response.status_code)
    doc = BeautifulSoup(response.text, 'html.parser')
    links = doc.select('nav a.nav-menu-link')
    assert len(links) == 5, (path, len(links))
    active = [link for link in links if 'is-active' in link.get('class', [])]
    assert len(active) == 1, (path, len(active))
    assert active[0].get('href') == href, (path, active[0].get('href'), href)
    assert active[0].get('aria-current') == 'page'
    assert all('aria-current' not in link.attrs for link in links if link != active[0])
    css = doc.style.get_text()
    assert '.navlinks .nav-menu-link.is-active' in css
    assert 'input[type=submit],input[type=button],input[type=reset]' in css
    assert 'cursor:pointer' in css
    assert 'cursor:not-allowed' in css
    checks.append({'path': path, 'active_href': href, 'http':response.status_code})
    return doc

check('/', '/')
check('/tickets', '/tickets')
ticket_doc = check('/tickets', '/tickets')
ticket = next((node.get('href') for node in ticket_doc.select('a[href^="/tickets/"]')
               if re.fullmatch(r'/tickets/\d+', node.get('href', ''))), None)
assert ticket
check(ticket, '/tickets')
check('/customers', '/customers')
customer_doc = check('/customers', '/customers')
customer = next((node.get('href') for node in customer_doc.select('a[href^="/customers/"]')
                 if re.fullmatch(r'/customers/\d+', node.get('href', ''))), None)
assert customer
check(customer, '/customers')
check('/knowledge_articles', '/knowledge_articles')
check('/kb/ai-search', '/kb/ai-search')

print(json.dumps({
    'status':'PASS_HTTPS_ACTIVE_NAV_AND_BUTTON_POINTER',
    'roles_tested':['teamflow-cloud/owner'],
    'main_sections':5,'paths_checked':len(checks),'checks':checks,
    'css_checks':['nav active','aria-current=page','button submit pointer','disabled cursor'],
    'business_mutations':0,'secrets_logged':False
}, indent=2))
