#!/usr/bin/env python3
"""
controller.py

Orchestrates running PowerShell installer scripts on AWS WorkSpaces via SSM.

Usage examples:
  AWS_REGION=us-east-1 python scripts/controller.py --csv workspaces.csv
  python scripts/controller.py --region us-west-2 --csv inputs/ws.csv --scripts-dir scripts --agents zscaler,splunk

Notes:
 - The controller uses AWS-RunPowerShellScript to execute inline PowerShell.
 - Ensure the GitHub Actions runner or the environment has AWS credentials with:
     ssm:SendCommand, ssm:ListCommandInvocations, ssm:DescribeInstanceInformation, workspaces:DescribeWorkspaces (optional)
 - The WorkSpaceId is expected to be the SSM-managed InstanceId for WorkSpaces (common in Fleet Manager).
"""

import os
import sys
import time
import csv
import argparse
from typing import List, Dict, Tuple
import boto3
from botocore.exceptions import ClientError

DEFAULT_SEQUENCE = [
    "zscaler.ps1",
    "splunk_uf.ps1",
    "bit9_cbac.ps1",
    "winlogbeat.ps1",
    "elastic_agent.ps1",
    "crowdstrike.ps1",
    "nessus.ps1",
    "bigfix.ps1",
]

# SSM polling settings
POLL_INTERVAL = 5        # seconds between polls
DEFAULT_TIMEOUT = 3600   # seconds per SSM command


def read_workspaces(csv_path: str) -> List[Dict[str, str]]:
    rows = []
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"CSV file not found: {csv_path}")
    with open(csv_path, newline="", encoding="utf-8") as fh:
        reader = csv.DictReader(fh)
        required = {"workspace_id", "username"}
        if not required.issubset(set(map(str.lower, reader.fieldnames or []))):
            raise ValueError(f"CSV must contain headers: workspace_id,username (found: {reader.fieldnames})")
        for r in reader:
            # Support either header-case or any case
            ws = r.get("workspace_id") or r.get("Workspace_ID") or r.get("WorkspaceId") or r.get("workspaceId")
            user = r.get("username") or r.get("user") or ""
            if ws:
                rows.append({"workspace_id": ws.strip(), "username": (user or "").strip()})
    return rows


def load_scripts(scripts_dir: str, sequence: List[str]) -> List[Tuple[str, str]]:
    """Load script files in the given order. Returns list of (script_name, content)."""
    out = []
    for name in sequence:
        path = os.path.join(scripts_dir, name)
        if not os.path.exists(path):
            raise FileNotFoundError(f"Script not found: {path}")
        with open(path, "r", encoding="utf-8") as fh:
            content = fh.read()
        out.append((name, content))
    return out


def resolve_ssm_managed_instances(ssm_client, workspace_ids: List[str]) -> Dict[str, bool]:
    """
    Build a set/map of which workspace_ids exist as SSM managed instance IDs in this region.
    Returns map: workspace_id -> True/False (True means found in SSM)
    """
    found = {ws: False for ws in workspace_ids}
    paginator = ssm_client.get_paginator("describe_instance_information")
    try:
        for page in paginator.paginate():
            for inst in page.get("InstanceInformationList", []):
                inst_id = inst.get("InstanceId")
                if inst_id in found:
                    found[inst_id] = True
    except ClientError as e:
        raise RuntimeError(f"Failed to list SSM instances: {e}")
    return found


def send_command_and_wait(
    ssm_client,
    instance_id: str,
    ps_script: str,
    timeout_seconds: int = DEFAULT_TIMEOUT,
    comment: str = None,
) -> Dict[str, str]:
    """
    Send an AWS-RunPowerShellScript command to a single instance and wait for completion.
    Returns a dict with keys: status, response_code, stdout, stderr, command_id
    """
    params = {
        "DocumentName": "AWS-RunPowerShellScript",
        "InstanceIds": [instance_id],
        "Parameters": {"commands": [ps_script]},
    }
    if comment:
        params["Comment"] = comment

    try:
        resp = ssm_client.send_command(**params)
    except ClientError as e:
        return {
            "status": "SendCommandFailed",
            "response_code": "",
            "stdout": "",
            "stderr": str(e),
            "command_id": "",
        }

    command_id = resp["Command"]["CommandId"]
    deadline = time.time() + timeout_seconds
    result = {
        "status": "Pending",
        "response_code": "",
        "stdout": "",
        "stderr": "",
        "command_id": command_id,
    }

    while time.time() < deadline:
        time.sleep(POLL_INTERVAL)
        try:
            inv = ssm_client.list_command_invocations(CommandId=command_id, InstanceId=instance_id, Details=True)
        except ClientError as e:
            result["status"] = "ListInvocationsFailed"
            result["stderr"] = str(e)
            return result

        invs = inv.get("CommandInvocations", [])
        if not invs:
            continue

        item = invs[0]
        status = item.get("Status", "Unknown")
        result["status"] = status

        # Plugin item contains the actual output for the aws:runPowerShellScript plugin
        plugins = item.get("CommandPlugins", [])
        if plugins:
            p = plugins[0]
            result["response_code"] = str(p.get("ResponseCode") or "")
            # Some fields may be None
            result["stdout"] = p.get("Output") or ""
            result["stderr"] = p.get("StandardErrorContent") or ""

        if status in ("Success", "Failed", "Cancelled", "TimedOut"):
            break

    # If we exit loop due to timeout
    if result["status"] not in ("Success", "Failed", "Cancelled", "TimedOut"):
        result["status"] = "TimedOut"
    return result


