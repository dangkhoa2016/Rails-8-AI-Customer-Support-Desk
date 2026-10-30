#!/usr/bin/env python3
"""P0.3 D-01 local READ-ONLY private VPN+HTTPS readiness inspection.

Never deploys/installs, creates credentials, opens ports, starts daemons,
changes Git, or connects to providers. No environment values are printed.
This Colab preflight is not a certification for a persistent production host.
"""
import argparse
import datetime as dt
import hashlib
import json
import pathlib
import re
import shutil
import socket
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONTRACT = ROOT / "config/security/p03_d01_private_https_contract.json"
EXPECTED = "p03.d01.gateway-contract.v1"

def evaluate_contract(c):
    assert isinstance(c, dict) and c.get("schema_version") == EXPECTED
    assert c.get("status") == "DESIGN_ONLY_NOT_APPROVED"
    assert c.get("owner_decision") == "D-01_PENDING"
    assert c.get("deployment_authorization") == "D-06_PENDING"
    checks = c.get("non_negotiable")
    assert isinstance(checks, dict) and len(checks) >= 18
    assert checks.get("operator_origin_public_routable") is False
    assert checks.get("persistent_host_outside_colab") is True
    assert checks.get("rails_force_ssl") is True
    assert checks.get("session_cookie_secure") is True
    assert checks.get("no_real_admin_until_owner_approval") is True
    assert checks.get("public_demo_read_only_unchanged") is True
    assert checks.get("trusted_proxy_exact_allowlist") is True
    assert checks.get("deny_forwarded_identity_headers_from_client") is True
    tests=c.get("negative_tests")
    assert isinstance(tests,list) and len(tests) >= 12 and len(tests)==len(set(tests))
    return {"status":"PASS_STATIC_CONTRACT_ONLY","checks":len(checks),"negative_tests":len(tests)}

def parse_listeners(text, port):
    """Return all local addresses with LISTEN on exact TCP port."""
    addresses=[]
    for line in text.splitlines():
        parts=line.split()
        if not parts or parts[0] != "LISTEN" or len(parts)<5:continue
        local=parts[3]
        if local.startswith("[") and "]:" in local:
            address, sep, end=local[1:].partition("]:")
            suffix=end if sep else ""
        else:
            address, sep, suffix=local.rpartition(":")
        if suffix==str(port):
            addresses.append(address)
    return addresses

def listener_gate(text,port):
    bindings=parse_listeners(text,port)
    if not bindings:return {"status":"NOT_VERIFIED","bindings":[]}
    ok=all(x in ("127.0.0.1","::1","localhost") for x in bindings)
    return {"status":"PASS_LOCAL_LOOPBACK" if ok else "FAIL_UNEXPECTED_BINDING",
            "bindings":bindings}

def cap_net_admin_from_status(text):
    match=re.search(r"^CapEff:\s*([0-9a-fA-F]+)$",text,re.M)
    if not match:return None
    return bool(int(match.group(1),16)&(1<<12))

def run_read_only(args):
    try:
        p=subprocess.run(args,stdout=subprocess.PIPE,stderr=subprocess.PIPE,
                         text=True,timeout=5,check=False)
        return p.stdout if p.returncode==0 else None
    except (OSError,subprocess.TimeoutExpired):
        return None

def inspect_host():
    ss=run_read_only(["ss","-ltnH"])
    status_path=pathlib.Path("/proc/self/status")
    caps=cap_net_admin_from_status(status_path.read_text() if status_path.exists() else "")
    host=socket.gethostname()
    colab_marker=pathlib.Path("/content").is_dir() and (
        not pathlib.Path("/run/systemd/system").exists())
    bindings={
      "platform_sandbox_3078":listener_gate(ss,3078) if ss is not None else {"status":"NOT_VERIFIED"},
      "demo_readonly_3068":listener_gate(ss,3068) if ss is not None else {"status":"NOT_VERIFIED"},
    }
    components={
      "wg_utility_present":shutil.which("wg") is not None,
      "reverse_proxy_binary_present":any(shutil.which(x) for x in ("caddy","nginx","haproxy")),
      "tun_device_present":pathlib.Path("/dev/net/tun").exists(),
      "cap_net_admin_effective":caps,
      "persistent_systemd_host_verified":pathlib.Path("/run/systemd/system").exists(),
      "tls_openssl_available":shutil.which("openssl") is not None,
    }
    missing=[key for key in ("wg_utility_present","reverse_proxy_binary_present",
              "cap_net_admin_effective","persistent_systemd_host_verified")
            if components[key] is not True]
    if bindings["platform_sandbox_3078"]["status"]=="FAIL_UNEXPECTED_BINDING":
        missing.append("platform_sandbox_binds_non_loopback")
    result={
      "host_label":host,
      "host_type":"COLAB_LIKE_EPHEMERAL" if colab_marker else "UNCLASSIFIED",
      "components":components,
      "bindings":bindings,
      "private_gateway_live":"NOT_DEPLOYED_OR_NOT_VERIFIED",
      "vpn_peer_identity":"NOT_CONFIGURED_OR_NOT_VERIFIED",
      "trusted_tls_certificate":"NOT_CONFIGURED_OR_NOT_VERIFIED",
      "owner_selected_persistent_host":"NOT_PROVIDED",
      "blockers":missing + ["D-01_D-06_OWNER_APPROVAL_PENDING",
                             "PERSISTENT_HOST_AND_VPN_PEER_NOT_SELECTED",
                             "INDEPENDENT_WORM_AND_EMERGENCY_RECOVERY_PENDING"],
    }
    result["readiness"]="BLOCKED_D0_ONLY"
    return result

def inspect_git():
    head=run_read_only(["git","-C",str(ROOT),"rev-parse","HEAD"])
    if head is None: return {"status":"NOT_VERIFIED"}
    return {
       "status":"READ_ONLY_CHECK",
       "head":head.strip(),
       "base_head_expected":"efebe1ad67a964716d2b255198765441c926ef66",
       "matches_base":head.strip()=="efebe1ad67a964716d2b255198765441c926ef66",
    }

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--output",help="Write sanitized JSON evidence to a specified local path")
    args=p.parse_args()
    raw=CONTRACT.read_bytes()
    contract=json.loads(raw)
    data={
      "schema_version":"p03.d01.host-readiness.v1",
      "generated_utc":dt.datetime.now(dt.timezone.utc).isoformat(),
      "operation":"READ_ONLY_INSPECTION",
      "config_sha256":hashlib.sha256(raw).hexdigest(),
      "contract":evaluate_contract(contract),
      "host":inspect_host(),
      "git":inspect_git(),
      "owner_decisions":{"D-01":"PENDING","D-06":"PENDING"},
      "external_gateway_deployment":"NOT_RUN",
      "hardware_mfa_and_https_live_validation":"NOT_RUN",
      "confidence":"local host observation only; no remote persistent host tested",
    }
    rendered=json.dumps(data,indent=2,sort_keys=True)+"\n"
    if args.output:
        target=pathlib.Path(args.output)
        assert target.parent.is_dir(),"Output parent must pre-exist"
        assert not target.exists(),"Refusing to overwrite existing evidence"
        target.write_text(rendered)
    print(rendered,end="")

if __name__=="__main__":
    main()
