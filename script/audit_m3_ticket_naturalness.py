#!/usr/bin/env python3
"""Read-only audit of M3 demo-ticket linguistic diversity (no changes to data)."""
from __future__ import annotations
import collections
import hashlib
import json
import re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "data/m3_synthetic_tickets.json"
OUT = ROOT / "evidence-m3-synthetic-tickets-20261029/naturalness-audit.json"
BEFORE = hashlib.sha256(SRC.read_bytes()).hexdigest()
dataset = json.loads(SRC.read_text())
tickets = dataset["tickets"]
assert len(tickets) == 240
bodies = []
normalized = []
for ticket in tickets:
    msg = ticket["messages"][0]["body"]
    bodies.append((ticket["organization"],ticket["category"],ticket["locale"],msg))
    text = msg.replace(ticket["business_ref"], "<REFERENCE>")
    for value in ticket["source_facts"].values():
        if isinstance(value, (str, int)) and str(value):
            text = text.replace(str(value), "<FACT>")
    text = re.sub(r"\b\d{3}\b", "<NUMBER>", text)
    normalized.append((ticket["organization"],ticket["category"],ticket["locale"],text))
tot = len(tickets)
distinct_bodies = len({r[3] for r in bodies})
distinct_patterns = len({r[3] for r in normalized})
pairs = collections.Counter((org,cat,lang) for org,cat,lang,_ in bodies)
patterns = collections.Counter(normalized)
internal = [m["body"] for t in tickets for m in t["messages"] if m["visibility"]=="internal"]
report = {
 "kind":"M3_DEMO_TICKET_NATURALNESS_HEURISTIC_AUDIT_NOT_HUMAN_REVIEW",
 "dataset_sha256": BEFORE,
 "tickets": tot,
 "distinct_customer_intake_texts": distinct_bodies,
 "distinct_masked_customer_intake_patterns": distinct_patterns,
 "unique_internal_note_texts": len(set(internal)),
 "internal_notes": len(internal),
 "unique_business_references": len({(t["organization"],t["source_table"],t["business_ref"]) for t in tickets}),
 "per_category_locale_count": {f"{o}:{c}:{l}":v for (o,c,l),v in sorted(pairs.items())},
 "largest_masked_pattern_reuse": max(patterns.values()),
 "assessment": "TEMPLATED_SYNTHETIC_DATA_NOT_NATURAL_CONVERSATION_GOLD",
 "limitations": [
  "One customer intake plus at most one repeated synthetic internal note, not multi-turn support",
  "String templates reuse a small number of sentence skeletons",
  "Reference variation increases unique literal strings but is not independent language diversity",
  "No human-review ground truth and no real-world user-language representativeness"
 ],
 "recommendation": "Keep approved M3 dataset immutable. Build a separate versioned linguistic-variation proposal and human spot-check samples before reimport.",
 "dataset_modified": False,
}
assert hashlib.sha256(SRC.read_bytes()).hexdigest() == BEFORE
OUT.parent.mkdir(parents=True,exist_ok=True)
OUT.write_text(json.dumps(report,indent=2,ensure_ascii=False,sort_keys=True)+"\n")
print(json.dumps(report,indent=2,ensure_ascii=False))