def write_results_csv(out_path: str, rows: List[Dict[str, str]]) -> None:
    fieldnames = [
        "workspace_id",
        "username",
        "agent_script",
        "status",
        "response_code",
        "stdout_snippet",
        "stderr_snippet",
        "command_id",
    ]
    with open(out_path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow(r)


def parse_args():
    p = argparse.ArgumentParser(description="Run PowerShell agent installers on WorkSpaces via SSM.")
    p.add_argument("--region", "-r", default=os.getenv("AWS_REGION", "us-east-1"), help="AWS region")
    p.add_argument("--csv", "-c", default=os.getenv("WORKSPACE_CSV", "workspaces.csv"), help="CSV file path (workspace_id,username)")
    p.add_argument("--scripts-dir", "-s", default=os.getenv("SCRIPTS_DIR", "scripts"), help="Directory containing .ps1 scripts")
    p.add_argument("--agents", "-a", default=None, help="Comma-separated sequence of .ps1 filenames (default sequence used if omitted)")
    p.add_argument("--timeout", "-t", default=int(os.getenv("COMMAND_TIMEOUT", DEFAULT_TIMEOUT)), type=int, help="Timeout in seconds per SSM command")
    p.add_argument("--out", "-o", default="ssm_results.csv", help="Output CSV summary")
    return p.parse_args()


def main():
    args = parse_args()

    region = args.region
    csv_path = args.csv
    scripts_dir = args.scripts_dir
    timeout = args.timeout
    out_csv = args.out

    if args.agents:
        sequence = [s.strip() for s in args.agents.split(",") if s.strip()]
    else:
        sequence = DEFAULT_SEQUENCE.copy()

    # Load workspaces
    try:
        workspaces = read_workspaces(csv_path)
    except Exception as e:
        print(f"[ERROR] Failed to read CSV: {e}", file=sys.stderr)
        sys.exit(2)
    if not workspaces:
        print(f"[ERROR] No workspace rows found in {csv_path}", file=sys.stderr)
        sys.exit(2)

    # Load scripts
    try:
        scripts = load_scripts(scripts_dir, sequence)
    except Exception as e:
        print(f"[ERROR] Failed to load scripts: {e}", file=sys.stderr)
        sys.exit(3)

    # Create boto3 clients
    ssm = boto3.client("ssm", region_name=region)

    # Resolve which workspace IDs are registered in SSM
    workspace_ids = [r["workspace_id"] for r in workspaces]
    print(f"[INFO] Resolving SSM-managed instances for {len(workspace_ids)} workspace IDs in region {region}...")
    try:
        ssm_map = resolve_ssm_managed_instances(ssm, workspace_ids)
    except Exception as e:
        print(f"[ERROR] Could not resolve SSM instances: {e}", file=sys.stderr)
        sys.exit(4)

    # Report which are missing
    missing = [k for k, v in ssm_map.items() if not v]
    if missing:
        print("[WARN] The following workspace IDs were NOT found as SSM managed instances in this region:")
        for m in missing:
            print("  -", m)
        print("[WARN] Commands will NOT be sent to missing instances. Ensure SSM agent is running on those WorkSpaces.")

    results = []

    # Iterate through CSV rows in order and run each script in sequence
    for idx, row in enumerate(workspaces, start=1):
        wsid = row["workspace_id"]
        user = row.get("username", "")
        print(f"\n=== ({idx}/{len(workspaces)}) Workspace {wsid} ({user}) ===")

        if not ssm_map.get(wsid, False):
            print(f"[SKIP] {wsid} not registered with SSM (skipping all agents for this workspace).")
            for script_name, _ in scripts:
                results.append({
                    "workspace_id": wsid,
                    "username": user,
                    "agent_script": script_name,
                    "status": "SSMNotFound",
                    "response_code": "",
                    "stdout_snippet": "",
                    "stderr_snippet": "",
                    "command_id": ""
                })
            continue

        for script_name, script_body in scripts:
            print(f"[RUN] {script_name} -> {wsid}")
            try:
                result = send_command_and_wait(
                    ssm_client=ssm,
                    instance_id=wsid,
                    ps_script=script_body,
                    timeout_seconds=timeout,
                    comment=f"install-{script_name}"
                )
            except Exception as e:
                print(f"[ERROR] Exception while sending command: {e}")
                result = {
                    "status": "SendFailed",
                    "response_code": "",
                    "stdout": "",
                    "stderr": str(e),
                    "command_id": ""
                }

            stdout_snip = (result.get("stdout") or "")[-4000:]  # keep last chunk
            stderr_snip = (result.get("stderr") or "")[-4000:]

            print(f"[{script_name}] status={result.get('status')} rc={result.get('response_code')}")
            if stdout_snip:
                print("----- STDOUT (tail) -----")
                print(stdout_snip)
            if stderr_snip:
                print("----- STDERR (tail) -----")
                print(stderr_snip)

            results.append({
                "workspace_id": wsid,
                "username": user,
                "agent_script": script_name,
                "status": result.get("status", ""),
                "response_code": result.get("response_code", ""),
                "stdout_snippet": stdout_snip,
                "stderr_snippet": stderr_snip,
                "command_id": result.get("command_id", "")
            })

    # Write summary CSV
    try:
        write_results_csv(out_csv, results)
        print(f"\n[INFO] Wrote results to {out_csv}")
    except Exception as e:
        print(f"[ERROR] Failed to write results CSV: {e}", file=sys.stderr)
        sys.exit(5)

    print("[INFO] Completed all operations.")


if __name__ == "__main__":
    main()
