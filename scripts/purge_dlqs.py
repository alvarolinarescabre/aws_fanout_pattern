#!/usr/bin/env python3
import argparse
import json
import subprocess
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description="Purge all DLQs from Terraform outputs.")
    parser.add_argument("--region", required=True, help="AWS region for the SQS purge calls")
    parser.add_argument("--outputs", default="terraform/outputs.json", help="Path to Terraform outputs JSON")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    outputs_path = Path(args.outputs)
    if not outputs_path.exists():
        raise SystemExit(f"Terraform outputs file not found: {outputs_path}")

    outputs = json.loads(outputs_path.read_text())
    dlqs = outputs.get("dlqs")
    if not dlqs:
        print("No DLQ URLs found in Terraform outputs.")
        return 0

    for dlq in dlqs:
        url = dlq.get("url")
        if not url:
            continue
        print("Purging", url)
        subprocess.run(
            ["aws", "sqs", "purge-queue", "--region", args.region, "--queue-url", url],
            check=True,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
