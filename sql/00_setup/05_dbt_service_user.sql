/*==============================================================================
  STEP 00-05 : SERVICE USER FOR dbt  (key-pair authentication, no password)
  ----------------------------------------------------------------------------
  Snowflake requires MFA for humans signing in with a password. Tools such as
  dbt, GitHub Actions or schedulers should use a SERVICE user with key-pair
  authentication instead - this is also what real companies do.

  Before running:
    1. python scripts/generate_keypair.py
    2. copy the printed public key into the ALTER USER statement below
==============================================================================*/

USE ROLE ACCOUNTADMIN;

CREATE USER IF NOT EXISTS MIG_DBT_SVC
    TYPE              = SERVICE              -- no password, no MFA, cannot use the UI
    DEFAULT_ROLE      = MIG_DEVELOPER
    DEFAULT_WAREHOUSE = MIG_WH
    DEFAULT_NAMESPACE = HC_MIGRATION_DB.STAGING
    COMMENT           = 'dbt / pipeline service account for the migration project';

GRANT ROLE MIG_DEVELOPER TO USER MIG_DBT_SVC;

-- >>> replace the text between the quotes with YOUR public key (one line, no BEGIN/END lines)
ALTER USER MIG_DBT_SVC SET RSA_PUBLIC_KEY = 'PASTE_YOUR_PUBLIC_KEY_HERE';

-- check: RSA_PUBLIC_KEY_FP should now show a fingerprint
DESC USER MIG_DBT_SVC;
