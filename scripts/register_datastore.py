"""
register_datastore.py
─────────────────────
Called by setup.sh Step 8.
Registers an Azure Blob container as a named datastore in the ML workspace.
"""
import argparse
from azure.ai.ml import MLClient
from azure.ai.ml.entities import AzureBlobDatastore, AccountKeyConfiguration
from azure.identity import DefaultAzureCredential


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--subscription")
    p.add_argument("--resource-group")
    p.add_argument("--workspace")
    p.add_argument("--datastore-name")
    p.add_argument("--account-name")
    p.add_argument("--account-key")
    p.add_argument("--container")
    args = p.parse_args()

    ml_client = MLClient(
        DefaultAzureCredential(),
        args.subscription,
        args.resource_group,
        args.workspace,
    )

    datastore = AzureBlobDatastore(
        name=args.datastore_name,
        description="Project training data — provisioned by setup.sh",
        account_name=args.account_name,
        container_name=args.container,
        credentials=AccountKeyConfiguration(account_key=args.account_key),
    )

    ml_client.datastores.create_or_update(datastore)
    print(f"[✓] Datastore registered: {args.datastore_name} → {args.container}")


if __name__ == "__main__":
    main()
