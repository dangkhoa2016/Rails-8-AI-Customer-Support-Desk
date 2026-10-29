#!/usr/bin/env python3
"""M3 synthetic dataset integrity regression checks (no Rails/DB/GPU required)."""
import copy
import hashlib
import json
import pathlib
import tempfile
import unittest
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "script"))
import validate_m3_synthetic_tickets as validator

class M3SyntheticTicketsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.dataset = json.loads(validator.M3_FILE.read_text())
        cls.manifest = json.loads(validator.MANIFEST_FILE.read_text())

    def test_canonical_dataset_integrity(self):
        result = validator.verify()
        self.assertEqual(result["tickets"], 240)
        self.assertEqual(result["messages"], 440)
        self.assertEqual(result["status"], "PASS_OFFLINE_M3_INTEGRITY_ONLY")

    def test_language_and_status_balanced(self):
        for org in ("teamflow-cloud", "novamart-store"):
            tickets = [t for t in self.dataset["tickets"] if t["organization"] == org]
            self.assertEqual(len(tickets), 120)
            for locale in ("vi", "en"):
                selected = [t for t in tickets if t["locale"] == locale]
                self.assertEqual(len(selected), 60)
                self.assertEqual({s: sum(x["status"] == s for x in selected)
                    for s in ("new", "open", "pending_customer", "pending_internal", "resolved", "closed")},
                    {s: 10 for s in ("new", "open", "pending_customer", "pending_internal", "resolved", "closed")})

    def assert_reject(self, mutate):
        data = copy.deepcopy(self.dataset)
        mutate(data)
        with tempfile.TemporaryDirectory() as temp:
            directory = pathlib.Path(temp)
            dataset_path = directory / "dataset.json"
            manifest_path = directory / "manifest.json"
            dataset_path.write_text(json.dumps(data, ensure_ascii=False), encoding="utf-8")
            manifest = copy.deepcopy(self.manifest)
            manifest["dataset_sha256"] = hashlib.sha256(dataset_path.read_bytes()).hexdigest()
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            original_dataset, original_manifest = validator.M3_FILE, validator.MANIFEST_FILE
            try:
                validator.M3_FILE, validator.MANIFEST_FILE = dataset_path, manifest_path
                with self.assertRaises((AssertionError, KeyError, ValueError)):
                    validator.verify()
            finally:
                validator.M3_FILE, validator.MANIFEST_FILE = original_dataset, original_manifest

    def test_reject_cross_customer_business_reference(self):
        def mutate(data):
            t = data["tickets"][0]
            t["customer_key"] = "TF-C-003" if t["customer_key"] != "TF-C-003" else "TF-C-005"
        self.assert_reject(mutate)

    def test_reject_cross_tenant_reference(self):
        def mutate(data):
            data["tickets"][0]["organization"] = "novamart-store"
        self.assert_reject(mutate)

    def test_reject_human_gold_fabrication(self):
        self.assert_reject(lambda data: data["tickets"][0].update(human_policy_gold=True))

    def test_reject_unsafe_automated_action(self):
        self.assert_reject(lambda data: data.update(ai_business_writes="ALLOWED"))

    def test_reject_message_visibility_forgery(self):
        self.assert_reject(lambda data: data["tickets"][2]["messages"][1].update(visibility="public"))

    def test_reject_backdated_message(self):
        self.assert_reject(lambda data: data["tickets"][2]["messages"][1].update(sent_at="2026-10-27T00:00:00+07:00"))

    def test_reject_wrong_locale(self):
        self.assert_reject(lambda data: data["tickets"][0].update(locale="en"))

    def test_reject_source_fact_change(self):
        self.assert_reject(lambda data: data["tickets"][0]["source_facts"].update(status="fabricated"))

if __name__ == "__main__":
    unittest.main(verbosity=2)
