/*==============================================================================
  STEP 01-01 : RAW (LANDING) TABLES
  ----------------------------------------------------------------------------
  Same idea as the "temp tables" in SQL Server: one table per source extract,
  columns in the same order as the file, ALL VARCHAR so nothing is lost or
  rejected on load. Typing and cleansing happen later (dbt staging layer),
  after profiling has told us what the data really looks like.

  Every raw row also carries lineage columns:
      BATCH_ID, SRC_FILE_NAME, SRC_ROW_NUM, LOAD_TS
  (These four must stay the LAST columns - SP_LOAD_RAW relies on it.)
==============================================================================*/

USE ROLE MIG_DEVELOPER;
USE WAREHOUSE MIG_WH;
USE DATABASE HC_MIGRATION_DB;
USE SCHEMA RAW;

CREATE TRANSIENT TABLE IF NOT EXISTS RAW.SRC_GROUP (
    GROUP_NUMBER      VARCHAR,
    GROUP_NAME        VARCHAR,
    LOB_CODE          VARCHAR,
    GROUP_STATUS      VARCHAR,
    GROUP_EFF_DATE    VARCHAR,
    GROUP_TERM_DATE   VARCHAR,
    ADDRESS_LINE1     VARCHAR,
    CITY              VARCHAR,
    STATE             VARCHAR,
    ZIP_CODE          VARCHAR,
    PHONE             VARCHAR,
    BATCH_ID          VARCHAR(50),
    SRC_FILE_NAME     VARCHAR(500),
    SRC_ROW_NUM       NUMBER,
    LOAD_TS           TIMESTAMP_NTZ
);

CREATE TRANSIENT TABLE IF NOT EXISTS RAW.SRC_MEMBER (
    MEMBER_ID           VARCHAR,
    SUBSCRIBER_ID       VARCHAR,
    RELATIONSHIP_CODE   VARCHAR,
    FIRST_NAME          VARCHAR,
    LAST_NAME           VARCHAR,
    MIDDLE_INITIAL      VARCHAR,
    DATE_OF_BIRTH       VARCHAR,
    GENDER_CODE         VARCHAR,
    SSN                 VARCHAR,
    ADDRESS_LINE1       VARCHAR,
    CITY                VARCHAR,
    STATE               VARCHAR,
    ZIP_CODE            VARCHAR,
    PHONE               VARCHAR,
    GROUP_NUMBER        VARCHAR,
    PLAN_CODE           VARCHAR,
    COVERAGE_EFF_DATE   VARCHAR,
    COVERAGE_TERM_DATE  VARCHAR,
    BATCH_ID            VARCHAR(50),
    SRC_FILE_NAME       VARCHAR(500),
    SRC_ROW_NUM         NUMBER,
    LOAD_TS             TIMESTAMP_NTZ
);

CREATE TRANSIENT TABLE IF NOT EXISTS RAW.SRC_PROVIDER (
    PROVIDER_ID         VARCHAR,
    NPI                 VARCHAR,
    PROVIDER_TYPE       VARCHAR,
    FIRST_NAME          VARCHAR,
    LAST_NAME           VARCHAR,
    ORGANIZATION_NAME   VARCHAR,
    SPECIALTY_CODE      VARCHAR,
    TAX_ID              VARCHAR,
    ADDRESS_LINE1       VARCHAR,
    CITY                VARCHAR,
    STATE               VARCHAR,
    ZIP_CODE            VARCHAR,
    NETWORK_STATUS      VARCHAR,
    PROVIDER_EFF_DATE   VARCHAR,
    BATCH_ID            VARCHAR(50),
    SRC_FILE_NAME       VARCHAR(500),
    SRC_ROW_NUM         NUMBER,
    LOAD_TS             TIMESTAMP_NTZ
);

CREATE TRANSIENT TABLE IF NOT EXISTS RAW.SRC_CLAIM_HEADER (
    CLAIM_ID              VARCHAR,
    MEMBER_ID             VARCHAR,
    PROVIDER_ID           VARCHAR,
    CLAIM_TYPE            VARCHAR,
    CLAIM_STATUS          VARCHAR,
    RECEIVED_DATE         VARCHAR,
    SERVICE_FROM_DATE     VARCHAR,
    SERVICE_TO_DATE       VARCHAR,
    TOTAL_CHARGE_AMT      VARCHAR,
    TOTAL_PAID_AMT        VARCHAR,
    PRIMARY_DIAG_CODE     VARCHAR,
    SECONDARY_DIAG_CODE   VARCHAR,
    BATCH_ID              VARCHAR(50),
    SRC_FILE_NAME         VARCHAR(500),
    SRC_ROW_NUM           NUMBER,
    LOAD_TS               TIMESTAMP_NTZ
);

CREATE TRANSIENT TABLE IF NOT EXISTS RAW.SRC_CLAIM_LINE (
    CLAIM_ID              VARCHAR,
    LINE_NUMBER           VARCHAR,
    PROCEDURE_CODE        VARCHAR,
    PROCEDURE_MODIFIER    VARCHAR,
    SERVICE_DATE          VARCHAR,
    UNITS                 VARCHAR,
    CHARGE_AMT            VARCHAR,
    ALLOWED_AMT           VARCHAR,
    PAID_AMT              VARCHAR,
    LINE_STATUS           VARCHAR,
    BATCH_ID              VARCHAR(50),
    SRC_FILE_NAME         VARCHAR(500),
    SRC_ROW_NUM           NUMBER,
    LOAD_TS               TIMESTAMP_NTZ
);

-- PHI in the landing zone is masked for QA / analysts too
ALTER TABLE RAW.SRC_MEMBER MODIFY COLUMN SSN           SET MASKING POLICY GOVERNANCE.MP_MASK_STRING FORCE;
ALTER TABLE RAW.SRC_MEMBER MODIFY COLUMN DATE_OF_BIRTH SET MASKING POLICY GOVERNANCE.MP_MASK_STRING FORCE;

SHOW TABLES IN SCHEMA RAW;
