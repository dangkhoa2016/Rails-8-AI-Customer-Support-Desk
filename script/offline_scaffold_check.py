#!/usr/bin/env python3
"""Source-only structural checks; NOT proof Rails boots or database migrations execute."""
from pathlib import Path
import json
import re
import subprocess
import yaml

root = Path(__file__).resolve().parents[1]
required = ["Gemfile", "Rakefile", "config.ru", "bin/rails", "bin/rake", "config/boot.rb",
    "config/application.rb", "config/environment.rb", "config/routes.rb", "config/database.yml",
    "db/seeds.rb", "config/environments/development.rb", "config/environments/test.rb",
    "app/controllers/application_controller.rb", "app/controllers/demo_sessions_controller.rb",
    "app/controllers/dashboard_controller.rb", "app/controllers/tickets_controller.rb",
    "app/controllers/ticket_messages_controller.rb", "app/controllers/customers_controller.rb",
    "app/controllers/business_records_controller.rb", "app/views/layouts/application.html.erb",
    "test/test_helper.rb", "test/integration/support_desk_security_test.rb",
    "app/controllers/knowledge_articles_controller.rb", "app/services/knowledge_publication.rb",
    "app/services/knowledge_retrieval.rb", "db/seeds/m2_knowledge_base.rb",
    "data/m2/knowledge_drafts.json", "test/integration/knowledge_base_security_test.rb"]
missing = [path for path in required if not (root / path).is_file()]
assert not missing, f"Missing app files: {missing}"
assert len(list((root / 'db/migrate').glob('*.rb'))) == 5
langs = {}
for language in ['vi', 'en']:
    langs[language] = yaml.safe_load((root / f'config/locales/{language}.yml').read_text())[language]
used = set()
for f in (root / 'app/views').rglob('*.erb'):
    used.update(re.findall(r"\bt\('([^']+)'", f.read_text()))
for f in (root / 'app/controllers').rglob('*.rb'):
    used.update(re.findall(r"\bt\('([^']+)'", f.read_text()))
for language, d in langs.items():
    for key in used:
        current = d
        for component in key.split('.'):
            assert component in current, f'{language} translation missing: {key}'
            current = current[component]
        assert isinstance(current, str), f'Invalid translation value {language}/{key}'
for f in (root / 'config').rglob('*.yml'):
    if f.name != 'database.yml' and f.name != 'storage.yml':
        yaml.safe_load(f.read_text())
rb_files = list(root.rglob('*.rb')) + list(root.glob('bin/*'))
for f in rb_files:
    if f.name.endswith('.py') or f.suffix not in ('.rb', ''):
        continue
    p = subprocess.run(['ruby', '-c', str(f)], capture_output=True, text=True)
    assert p.returncode == 0, f'Ruby syntax FAIL {f}: {p.stderr}'
source = json.loads((root / 'data/m1_business_records.json').read_text())
assert source['kind'] == 'M1_DETERMINISTIC_BUSINESS_RECORDS_ONLY'
print(json.dumps({'status':'PASS_SOURCE_ONLY','verified':'files Ruby syntax translation keys and expected scaffolding',
  'rails_boot':'NOT_RUN', 'postgresql':'NOT_RUN', 'views':len(list((root/'app/views').rglob('*.erb'))),
  'ruby_files':len(rb_files),'translated_keys':len(used),'migrations':5}, indent=2))
