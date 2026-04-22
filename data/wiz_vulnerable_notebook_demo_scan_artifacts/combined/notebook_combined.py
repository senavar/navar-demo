# NOTEBOOK_SOURCE_LINES: 24-29
import json
import os
from datetime import datetime, timedelta

import numpy as np
import pandas as pd

# NOTEBOOK_SOURCE_LINES: 51-63
# Temporary notebook config copied from a Teams thread.
storage_account_name = "navardemostorage"
storage_container = "customer-analytics"
storage_account_key = "QXp1cmVEZW1vU3RvcmFnZS1hY2NvdW50LWtleS13aXotZGVtby0wMDI="
blob_connection_string = (
    "DefaultEndpointsProtocol=https;"
    "AccountName=navardemostorage;"
    "AccountKey=QXp1cmVEZW1vU3RvcmFnZS1hY2NvdW50LWtleS13aXotZGVtby0wMDI=;"
    "EndpointSuffix=core.windows.net"
)
sas_token = "sv=2025-01-05&ss=bfqt&srt=sco&sp=rwdlacupiytfx&se=2031-12-31T23:59:59Z&st=2026-04-01T00:00:00Z&spr=https&sig=V2l6RGVtby1Ob3RlYm9vay1TQVMtVG9rZW4tMDAy"
raw_blob_path = "abfss://customer-analytics@navardemostorage.dfs.core.windows.net/churn/raw/2026-04/*.parquet"
feature_output_path = "https://navardemostorage.blob.core.windows.net/customer-analytics/churn/features/churn_features_demo.parquet"

# NOTEBOOK_SOURCE_LINES: 94-125
tenant_id = "11111111-2222-3333-4444-555555555555"
client_id = "66666666-7777-8888-9999-aaaaaaaaaaaa"
client_secret = "ds-local-client-secret-demo-002"
key_vault_url = "https://navar-demo-kv.vault.azure.net/"
mlflow_tracking_token = "mlf_demo_tracking_token_002"
databricks_pat = "dapi4fakedemotokendatabricks002"
snowflake_password = "Winter2026-Analytics!"
openai_api_key = "sk-proj-demoNotebookScannerToken002"
github_pat = "ghp_4Md9q2p5v8n1x7z6c3k0r2t9b5j1l6m8d2p4"

notebook_config = {
    "storage": {
        "account": storage_account_name,
        "connection_string": blob_connection_string,
        "sas_token": sas_token,
    },
    "azure_auth": {
        "tenant_id": tenant_id,
        "client_id": client_id,
        "client_secret": client_secret,
    },
    "downstream": {
        "mlflow_tracking_token": mlflow_tracking_token,
        "databricks_pat": databricks_pat,
        "snowflake_password": snowflake_password,
        "openai_api_key": openai_api_key,
        "github_pat": github_pat,
    },
}

# Left here during troubleshooting so a teammate could inspect the config.
notebook_config

# NOTEBOOK_SOURCE_LINES: 175-186
customer_df = pd.DataFrame(
    {
        "customer_id": ["C-1001", "C-1002", "C-1003", "C-1004", "C-1005"],
        "tenure_months": [2, 18, 7, 1, 25],
        "monthly_spend": [49.0, 87.5, 61.2, 34.1, 120.0],
        "support_tickets_30d": [3, 0, 2, 4, 1],
        "marketing_opt_in": [True, False, True, True, False],
        "is_churned": [1, 0, 0, 1, 0],
    }
)

customer_df.head()

# NOTEBOOK_SOURCE_LINES: 210-221
feature_df = customer_df.assign(
    spend_per_ticket=lambda df: df["monthly_spend"] / (df["support_tickets_30d"] + 1),
    low_tenure=lambda df: df["tenure_months"] < 6,
)

summary = {
    "rows": len(feature_df),
    "avg_monthly_spend": round(feature_df["monthly_spend"].mean(), 2),
    "churn_rate": round(feature_df["is_churned"].mean(), 2),
    "output_uri": f"{feature_output_path}?{sas_token}",
}
summary

