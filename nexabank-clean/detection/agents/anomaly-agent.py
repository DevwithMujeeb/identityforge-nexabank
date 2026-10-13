#!/usr/bin/env python3
"""
NexaBank Anomaly Detection Agent
==================================
Consumes API audit logs and runs three detection models:

  Model 1 — Volume Spike: flags users with > VOLUME_THRESHOLD requests in WINDOW_MINUTES
  Model 2 — Region Jump: flags tokens used from two different regions within REGION_WINDOW_MINUTES
  Model 3 — Off-Hours Access: flags access outside ALLOWED_HOURS_UTC for a given branch timezone

Designed to be queried by Wazuh via the Wazuh Active Response framework,
or run standalone for development testing.

Usage:
    python anomaly-agent.py --log-file /var/log/nexabank/audit.log
    python anomaly-agent.py --log-file /var/log/nexabank/audit.log --mode stream
"""

import argparse
import json
import logging
import os
import sys
import time
from collections import defaultdict
from datetime import datetime, timezone

# -- Configuration (override with environment variables) --
VOLUME_THRESHOLD = int(os.getenv("VOLUME_THRESHOLD", "100"))        # requests per window
WINDOW_MINUTES = int(os.getenv("WINDOW_MINUTES", "10"))
REGION_WINDOW_MINUTES = int(os.getenv("REGION_WINDOW_MINUTES", "5"))
ALLOWED_HOURS_START_UTC = int(os.getenv("ALLOWED_HOURS_START_UTC", "6"))   # 06:00 UTC
ALLOWED_HOURS_END_UTC = int(os.getenv("ALLOWED_HOURS_END_UTC", "22"))      # 22:00 UTC
ALERT_WEBHOOK = os.getenv("ALERT_WEBHOOK_URL", "")                          # optional HTTP endpoint

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("nexabank-anomaly")


class AnomalyDetector:
    def __init__(self):
        # {userId: [(timestamp, ip, region), ...]}
        self.request_log: dict[str, list] = defaultdict(list)
        self.alerts: list[dict] = []

    def ingest(self, entry: dict):
        """Process one audit log line."""
        user_id = entry.get("userId", "unknown")
        if user_id == "unauthenticated":
            return

        now = datetime.fromisoformat(entry.get("timestamp", datetime.now(timezone.utc).isoformat()))
        ip = entry.get("ip", "")
        region = entry.get("region", "")     # populated from Keycloak token claim

        self.request_log[user_id].append((now, ip, region))
        self._prune(user_id)
        self._check_volume(user_id)
        self._check_region_jump(user_id)
        self._check_off_hours(user_id, now)

    def _prune(self, user_id: str):
        """Remove entries older than the largest window we track."""
        cutoff_minutes = max(WINDOW_MINUTES, REGION_WINDOW_MINUTES) + 1
        cutoff = datetime.now(timezone.utc).timestamp() - (cutoff_minutes * 60)
        self.request_log[user_id] = [
            e for e in self.request_log[user_id]
            if e[0].timestamp() > cutoff
        ]

    def _check_volume(self, user_id: str):
        """Model 1: Volume spike within WINDOW_MINUTES."""
        cutoff = datetime.now(timezone.utc).timestamp() - (WINDOW_MINUTES * 60)
        recent = [e for e in self.request_log[user_id] if e[0].timestamp() > cutoff]
        if len(recent) > VOLUME_THRESHOLD:
            self._alert({
                "model": "volume_spike",
                "userId": user_id,
                "requestCount": len(recent),
                "windowMinutes": WINDOW_MINUTES,
                "threshold": VOLUME_THRESHOLD
            })

    def _check_region_jump(self, user_id: str):
        """Model 2: Token used from two distinct regions within REGION_WINDOW_MINUTES."""
        cutoff = datetime.now(timezone.utc).timestamp() - (REGION_WINDOW_MINUTES * 60)
        recent = [e for e in self.request_log[user_id] if e[0].timestamp() > cutoff]
        regions = {e[2] for e in recent if e[2]}
        if len(regions) > 1:
            self._alert({
                "model": "region_jump",
                "userId": user_id,
                "regions": list(regions),
                "windowMinutes": REGION_WINDOW_MINUTES
            })

    def _check_off_hours(self, user_id: str, timestamp: datetime):
        """Model 3: Access outside allowed hours (UTC)."""
        hour = timestamp.astimezone(timezone.utc).hour
        if not (ALLOWED_HOURS_START_UTC <= hour < ALLOWED_HOURS_END_UTC):
            self._alert({
                "model": "off_hours_access",
                "userId": user_id,
                "hourUtc": hour,
                "allowedWindow": f"{ALLOWED_HOURS_START_UTC:02d}:00-{ALLOWED_HOURS_END_UTC:02d}:00 UTC"
            })

    def _alert(self, payload: dict):
        payload["timestamp"] = datetime.now(timezone.utc).isoformat()
        payload["severity"] = "HIGH"
        logger.warning(f"ALERT: {json.dumps(payload)}")
        self.alerts.append(payload)
        # TODO (mentee): post to ALERT_WEBHOOK or Wazuh Active Response socket


def run_batch(log_file: str):
    """Process a static log file."""
    detector = AnomalyDetector()
    with open(log_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get("event") == "api_request":
                    detector.ingest(entry)
            except json.JSONDecodeError:
                logger.debug(f"Skipping non-JSON line: {line[:80]}")

    logger.info(f"Batch complete. Total alerts: {len(detector.alerts)}")


def run_stream(log_file: str):
    """Tail a log file in real time (like tail -F)."""
    detector = AnomalyDetector()
    logger.info(f"Streaming from {log_file}...")
    with open(log_file) as f:
        f.seek(0, 2)   # seek to end
        while True:
            line = f.readline()
            if not line:
                time.sleep(0.5)
                continue
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                if entry.get("event") == "api_request":
                    detector.ingest(entry)
            except json.JSONDecodeError:
                pass


def main():
    parser = argparse.ArgumentParser(description="NexaBank Anomaly Detection Agent")
    parser.add_argument("--log-file", default="/var/log/nexabank/audit.log")
    parser.add_argument("--mode", choices=["batch", "stream"], default="batch")
    args = parser.parse_args()

    if args.mode == "stream":
        run_stream(args.log_file)
    else:
        run_batch(args.log_file)


if __name__ == "__main__":
    main()
