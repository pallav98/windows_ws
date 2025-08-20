import boto3
import csv
import os
import time

AWS_REGION = os.getenv("AWS_REGION", "us-east-1")
CSV_FILE = os.getenv("WORKSPACES_CSV", "workspaces.csv")

# Name mapping of packages to PowerShell scripts (stored in S3 or inline)
name_map = {
    "zscaler": "zscaler.ps1",
    "splunk": "splunk_uf.ps1",
    "bit9": "bit9_cbac.ps1",
    "winlogbeat": "winlogbeat.ps1",
    "elastic": "elastic_agent.ps1",
    "crowdstrike": "crowdstrike.ps1",
    "nessus": "nessus.ps1",
    "bigfix": "bigfix.ps1",
}

# AWS Clients
ssm = boto3.client("ssm", region_name=AWS_REGION)
workspaces = boto3.client("workspaces", region_name=AWS_REGION)


def get_instance_id_from_workspace(workspace_id):
    """Get EC2 instance ID from Workspace ID."""
    response = workspaces.describe_workspaces(WorkspaceIds=[workspace_id])
    if not response["Workspaces"]:
        raise Exception(f"No workspace found for {workspace_id}")
    return response["Workspaces"][0]["WorkspaceId"], response["Workspaces"][0]["ComputerName"]


def send_ssm_command(instance_id, script_name):
    """Send SSM RunCommand to instance for PowerShell script."""
    with open(f"scripts/{script_name}", "r") as f:
        ps_script = f.read()

    response = ssm.send_command(
        InstanceIds=[instance_id],
        DocumentName="AWS-RunPowerShellScript",
        Parameters={"commands": [ps_script]},
    )
    return response["Command"]["CommandId"]


def wait_for_command(command_id, instance_id):
    """Wait until SSM command completes and return output."""
    while True:
        time.sleep(5)
        result = ssm.list_command_invocations(
            CommandId=command_id,
            InstanceId=instance_id,
            Details=True
        )
        if result["CommandInvocations"]:
            status = result["CommandInvocations"][0]["Status"]
            if status in ["Success", "Failed", "Cancelled", "TimedOut"]:
                output = result["CommandInvocations"][0]["CommandPlugins"][0].get("Output", "")
                return status, output


def main():
    report = []

    with open(CSV_FILE, newline="") as csvfile:
        reader = csv.DictReader(csvfile)
        for row in reader:
            workspace_id = row["workspace_id"]
            username = row["username"]

            try:
                ws_id, computer_name = get_instance_id_from_workspace(workspace_id)
                instance_id = workspace_id  # Adjust if mapping to EC2 ID via Fleet Manager

                print(f"\n[INFO] Processing {workspace_id} ({username}, {computer_name})")

                for pkg, script in name_map.items():
                    print(f"[INFO] Installing {pkg} on {workspace_id}...")

                    command_id = send_ssm_command(instance_id, script)
                    status, output = wait_for_command(command_id, instance_id)

                    report.append({
                        "workspace_id": workspace_id,
                        "username": username,
                        "package": pkg,
                        "status": status,
                        "output": output.strip()[:200]  # Truncate for readability
                    })

                    print(f"[{status}] {pkg} on {workspace_id}")
                    if output:
                        print(f"Output: {output[:200]}")

            except Exception as e:
                report.append({
                    "workspace_id": workspace_id,
                    "username": username,
                    "package": "ALL",
                    "status": "ERROR",
                    "output": str(e)
                })
                print(f"[ERROR] {workspace_id}: {e}")

    print("\n===== FINAL REPORT =====")
    for r in report:
        print(f"{r['workspace_id']} ({r['username']}) - {r['package']}: {r['status']}")

if __name__ == "__main__":
    main()
