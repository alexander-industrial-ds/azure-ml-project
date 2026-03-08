"""
register_environment.py
────────────────────────
Called by setup.sh Step 10.
Registers a custom conda environment in the ML workspace.
"""
import argparse
from azure.ai.ml import MLClient
from azure.ai.ml.entities import Environment
from azure.identity import DefaultAzureCredential


BASE_IMAGE = "mcr.microsoft.com/azureml/openmpi4.1.0-ubuntu20.04"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--subscription")
    p.add_argument("--resource-group")
    p.add_argument("--workspace")
    p.add_argument("--env-name")
    p.add_argument("--conda-file")
    p.add_argument("--version", default="1")
    args = p.parse_args()

    ml_client = MLClient(
        DefaultAzureCredential(),
        args.subscription,
        args.resource_group,
        args.workspace,
    )

    env = Environment(
        name=args.env_name,
        version=args.version,
        description="Training environment — provisioned by setup.sh",
        image=BASE_IMAGE,
        conda_file=args.conda_file,
    )

    ml_client.environments.create_or_update(env)
    print(f"[✓] Environment registered: {args.env_name} v{args.version}")
    print(f"    First job use will trigger Docker build in ACR (~5-10 min)")


if __name__ == "__main__":
    main()


