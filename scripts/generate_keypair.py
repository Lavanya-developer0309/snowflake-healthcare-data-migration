"""
Generate an RSA key pair for Snowflake key-pair authentication (used by dbt).

Works on Windows, macOS and Linux - no OpenSSL needed. Uses the
`cryptography` package, which is installed automatically with dbt-snowflake.

Usage:
    python scripts/generate_keypair.py
    python scripts/generate_keypair.py --out C:\\Users\\me\\.ssh\\snowflake

Creates (outside the repo by default):
    rsa_key.p8   PRIVATE key  -> keep secret, point SNOWFLAKE_PRIVATE_KEY_PATH at it
    rsa_key.pub  PUBLIC key   -> goes into Snowflake (ALTER USER ... SET RSA_PUBLIC_KEY)

and prints the ALTER USER statement to paste into
sql/00_setup/05_dbt_service_user.sql.

Note: for a personal demo the private key is not passphrase-protected.
In a real company you would encrypt it (--passphrase) or keep it in a vault.
"""

import argparse
import os

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa


def main():
    default_dir = os.path.join(os.path.expanduser("~"), ".ssh", "snowflake")
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=default_dir, help=f"output folder (default {default_dir})")
    ap.add_argument("--passphrase", default=None, help="optional passphrase to encrypt the private key")
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    priv_path = os.path.join(a.out, "rsa_key.p8")
    pub_path = os.path.join(a.out, "rsa_key.pub")
    if os.path.exists(priv_path):
        raise SystemExit(f"{priv_path} already exists - delete it first if you really want a new key.")

    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    enc = (serialization.BestAvailableEncryption(a.passphrase.encode())
           if a.passphrase else serialization.NoEncryption())
    with open(priv_path, "wb") as fh:
        fh.write(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8, enc))
    pub_pem = key.public_key().public_bytes(serialization.Encoding.PEM,
                                            serialization.PublicFormat.SubjectPublicKeyInfo)
    with open(pub_path, "wb") as fh:
        fh.write(pub_pem)

    body = "".join(l for l in pub_pem.decode().splitlines() if "PUBLIC KEY" not in l)
    print(f"Private key : {priv_path}")
    print(f"Public key  : {pub_path}\n")
    print("Set this environment variable before running dbt:")
    print(f"  SNOWFLAKE_PRIVATE_KEY_PATH = {priv_path}\n")
    print("Paste this into sql/00_setup/05_dbt_service_user.sql (replace the placeholder):\n")
    print(f"ALTER USER MIG_DBT_SVC SET RSA_PUBLIC_KEY = '{body}';")


if __name__ == "__main__":
    main()