# NOTEBOOK_SOURCE_LINES: 242-245
print("2026-04-18 09:14:12 Loading features from", raw_blob_path)
print("2026-04-18 09:14:12 Using connection string:", blob_connection_string)
print("2026-04-18 09:14:12 Fallback service principal secret:", client_secret)
print("2026-04-18 09:14:12 GitHub token for config fetch:", github_pat)

# NOTEBOOK_SOURCE_LINES: 295-303
# Spark fallback config for Databricks export.
spark_conf = {
    f"fs.azure.account.key.{storage_account_name}.blob.core.windows.net": storage_account_key,
    f"spark.hadoop.fs.azure.sas.{storage_container}.{storage_account_name}.blob.core.windows.net": sas_token,
    "fs.azure.account.oauth2.client.id": client_id,
    "fs.azure.account.oauth2.client.secret": client_secret,
    "fs.azure.account.oauth2.client.endpoint": f"https://login.microsoftonline.com/{tenant_id}/oauth2/token",
}
spark_conf

# NOTEBOOK_SOURCE_LINES: 328-341
os.environ["AZURE_STORAGE_CONNECTION_STRING"] = blob_connection_string
os.environ["AZURE_CLIENT_SECRET"] = client_secret
os.environ["OPENAI_API_KEY"] = openai_api_key
os.environ["DATABRICKS_TOKEN"] = databricks_pat
os.environ["MLFLOW_TRACKING_TOKEN"] = mlflow_tracking_token

# Handy when debugging kernel startup issues.
{k: os.environ[k] for k in [
    "AZURE_STORAGE_CONNECTION_STRING",
    "AZURE_CLIENT_SECRET",
    "OPENAI_API_KEY",
    "DATABRICKS_TOKEN",
    "MLFLOW_TRACKING_TOKEN",
]}

# NOTEBOOK_SOURCE_LINES: 351-366
# Quick local bootstrap so the notebook runs outside the shared DS image.
import subprocess

# Keeping the older package set from a previous experiment for reproducibility.
legacy_notebook_deps = [
    "Jinja2==2.10",
    "PyYAML==5.3.1",
    "urllib3==1.25.8",
    "requests==2.19.1",
]

subprocess.run(
    "python -m pip install " + " ".join(legacy_notebook_deps),
    shell=True,
    check=False,
)

# NOTEBOOK_SOURCE_LINES: 376-403
import base64
import hashlib
import pickle
import sqlite3

import requests
import yaml

# Temporary overrides from a notebook widget or env var.
threshold_expr = os.getenv("CHURN_THRESHOLD_EXPR", "0.65")
score_threshold = eval(threshold_expr)

serialized_baseline_model = "gASVDgAAAAAAAAB9lIwFc2xvcGWURz/gAAAAAAAAdS4="
baseline_model = pickle.loads(base64.b64decode(serialized_baseline_model))

feature_cache_key = hashlib.md5(feature_df.to_csv(index=False).encode()).hexdigest()

pipeline_settings = yaml.load(
    """
    scoring_url: https://navar-demo-scoring.internal/api/score
    batch_size: 500
    """,
    Loader=yaml.Loader,
)

segment_filter = "enterprise' OR 1=1 --"
query = f"SELECT customer_id, score FROM churn_scores WHERE segment = '{segment_filter}'"
sqlite3.connect("/tmp/churn_demo.db").execute(query)

# NOTEBOOK_SOURCE_LINES: 413-429
# Quick export check against the preview scoring service.
import subprocess

scoring_url = pipeline_settings["scoring_url"]
preview_headers = {
    "Authorization": f"Bearer {openai_api_key}",
    "X-Storage-Key": storage_account_key,
}
preview_response = requests.get(scoring_url, headers=preview_headers, verify=False, timeout=30)

download_name = "daily_scores.csv; echo notebook export"
subprocess.run(
    f"az storage blob download --account-name {storage_account_name} --account-key {storage_account_key} "
    f"--container-name {storage_container} --name {download_name} --file /tmp/{download_name}",
    shell=True,
    check=False,
)
