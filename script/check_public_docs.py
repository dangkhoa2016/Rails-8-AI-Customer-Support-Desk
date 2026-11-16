#!/usr/bin/env python3
"""Fail-closed audit of public bilingual documentation and checked-in fixtures."""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
GH = ROOT / ".github"

def pair(path: pathlib.Path) -> pathlib.Path:
    if path.name.endswith(".vi.md"):
        return path.with_name(path.name.removesuffix(".vi.md") + ".md")
    return path.with_name(path.name.removesuffix(".md") + ".vi.md")

def md_links(text: str) -> list[str]:
    return re.findall(r"!?(?:\\[[^\\]]*\\])\\(([^)]+)\\)", text)

def main() -> int:
    readmes = [ROOT / "README.md", ROOT / "README.vi.md"]
    for readme in readmes:
        if not readme.is_file() or len(readme.read_text()) < 3500:
            raise AssertionError(f"Missing or insufficient README: {readme.name}")
    for required in ("License-MIT", "actions/workflows/ci.yml/badge.svg"):
        if required not in readmes[0].read_text():
            raise AssertionError("Missing required public badge " + required)
    docs = [p for p in DOCS.glob("*.md")]
    community = [p for p in GH.rglob("*.md")]
    for path in docs + community:
        assert pair(path).is_file(), f"Missing language counterpart: {path}"
    checked = [*readmes, *docs, *community]
    forbidden = (
        re.compile(r"ghp_[A-Za-z0-9]{25,}|github_pat_[A-Za-z0-9_]{25,}"),
        re.compile(r"sk-[A-Za-z0-9_-]{25,}|hf_[A-Za-z0-9]{25,}"),
        re.compile(r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----"),
        re.compile(r"/root/\\.config/|/content/krw-workspace|/content/\\.rails8-private"),
    )
    for path in checked:
        text = path.read_text(encoding="utf-8")
        assert len(text) > 200, f"Insufficient content: {path}"
        counterpart = pair(path)
        # Filename is required to appear as an explicit language switch.
        assert counterpart.name in text, f"Language switch missing: {path}"
        for pattern in forbidden:
            assert not pattern.search(text), f"Sensitive pattern in {path}"
        for raw in md_links(text):
            target = raw.split("#", 1)[0].strip().split(" ", 1)[0]
            if not target or target.startswith(("http://", "https://", "mailto:")):
                continue
            candidate = (path.parent / target).resolve()
            assert candidate.is_relative_to(ROOT.resolve()), f"Escaping link: {path}"
            assert candidate.exists(), f"Broken link: {path} -> {target}"
    fixture_dir = ROOT / "data" / "policy"
    assert (fixture_dir / "source_blueprint.json").is_file()
    assert (fixture_dir / "canonical_blueprint.json").is_file()
    assert len(list(DOCS.glob("*.json"))) == 0
    print(f"PASS: {len(checked)} bilingual Markdown files, linked assets, badges, fixtures and safety patterns")
    return 0

if __name__ == "__main__":
    sys.exit(main())
