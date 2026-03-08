"""
train.py — Standard Training Script
─────────────────────────────────────
Runs on the Compute Cluster (submitted via Block 6 Command Job in blueprint.ipynb).
Reads training data, trains a LogisticRegression model, logs everything to MLflow.

USAGE (submitted by command() in blueprint.ipynb):
  python train.py --training_data <path> --reg_rate 0.1

ARGUMENTS:
  --training_data   Path to training CSV (injected by Azure ML as ${{inputs.training_data}})
  --reg_rate        Regularization rate (default: 0.1)
  --output_dir      Where to save the model artifact (default: ./outputs)
"""

import argparse
import os
import pandas as pd
import mlflow
import mlflow.sklearn
import matplotlib.pyplot as plt

from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import (
    accuracy_score,
    roc_auc_score,
    classification_report,
    RocCurveDisplay,
)


# =============================================================================
# ARGUMENT PARSING
# =============================================================================
def parse_args():
    parser = argparse.ArgumentParser(description="Train a classification model")
    parser.add_argument("--training_data", type=str,  required=True,
                        help="Path to training CSV file")
    parser.add_argument("--reg_rate",      type=float, default=0.1,
                        help="Regularization rate (C = 1/reg_rate)")
    parser.add_argument("--output_dir",    type=str,  default="./outputs",
                        help="Directory to save model outputs")
    return parser.parse_args()


# =============================================================================
# MAIN
# =============================================================================
def main():
    args = parse_args()
    os.makedirs(args.output_dir, exist_ok=True)

    # ── NOTE: In a Command Job, MLflow auto-connects to Azure ML workspace ────
    # No set_tracking_uri() needed here — that is only required in Block 7
    # (interactive notebook running on Compute Instance)
    mlflow.start_run()

    # ── Log hyperparameters ───────────────────────────────────────────────────
    mlflow.log_param("regularization_rate", args.reg_rate)
    mlflow.log_param("solver", "lbfgs")
    mlflow.log_param("max_iter", 1000)

    # ── Load data ─────────────────────────────────────────────────────────────
    print(f"Loading data from: {args.training_data}")
    df = pd.read_csv(args.training_data)

    # ── CONFIGURE: adjust these column names to match your dataset ────────────
    TARGET_COLUMN  = "Diabetic"    # column to predict
    DROP_COLUMNS   = ["PatientID"] # ID/non-feature columns to remove
    # ─────────────────────────────────────────────────────────────────────────

    feature_cols = [c for c in df.columns if c != TARGET_COLUMN and c not in DROP_COLUMNS]
    X = df[feature_cols]
    y = df[TARGET_COLUMN]

    print(f"Dataset shape  : {df.shape}")
    print(f"Feature columns: {feature_cols}")
    print(f"Target column  : {TARGET_COLUMN} | Classes: {sorted(y.unique())}")

    mlflow.log_param("n_features", len(feature_cols))
    mlflow.log_param("n_samples",  len(df))

    # ── Train / test split ────────────────────────────────────────────────────
    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )
    print(f"Train: {len(X_train)} | Test: {len(X_test)}")

    # ── Train model ───────────────────────────────────────────────────────────
    print(f"\nTraining LogisticRegression (C={1/args.reg_rate:.4f})...")
    model = LogisticRegression(
        C=1 / args.reg_rate,
        solver="lbfgs",
        max_iter=1000,
        random_state=42,
    )
    model.fit(X_train, y_train)

    # ── Evaluate ──────────────────────────────────────────────────────────────
    y_pred = model.predict(X_test)
    y_prob = model.predict_proba(X_test)[:, 1]

    accuracy = accuracy_score(y_test, y_pred)
    auc      = roc_auc_score(y_test, y_prob)

    print(f"\nAccuracy : {accuracy:.4f}")
    print(f"AUC      : {auc:.4f}")
    print(f"\n{classification_report(y_test, y_pred)}")

    # ── Log metrics ───────────────────────────────────────────────────────────
    mlflow.log_metric("accuracy", accuracy)
    mlflow.log_metric("auc",      auc)

    # ── Save ROC curve as artifact ────────────────────────────────────────────
    fig, ax = plt.subplots(figsize=(6, 4))
    RocCurveDisplay.from_predictions(y_test, y_prob, ax=ax, name="LogReg")
    ax.set_title(f"ROC Curve  |  AUC = {auc:.4f}")
    roc_path = os.path.join(args.output_dir, "ROC-Curve.png")
    fig.savefig(roc_path)
    plt.close(fig)
    mlflow.log_artifact(roc_path)
    print(f"ROC curve saved: {roc_path}")

    # ── Log model ─────────────────────────────────────────────────────────────
    mlflow.sklearn.log_model(
        sk_model=model,
        artifact_path="model",
        input_example=X_train.head(5),
    )
    print("Model logged to MLflow")

    mlflow.end_run()
    print("\n✅ Training complete")


if __name__ == "__main__":
    main()
