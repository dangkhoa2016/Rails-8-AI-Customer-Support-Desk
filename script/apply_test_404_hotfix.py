#!/usr/bin/env python3
"""Non-destructive, idempotent Rails 8 test-only exception mapping hotfix.

Usage: python3 script/apply_test_404_hotfix.py [project_root]
Does not touch production, development, database, CSRF, or controllers.
"""
import hashlib
import pathlib
import re
import sys

RELATIVE = pathlib.Path('config/environments/test.rb')
EXACT_OLD = 'config.action_dispatch.show_exceptions = :none'
EXACT_NEW = 'config.action_dispatch.show_exceptions = :rescuable'
LINE_RE = re.compile(r'(?m)^(\s*)config\.action_dispatch\.show_exceptions\s*=\s*:(\w+)\s*(?:#.*)?$')

def patch(root):
    target = pathlib.Path(root) / RELATIVE
    if not target.is_file():
        raise RuntimeError(f'ABORT: missing Rails test environment: {target}')
    data = target.read_bytes()
    try:
        raw = data.decode('utf-8')
    except UnicodeDecodeError:
        raise RuntimeError('ABORT: test.rb is not UTF-8')
    matches = list(LINE_RE.finditer(raw))
    if len(matches) != 1:
        raise RuntimeError(f'ABORT: expected exactly one show_exceptions configuration, found {len(matches)}')
    old_mode=matches[0].group(2)
    if old_mode == 'rescuable':
        print('ALREADY_APPLIED: test.rb uses :rescuable; no changes')
        return False
    if old_mode != 'none':
        raise RuntimeError(f'ABORT: unexpected show_exceptions setting :{old_mode}; no changes')
    old_line=matches[0].group(0)
    replacement = matches[0].group(1) + EXACT_NEW
    if '#' in old_line:
        replacement += '  #' + old_line.split('#',1)[1]
    updated = raw[:matches[0].start()] + replacement + raw[matches[0].end():]
    if updated == raw:
        raise RuntimeError('ABORT: no effective replacement')
    backup = target.with_name('test.rb.pre-404-hotfix.bak')
    if not backup.exists():
        backup.write_bytes(data)
    target.write_bytes(updated.encode('utf-8'))
    print(f'APPLIED: {target}')
    print(f'BEFORE_SHA256: {hashlib.sha256(data).hexdigest()}')
    print(f'AFTER_SHA256:  {hashlib.sha256(target.read_bytes()).hexdigest()}')
    print('RESULT: :none -> :rescuable; Rails will translate RecordNotFound to HTTP 404')
    return True

if __name__ == '__main__':
    root=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else '.')
    try:
        patch(root)
    except (RuntimeError,OSError) as exc:
        print(str(exc),file=sys.stderr)
        sys.exit(2)
