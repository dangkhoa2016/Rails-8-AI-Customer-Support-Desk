#!/usr/bin/env python3
"""Offline deterministic tests for the read-only D-01 host preflight."""
import copy
import importlib.util
import json
import pathlib
import unittest

BASE=pathlib.Path(__file__).resolve().parents[2]
P=BASE/"script/p03_d01_private_https_preflight.py"
spec=importlib.util.spec_from_file_location("d01_preflight",P)
d01=importlib.util.module_from_spec(spec)
spec.loader.exec_module(d01)

class D01SecurityPreflightTests(unittest.TestCase):
    def test_frozen_design_contract_is_valid_but_not_approved(self):
        contract=json.loads(d01.CONTRACT.read_text())
        report=d01.evaluate_contract(contract)
        self.assertEqual("PASS_STATIC_CONTRACT_ONLY",report["status"])
        self.assertEqual("D-01_PENDING",contract["owner_decision"])
        self.assertEqual("D-06_PENDING",contract["deployment_authorization"])
        self.assertFalse(contract["non_negotiable"]["operator_origin_public_routable"])

    def test_reject_attempt_to_label_owner_approved(self):
        raw=json.loads(d01.CONTRACT.read_text())
        bad=copy.deepcopy(raw)
        bad["deployment_authorization"]="D-06_APPROVED"
        with self.assertRaises(AssertionError):
            d01.evaluate_contract(bad)

    def test_reject_public_origin_and_insecure_cookie(self):
        contract=json.loads(d01.CONTRACT.read_text())
        bad=copy.deepcopy(contract)
        bad["non_negotiable"]["operator_origin_public_routable"]=True
        with self.assertRaises(AssertionError):d01.evaluate_contract(bad)
        bad=copy.deepcopy(contract)
        bad["non_negotiable"]["session_cookie_secure"]=False
        with self.assertRaises(AssertionError):d01.evaluate_contract(bad)

    def test_ip_trust_and_forwarded_headers_must_be_strict(self):
        contract=json.loads(d01.CONTRACT.read_text())
        for key in ("trusted_proxy_exact_allowlist","deny_forwarded_identity_headers_from_client"):
            bad=copy.deepcopy(contract)
            bad["non_negotiable"][key]=False
            with self.subTest(key=key),self.assertRaises(AssertionError):
                d01.evaluate_contract(bad)

    def test_listen_ipv4_and_ipv6_loopback_only(self):
        ss=("LISTEN 0 1024 127.0.0.1:3078 0.0.0.0:*\n"
            "LISTEN 0 1024 [::1]:3078 [::]:*\n"
            "LISTEN 0 1024 127.0.0.1:3068 0.0.0.0:*\n")
        self.assertEqual(["127.0.0.1","::1"],d01.parse_listeners(ss,3078))
        self.assertEqual("PASS_LOCAL_LOOPBACK",d01.listener_gate(ss,3078)["status"])

    def test_non_loopback_binding_must_fail(self):
        for address in ("0.0.0.0","*","172.28.0.12","::"):
            with self.subTest(address=address):
                text=f"LISTEN 0 1024 {address}:3078 0.0.0.0:*"
                self.assertEqual("FAIL_UNEXPECTED_BINDING",d01.listener_gate(text,3078)["status"])

    def test_missing_listener_is_unverified_not_pass(self):
        self.assertEqual("NOT_VERIFIED",d01.listener_gate("",3078)["status"])

    def test_cap_net_admin_capability_parser(self):
        self.assertTrue(d01.cap_net_admin_from_status("Name:\ttest\nCapEff:\t0000000000001000\n"))
        self.assertFalse(d01.cap_net_admin_from_status("CapEff:\t0000000000000000\n"))
        self.assertIsNone(d01.cap_net_admin_from_status("NoCaps: x"))

    def test_real_host_preflight_never_claims_production_readiness(self):
        host=d01.inspect_host()
        self.assertEqual("BLOCKED_D0_ONLY",host["readiness"])
        self.assertEqual("NOT_CONFIGURED_OR_NOT_VERIFIED",host["trusted_tls_certificate"])
        self.assertIn("D-01_D-06_OWNER_APPROVAL_PENDING",host["blockers"])

if __name__=="__main__":
    unittest.main(verbosity=2)
