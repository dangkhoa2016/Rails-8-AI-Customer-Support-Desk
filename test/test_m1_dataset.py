"""Stdlib unit tests for M1 generation and relational validator (NOT Rails DB tests)."""
import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BLUEPRINT = ROOT / 'data' / 'policy' / 'canonical_blueprint.json'
sys.path.insert(0, str(ROOT / 'script'))
from generate_m1_dataset import generate, stable_json  # noqa: E402
from verify_m1_dataset import check  # noqa: E402


class M1OfflineDatasetTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.blueprint = json.loads(BLUEPRINT.read_text())
        cls.dataset = generate(cls.blueprint)

    def test_determinism(self):
        self.assertEqual(stable_json(self.dataset), stable_json(generate(self.blueprint)))

    def test_reference_fixtures_and_counts(self):
        self.assertEqual('PASS_OFFLINE_ONLY', check(self.dataset, self.blueprint)['status'])

    def test_reject_missing_customer(self):
        d = copy.deepcopy(self.dataset)
        d['records']['customers'] = [x for x in d['records']['customers'] if x['external_key'] != 'TF-C-014']
        with self.assertRaises(AssertionError): check(d, self.blueprint)

    def test_reject_incorrect_discount_money(self):
        d = copy.deepcopy(self.dataset)
        d['records']['nm_order_items'][25]['discount_snapshot_vnd'] += 1
        with self.assertRaisesRegex(AssertionError, 'snapshot totals'):
            check(d, self.blueprint)

    def test_reject_wrong_shipping_boundary(self):
        d = copy.deepcopy(self.dataset)
        d['records']['nm_orders'][42]['shipping_vnd'] = 0 if d['records']['nm_orders'][42]['shipping_vnd'] else 30000
        with self.assertRaises(AssertionError): check(d, self.blueprint)

    def test_reject_overshipment(self):
        d = copy.deepcopy(self.dataset)
        d['records']['nm_shipment_items'][0]['shipped_quantity'] += 100
        with self.assertRaisesRegex(AssertionError, 'overshipped'):
            check(d, self.blueprint)

    def test_reject_unpaid_fulfillment(self):
        d = copy.deepcopy(self.dataset)
        d['records']['nm_orders'][0]['status'] = 'shipped'
        with self.assertRaisesRegex(AssertionError, 'prepaid fulfillment'):
            check(d, self.blueprint)

    def test_reject_false_activation(self):
        d = copy.deepcopy(self.dataset)
        ev = next(x for x in d['records']['tf_activation_events'] if x['invoice_number'] == 'TF-INV-2026-0064')
        ev['result'] = 'succeeded'
        with self.assertRaises(AssertionError): check(d, self.blueprint)

    def test_reject_delivery_without_fulfillment(self):
        d = copy.deepcopy(self.dataset)
        d['records']['nm_orders'][41]['status'] = 'delivered'
        with self.assertRaisesRegex(AssertionError, 'order delivered despite incomplete'):
            check(d, self.blueprint)

    def test_reject_wrong_tenant_reference(self):
        d = copy.deepcopy(self.dataset)
        d['records']['nm_orders'][25]['customer_key'] = 'TF-C-014'
        with self.assertRaisesRegex(AssertionError, 'order customer mismatch'):
            check(d, self.blueprint)


if __name__ == '__main__':
    unittest.main(verbosity=2)
