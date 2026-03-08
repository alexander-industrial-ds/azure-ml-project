# ☁️ Azure ML SDK v2 — Project Blueprint

Standard template for any data science project on Azure Machine Learning.  
Clone this repo, fill in `config.env`, and run `setup.sh` to get a fully
provisioned workspace in minutes.

---

## Quick Start

```bash
# 1. Clone this repo
git clone <this-repo-url>
cd azure-ml-project

# 2. Copy and fill in config (the ONLY file you need to edit)
cp config.env.example config.env
nano config.env       # fill in subscription ID, resource names, GitHub URL

# 3. Make scripts executable
chmod +x setup.sh scripts/*.sh

# 4. Preview what will be created (no resources provisioned)
./setup.sh --config config.env --dry-run

# 5. Run full setup (~5 min)
./setup.sh --config config.env

# 6. Open Studio — URL is printed at the end of setup output
#    Then: Notebooks → Files → notebooks/blueprint.ipynb
```

---

## Project Structure

```
azure-ml-project/
│
├── setup.sh                       ← MASTER: provisions all 12 Azure resources
├── config.env                     ← Your settings (⚠️ never commit — in .gitignore)
├── config.env.example             ← Template — safe to commit, no real values
├── .gitignore                     ← Excludes config.env, data files, logs
├── README.md                      ← This file
│
├── scripts/
│   ├── register_datastore.py      ← Step 8 — registers Blob container as datastore
│   ├── register_data_assets.py    ← Step 9 — reads assets.yml, creates data assets
│   ├── register_environment.py    ← Step 10 — registers conda.yml as environment
│   ├── status.sh                  ← Shows state of all resources + billing warnings
│   └── teardown.sh                ← Deletes everything or stops compute only
│
├── data/
│   ├── assets.yml                 ← Data asset manifest (name, version, path, type)
│   └── mltable/
│       └── MLTable                ← Schema YAML required for AutoML (Block 8)
│
├── environments/
│   └── conda.yml                  ← Pinned Python packages for training jobs
│
├── src/
│   └── train.py                   ← Training script — runs on Compute Cluster (Block 6)
│
└── notebooks/
    └── blueprint.ipynb            ← SDK v2 blueprint notebook (Blocks 0–8)
```

---

## What setup.sh Provisions (12 Steps)

| Step | Resource | CLI Command |
|------|----------|-------------|
| 1 | Validate prerequisites | `check_tool az / python3 / git` |
| 2 | Load config | `source config.env` |
| 3 | Azure login | `az login` |
| 4 | Resource Group | `az group create` |
| 5 | Storage Account + Blob container | `az storage account create` |
| 6 | Azure ML Workspace | `az ml workspace create` |
| 7 | Compute Cluster + Compute Instance | `az ml compute create` |
| 8 | Datastore | `scripts/register_datastore.py` |
| 9 | Data Assets (from `data/assets.yml`) | `scripts/register_data_assets.py` |
| 10 | Environment (from `environments/conda.yml`) | `scripts/register_environment.py` |
| 11 | Clone / pull GitHub repo | `git clone` or `git pull` |
| 12 | Upload data to Blob storage | `az storage blob upload-batch` |

All steps are **idempotent** — re-running `setup.sh` only creates what is missing.

---

## Daily Workflow

```bash
# Check what's running (and billing)
./scripts/status.sh

# End of session — stop compute instance (keeps workspace, saves cost)
./scripts/teardown.sh --stop-compute-only

# End of project — delete everything
./scripts/teardown.sh
```

---

## Adding a New Dataset

1. Upload the file to the `mldata` blob container (or add it to `data/` and re-run setup)
2. Add an entry to `data/assets.yml`:
   ```yaml
   - name: "my-new-dataset"
     version: "1"
     blob_path: "data/my_file.csv"
     type: "uri_file"
   ```
3. Re-run setup — only Step 9 does work, everything else is skipped:
   ```bash
   ./setup.sh --config config.env
   ```

---

## Updating the Environment

1. Edit `environments/conda.yml` (bump a version or add a package)
2. Re-run setup with a new version number:
   ```bash
   # In register_environment.py or pass as arg:
   python3 scripts/register_environment.py ... --version 2
   ```
3. Update `environment = "azureml:project-training-env:2"` in your notebook

> **Pin both MLflow packages together** to avoid the `ArtifactRepository.__init__()` error:
> `mlflow==2.22.0` + `azureml-mlflow==1.51.0`

---

## Scripts Reference

| Script | Flags | When to run |
|--------|-------|-------------|
| `setup.sh` | `--config FILE` `--dry-run` | Once per project, or after config changes |
| `scripts/status.sh` | — | Anytime — shows state + billing warnings |
| `scripts/teardown.sh` | — | End of project — deletes resource group |
| `scripts/teardown.sh` | `--stop-compute-only` | End of workday — stops instance, keeps workspace |
| `scripts/teardown.sh` | `--force` | CI/CD pipelines — skips confirmation prompt |

---

## Cost Management

| Resource | Billing behaviour | Action needed |
|----------|------------------|---------------|
| Compute **Cluster** | Only during active jobs (min=0 scales to zero) | None — automatic |
| Compute **Instance** | While running | `teardown.sh --stop-compute-only` after each session |
| Storage Account | Per GB stored | Negligible for lab data |
| ML Workspace | Free (pay only for compute/storage) | None |

---

## Notebook Blueprint (Blocks 0–8)

Open `notebooks/blueprint.ipynb` on the Compute Instance in Azure ML Studio.

| Block | What it does | Key concept |
|-------|-------------|-------------|
| 0 | Install & Imports | All SDK v2 packages |
| 1 | Auth & Workspace | `MLClient` + `DefaultAzureCredential` |
| 2 | Compute | Instance vs Cluster |
| 3 | Datastores | Connection reference to storage |
| 4 | Data Assets | Versioned pointers — URI_FILE / URI_FOLDER / MLTable |
| 5 | Environments | Curated vs custom, Docker build lifecycle |
| 6 | Command Job | Submit `src/train.py` to cluster |
| 7 | MLflow Tracking | Manual logging + autolog + search_runs |
| 8 | AutoML | Auto model selection + SHAP explainability |

---

## DP-100 Exam Coverage

| setup.sh Steps | Exam Domain | Weight |
|----------------|-------------|--------|
| Steps 4–10 (all Azure ML resources) | Design and Prepare a Machine Learning Solution | 20–25% |
| Block 6 (Command Job) | Explore Data and Run Experiments | 20–25% |
| Block 7 (MLflow) | Explore Data and Run Experiments | 20–25% |
| Block 8 (AutoML + explainability) | Explore Data and Run Experiments | 20–25% |

---

## Navigation Maps (companion documents)

Two Word documents explain every line of this project:

| Document | What it covers |
|----------|---------------|
| `blueprint_navigation_map.docx` | Blocks 0–8 in the notebook — global view, block deep dives, exam cheat sheet |
| `setup_navigation_map.docx` | Every step in setup.sh — config variables, CLI commands, helper scripts |
