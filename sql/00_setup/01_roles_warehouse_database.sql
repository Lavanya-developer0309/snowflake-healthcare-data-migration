/*==============================================================================
  STEP 00-01 : ROLES, WAREHOUSE, DATABASE, SCHEMAS, GRANTS
  ----------------------------------------------------------------------------
  Run this ONCE in a Snowsight worksheet as ACCOUNTADMIN (trial accounts give
  you ACCOUNTADMIN by default).

  Role design (RBAC):
      ACCOUNTADMIN
          └── SYSADMIN
                 └── MIG_DEVELOPER   owns the database, runs dbt + procedures
                        └── MIG_QA        reads every schema (masked PHI)
                               └── MIG_ANALYST   reads FACETS_TGT + AUDIT only (masked PHI)

  Schema design (one schema per layer of the migration):
      RAW            transient, source extracts loaded "as is" (all VARCHAR)
      REF            crosswalks and config values (dbt seeds)
      STAGING        dbt views: trimmed, typed, cleansed source
      INTERMEDIATE   dbt tables: crosswalks applied, reject reasons, keys
      FACETS_STG     dbt tables: Facets-like tables (what we validate)
      KEYWORD        dbt tables: keyword (load-file) records
      FACETS_TGT     final "Facets environment", loaded only from keyword files
      AUDIT          control tables, logs, profiling, scorecard, procedures, stages
      GOVERNANCE     masking policies
      DBT_TEST_AUDIT failing rows stored by dbt tests (store_failures)
==============================================================================*/

USE ROLE ACCOUNTADMIN;

-------------------------------------------------------------------------------
-- 1. Roles + hierarchy
-------------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS MIG_DEVELOPER COMMENT = 'Migration developer - builds and runs the pipeline';
CREATE ROLE IF NOT EXISTS MIG_QA        COMMENT = 'Migration QA - read-only on all layers, PHI masked';
CREATE ROLE IF NOT EXISTS MIG_ANALYST   COMMENT = 'Business analyst - read-only on target + audit, PHI masked';

GRANT ROLE MIG_ANALYST   TO ROLE MIG_QA;
GRANT ROLE MIG_QA        TO ROLE MIG_DEVELOPER;
GRANT ROLE MIG_DEVELOPER TO ROLE SYSADMIN;      -- best practice: custom roles roll up to SYSADMIN

-- give all three roles to the person running this script, so you can switch
-- roles in Snowsight and demo the masking policies
SET MY_USER = CURRENT_USER();
GRANT ROLE MIG_DEVELOPER TO USER IDENTIFIER($MY_USER);
GRANT ROLE MIG_QA        TO USER IDENTIFIER($MY_USER);
GRANT ROLE MIG_ANALYST   TO USER IDENTIFIER($MY_USER);

-------------------------------------------------------------------------------
-- 2. Warehouse (compute) - smallest size, suspends after 60 seconds idle
-------------------------------------------------------------------------------
CREATE WAREHOUSE IF NOT EXISTS MIG_WH
    WAREHOUSE_SIZE      = 'XSMALL'
    AUTO_SUSPEND        = 60
    AUTO_RESUME         = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT             = 'Compute for the healthcare data migration project';

-- cost guard-rail: stop the warehouse if it burns 10 credits in a month
CREATE RESOURCE MONITOR IF NOT EXISTS MIG_RM
    WITH CREDIT_QUOTA = 10
         FREQUENCY = MONTHLY
         START_TIMESTAMP = IMMEDIATELY
    TRIGGERS ON 80  PERCENT DO NOTIFY
             ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE MIG_WH SET RESOURCE_MONITOR = MIG_RM;

GRANT USAGE ON WAREHOUSE MIG_WH TO ROLE MIG_ANALYST;           -- inherited by QA + DEV
GRANT OPERATE, MONITOR ON WAREHOUSE MIG_WH TO ROLE MIG_DEVELOPER;

-- account-level privileges the developer role needs
GRANT CREATE DATABASE ON ACCOUNT TO ROLE MIG_DEVELOPER;
GRANT EXECUTE TASK    ON ACCOUNT TO ROLE MIG_DEVELOPER;        -- Snowflake Tasks (orchestration)

