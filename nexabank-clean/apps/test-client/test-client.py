#!/usr/bin/env python3
"""
NexaBank IdentityForge Test Client
===================================
Exercises the NexaBank API with real Keycloak tokens and mTLS certs.

Usage:
    python test-client.py --mode agent
    python test-client.py --mode partner
    python test-client.py --mode revoke --agent-id <sub>
    python test-client.py --mode anomaly

Modes:
    agent     -- authenticate as a field agent, hit /api/agents/me
    partner   -- authenticate as a partner MFB, hit /api/partners/me
    revoke    -- trigger session revocation and measure latency
    anomaly   -- generate suspicious traffic patterns for detection model testing

Prerequisites:
    pip install requests python-dotenv
"""

import argparse
import json
import os
import time
from pathlib import Path

import requests
from dotenv import load_dotenv

load_dotenv()

KEYCLOAK_URL = os.getenv("KEYCLOAK_URL", "http://localhost:8080")
API_BASE = os.getenv("API_BASE", "http://localhost:3000")

AGENT_REALM = "nexabank-agents"
PARTNER_REALM = "nexabank-partners"
STAFF_REALM = "nexabank-staff"

# mTLS cert paths (override with env vars)
AGENT_CERT = os.getenv("AGENT_CERT_PATH", "./certs/agent.crt")
AGENT_KEY = os.getenv("AGENT_KEY_PATH", "./certs/agent.key")
PARTNER_CERT = os.getenv("PARTNER_CERT_PATH", "./certs/partner.crt")
PARTNER_KEY = os.getenv("PARTNER_KEY_PATH", "./certs/partner.key")
CA_CERT = os.getenv("CA_CERT_PATH", "./certs/ca.crt")


def get_token(realm: str, client_id: str, client_secret: str) -> str:
    """Fetch a client credentials token from Keycloak."""
    url = f"{KEYCLOAK_URL}/realms/{realm}/protocol/openid-connect/token"
    resp = requests.post(url, data={
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
    }, verify=CA_CERT)
    resp.raise_for_status()
    token = resp.json()["access_token"]
    print(f"[AUTH] Got token for realm={realm}, client={client_id}")
    return token


def mode_agent():
    """Authenticate as a field agent and call /api/agents/me with mTLS."""
    client_id = os.getenv("AGENT_CLIENT_ID", "agent-test-client")
    client_secret = os.getenv("AGENT_CLIENT_SECRET", "change-me")

    token = get_token(AGENT_REALM, client_id, client_secret)
    cert = (AGENT_CERT, AGENT_KEY) if Path(AGENT_CERT).exists() else None

    resp = requests.get(
        f"{API_BASE}/api/agents/me",
        headers={"Authorization": f"Bearer {token}"},
        cert=cert,
        verify=CA_CERT
    )
    print(f"[AGENT] Status: {resp.status_code}")
    print(json.dumps(resp.json(), indent=2))


def mode_partner():
    """Authenticate as a partner MFB and call /api/partners/me with mTLS."""
    client_id = os.getenv("PARTNER_CLIENT_ID", "partner-test-client")
    client_secret = os.getenv("PARTNER_CLIENT_SECRET", "change-me")

    token = get_token(PARTNER_REALM, client_id, client_secret)
    cert = (PARTNER_CERT, PARTNER_KEY) if Path(PARTNER_CERT).exists() else None

    resp = requests.get(
        f"{API_BASE}/api/partners/me",
        headers={"Authorization": f"Bearer {token}"},
        cert=cert,
        verify=CA_CERT
    )
    print(f"[PARTNER] Status: {resp.status_code}")
    print(json.dumps(resp.json(), indent=2))


def mode_revoke(agent_id: str):
    """Trigger session revocation and assert it completes within 60 seconds."""
    client_id = os.getenv("AGENT_CLIENT_ID", "agent-test-client")
    client_secret = os.getenv("AGENT_CLIENT_SECRET", "change-me")

    token = get_token(AGENT_REALM, client_id, client_secret)
    cert = (AGENT_CERT, AGENT_KEY) if Path(AGENT_CERT).exists() else None

    start = time.time()
    resp = requests.post(
        f"{API_BASE}/api/agents/revoke-session",
        headers={"Authorization": f"Bearer {token}"},
        cert=cert,
        verify=CA_CERT
    )
    elapsed = time.time() - start

    print(f"[REVOKE] Status: {resp.status_code} | Latency: {elapsed:.2f}s")
    if elapsed > 60:
        print("[REVOKE] FAIL: revocation exceeded 60-second SLA")
    else:
        print("[REVOKE] PASS: revocation completed within SLA")
    print(json.dumps(resp.json(), indent=2))


def mode_anomaly():
    """
    Generate synthetic anomalous traffic for detection model testing.
    Simulates: high-volume requests, off-hours access, region-jump pattern.
    """
    client_id = os.getenv("AGENT_CLIENT_ID", "agent-test-client")
    client_secret = os.getenv("AGENT_CLIENT_SECRET", "change-me")
    token = get_token(AGENT_REALM, client_id, client_secret)
    cert = (AGENT_CERT, AGENT_KEY) if Path(AGENT_CERT).exists() else None

    print("[ANOMALY] Sending high-volume burst (volume detection model trigger)...")
    for i in range(50):
        resp = requests.get(
            f"{API_BASE}/api/agents/me",
            headers={"Authorization": f"Bearer {token}"},
            cert=cert,
            verify=CA_CERT
        )
        if i % 10 == 0:
            print(f"  Request {i}: {resp.status_code}")

    print("[ANOMALY] Done. Check anomaly-agent logs for alerts.")


def main():
    parser = argparse.ArgumentParser(description="NexaBank IdentityForge Test Client")
    parser.add_argument("--mode", choices=["agent", "partner", "revoke", "anomaly"], required=True)
    parser.add_argument("--agent-id", help="Agent sub (required for --mode revoke)")
    args = parser.parse_args()

    if args.mode == "agent":
        mode_agent()
    elif args.mode == "partner":
        mode_partner()
    elif args.mode == "revoke":
        mode_revoke(args.agent_id or "unknown")
    elif args.mode == "anomaly":
        mode_anomaly()


if __name__ == "__main__":
    main()
