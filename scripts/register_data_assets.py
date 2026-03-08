"""
register_data_assets.py
────────────────────────
Called by setup.sh Step 9.
Reads a manifest (data/assets.yml) and registers each entry as a versioned
data asset in the ML workspace. Falls back to scanning the data/ folder.
"""
import argparse
import os
import yaml
from azure.ai.ml import MLClient
from azure.ai.ml.entities import Data
from azure.ai.ml.constants import AssetTypes
from azure.identity import DefaultAzureCredential


ASSET_TYPE_MAP = {
    "uri_file":   AssetTypes.URI_FILE,
    "uri_folder": AssetTypes.URI_FOLDER,
    "mltable":    AssetTypes.MLTABLE,
}


def build_datastore_path(datastore_name: str, blob_path: str) -> str:
    """Converts a blob path to the azureml:// datastore URI format."""
    return f"azureml://datastores/{datastore_name}/paths/{blob_path}"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--subscription")
    p.add_argument("--resource-group")
    p.add_argument("--workspace")
    p.add_argument("--datastore-name")
    p.add_argument("--data-dir", default="./data")
    args = p.parse_args()

    ml_client = MLClient(
        DefaultAzureCredential(),
        args.subscription,
        args.resource_group,
        args.workspace,
    )

    # ── Try manifest first ────────────────────────────────────────────────────
    manifest_path = os.path.join(args.data_dir, "assets.yml")
    if os.path.exists(manifest_path):
        with open(manifest_path) as f:
            manifest = yaml.safe_load(f)

        for entry in manifest.get("assets", []):
            asset = Data(
                name=entry["name"],
                version=str(entry.get("version", "1")),
                description=entry.get("description", ""),
                path=build_datastore_path(args.datastore_name, entry["blob_path"]),
                type=ASSET_TYPE_MAP[entry.get("type", "uri_file")],
            )
            ml_client.data.create_or_update(asset)
            print(f"[✓] Registered: {entry['name']} v{entry.get('version', 1)} [{entry.get('type', 'uri_file')}]")

    else:
        # ── Fallback: auto-register CSV files found in data/ ─────────────────
        print("[!] No assets.yml found — scanning data/ folder for CSV files")
        for fname in os.listdir(args.data_dir):
            if fname.endswith(".csv"):
                name = os.path.splitext(fname)[0].replace("_", "-")
                asset = Data(
                    name=name,
                    version="1",
                    description=f"Auto-registered from {fname}",
                    path=build_datastore_path(args.datastore_name, fname),
                    type=AssetTypes.URI_FILE,
                )
                ml_client.data.create_or_update(asset)
                print(f"[✓] Auto-registered: {name} v1 [uri_file]")


if __name__ == "__main__":
    main()