-------------------------------------------------------------------------------
-- 3. Database + schemas (owned by MIG_DEVELOPER)
-------------------------------------------------------------------------------
USE ROLE MIG_DEVELOPER;
USE WAREHOUSE MIG_WH;

CREATE DATABASE IF NOT EXISTS HC_MIGRATION_DB
    DATA_RETENTION_TIME_IN_DAYS = 1      -- Time Travel window (raise up to 90 on Enterprise edition)
    COMMENT = 'Healthcare payer data migration - legacy extracts to Facets-like target';

USE DATABASE HC_MIGRATION_DB;

CREATE TRANSIENT SCHEMA IF NOT EXISTS RAW
    COMMENT = 'Landing zone: source extracts as-is (transient = no fail-safe cost, data is re-loadable)';
CREATE SCHEMA IF NOT EXISTS REF            COMMENT = 'Crosswalks / config values (dbt seeds)';
CREATE SCHEMA IF NOT EXISTS STAGING        COMMENT = 'dbt staging views - cleansed and typed source';
CREATE SCHEMA IF NOT EXISTS INTERMEDIATE   COMMENT = 'dbt intermediate - crosswalks, reject reasons, contrived keys';
CREATE SCHEMA IF NOT EXISTS FACETS_STG     COMMENT = 'Facets-lookalike tables built by dbt (validated before load)';
CREATE SCHEMA IF NOT EXISTS KEYWORD        COMMENT = 'Keyword (load file) records built by dbt';
CREATE SCHEMA IF NOT EXISTS FACETS_TGT     COMMENT = 'Target Facets-like environment - loaded only from keyword files';
CREATE SCHEMA IF NOT EXISTS AUDIT          COMMENT = 'Control, logging, profiling, scorecard, procedures, stages';
CREATE SCHEMA IF NOT EXISTS GOVERNANCE     COMMENT = 'Masking policies for PHI / PII';
CREATE SCHEMA IF NOT EXISTS DBT_TEST_AUDIT COMMENT = 'Failing rows captured by dbt tests (store_failures)';

-------------------------------------------------------------------------------
-- 4. Read access for QA and ANALYST (future grants cover tables dbt creates later)
-------------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

GRANT USAGE ON DATABASE HC_MIGRATION_DB TO ROLE MIG_ANALYST;

-- MIG_QA: every schema
GRANT USAGE ON ALL SCHEMAS IN DATABASE HC_MIGRATION_DB                TO ROLE MIG_QA;
GRANT SELECT ON ALL TABLES    IN DATABASE HC_MIGRATION_DB             TO ROLE MIG_QA;
GRANT SELECT ON ALL VIEWS     IN DATABASE HC_MIGRATION_DB             TO ROLE MIG_QA;
GRANT SELECT ON FUTURE TABLES IN DATABASE HC_MIGRATION_DB             TO ROLE MIG_QA;
GRANT SELECT ON FUTURE VIEWS  IN DATABASE HC_MIGRATION_DB             TO ROLE MIG_QA;

-- MIG_ANALYST: target + audit only
-- (schema-level future grants take precedence over database-level ones for that
--  schema; MIG_QA still gets these two schemas because it inherits MIG_ANALYST)
GRANT USAGE ON SCHEMA HC_MIGRATION_DB.FACETS_TGT                      TO ROLE MIG_ANALYST;
GRANT USAGE ON SCHEMA HC_MIGRATION_DB.AUDIT                           TO ROLE MIG_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA HC_MIGRATION_DB.FACETS_TGT    TO ROLE MIG_ANALYST;
GRANT SELECT ON FUTURE TABLES IN SCHEMA HC_MIGRATION_DB.AUDIT         TO ROLE MIG_ANALYST;
GRANT SELECT ON FUTURE VIEWS  IN SCHEMA HC_MIGRATION_DB.AUDIT         TO ROLE MIG_ANALYST;

USE ROLE MIG_DEVELOPER;
SHOW SCHEMAS IN DATABASE HC_MIGRATION_DB;
