/*==============================================================================
  STEP 00-03 : CONTROL (CONFIG) + AUDIT (LOGGING) TABLES
  ----------------------------------------------------------------------------
  The stored procedures are metadata driven: which files to load and which
  entities to reconcile come from config tables, not hard-coded logic.
  Adding a new source file = add a row, not change code.
==============================================================================*/

USE ROLE MIG_DEVELOPER;
USE WAREHOUSE MIG_WH;
USE DATABASE HC_MIGRATION_DB;
USE SCHEMA AUDIT;

-------------------------------------------------------------------------------
-- CONFIG: which source file loads into which RAW table
-------------------------------------------------------------------------------
CREATE OR REPLACE TABLE AUDIT.MIG_SOURCE_FILE_CONFIG (
    LOAD_SEQ     NUMBER(3)     NOT NULL,
    RAW_TABLE    VARCHAR(100)  NOT NULL,
    FILE_NAME    VARCHAR(200)  NOT NULL,
    DESCRIPTION  VARCHAR(500),
    IS_ACTIVE    BOOLEAN       DEFAULT TRUE
);

INSERT INTO AUDIT.MIG_SOURCE_FILE_CONFIG (LOAD_SEQ, RAW_TABLE, FILE_NAME, DESCRIPTION) VALUES
    (1, 'SRC_GROUP',        'SRC_GROUP.txt',        'Employer groups'),
    (2, 'SRC_MEMBER',       'SRC_MEMBER.txt',       'Subscribers, dependents and coverage'),
    (3, 'SRC_PROVIDER',     'SRC_PROVIDER.txt',     'Practitioners and facilities'),
    (4, 'SRC_CLAIM_HEADER', 'SRC_CLAIM_HEADER.txt', 'Medical claim headers'),
    (5, 'SRC_CLAIM_LINE',   'SRC_CLAIM_LINE.txt',   'Medical claim service lines');

-------------------------------------------------------------------------------
-- CONFIG: migration entities (drives keyword load + reconciliation scorecard)
--   RAW_FILTER  = which raw rows belong to this entity (used for source count)
--   STG_TABLE   = dbt-built Facets-like table in FACETS_STG
--   TGT_TABLE   = final table in FACETS_TGT
-------------------------------------------------------------------------------
CREATE OR REPLACE TABLE AUDIT.MIG_ENTITY_CONFIG (
    ENTITY_NAME  VARCHAR(50)   NOT NULL,
    LOAD_SEQ     NUMBER(3)     NOT NULL,
    RAW_TABLE    VARCHAR(100)  NOT NULL,
    RAW_FILTER   VARCHAR(500)  DEFAULT '1 = 1',
    STG_TABLE    VARCHAR(100)  NOT NULL,
    TGT_TABLE    VARCHAR(100)  NOT NULL,
    IS_ACTIVE    BOOLEAN       DEFAULT TRUE
);

INSERT INTO AUDIT.MIG_ENTITY_CONFIG (ENTITY_NAME, LOAD_SEQ, RAW_TABLE, RAW_FILTER, STG_TABLE, TGT_TABLE) VALUES
    ('GROUP',       1, 'SRC_GROUP',        '1 = 1',                          'CMC_GRGR_GROUP',     'CMC_GRGR_GROUP'),
    ('SUBSCRIBER',  2, 'SRC_MEMBER',       'TRIM(RELATIONSHIP_CODE) = ''18''', 'CMC_SBSB_SUBSC',     'CMC_SBSB_SUBSC'),
    ('MEMBER',      3, 'SRC_MEMBER',       '1 = 1',                          'CMC_MEME_MEMBER',    'CMC_MEME_MEMBER'),
    ('ELIGIBILITY', 4, 'SRC_MEMBER',       '1 = 1',                          'CMC_MEPE_PRCS_ELIG', 'CMC_MEPE_PRCS_ELIG'),
    ('PROVIDER',    5, 'SRC_PROVIDER',     '1 = 1',                          'CMC_PRPR_PROV',      'CMC_PRPR_PROV'),
    ('CLAIM',       6, 'SRC_CLAIM_HEADER', '1 = 1',                          'CMC_CLCL_CLAIM',     'CMC_CLCL_CLAIM'),
    ('CLAIM_LINE',  7, 'SRC_CLAIM_LINE',   '1 = 1',                          'CMC_CDML_CL_LINE',   'CMC_CDML_CL_LINE');

-------------------------------------------------------------------------------
-- CONTROL: batches (the "current" batch is what Tasks will process)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS AUDIT.MIG_BATCH_CONTROL (
    BATCH_ID     VARCHAR(50)   NOT NULL,
    BATCH_DESC   VARCHAR(500),
    IS_CURRENT   BOOLEAN       DEFAULT FALSE,
    STATUS       VARCHAR(30)   DEFAULT 'CREATED',   -- CREATED / RUNNING / PASSED / PASSED_WITH_WARNINGS / FAILED
    CREATED_AT   TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    STARTED_AT   TIMESTAMP_NTZ,
    ENDED_AT     TIMESTAMP_NTZ
);

MERGE INTO AUDIT.MIG_BATCH_CONTROL t
USING (SELECT 'BATCH_001' AS BATCH_ID, 'Initial conversion - mock batch 1' AS BATCH_DESC) s
   ON t.BATCH_ID = s.BATCH_ID
WHEN NOT MATCHED THEN INSERT (BATCH_ID, BATCH_DESC, IS_CURRENT) VALUES (s.BATCH_ID, s.BATCH_DESC, TRUE);

-------------------------------------------------------------------------------
-- AUDIT: generic step log written by every stored procedure
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS AUDIT.MIG_LOAD_LOG (
    LOG_ID       NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    BATCH_ID     VARCHAR(50),
    STEP_NAME    VARCHAR(100),
    OBJECT_NAME  VARCHAR(200),
    ROW_COUNT    NUMBER,
    STATUS       VARCHAR(20),          -- SUCCESS / WARNING / ERROR
    MESSAGE      VARCHAR(4000),
    LOGGED_BY    VARCHAR(200) DEFAULT CURRENT_USER(),
    LOGGED_AT    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-------------------------------------------------------------------------------
-- AUDIT: data profiling results (one row per table/column per batch)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS AUDIT.DQ_PROFILE_RESULTS (
    BATCH_ID                     VARCHAR(50),
    TABLE_NAME                   VARCHAR(100),
    COLUMN_NAME                  VARCHAR(100),
    COLUMN_POSITION              NUMBER,
    TOTAL_ROWS                   NUMBER,
    NULL_COUNT                   NUMBER,
    NULL_PCT                     NUMBER(6,2),
    BLANK_COUNT                  NUMBER,
    DISTINCT_COUNT               NUMBER,
    MIN_LENGTH                   NUMBER,
    MAX_LENGTH                   NUMBER,
    MIN_VALUE                    VARCHAR(1000),
    MAX_VALUE                    VARCHAR(1000),
    NUMERIC_VALUE_COUNT          NUMBER,
    MIN_NUMERIC                  NUMBER(38,4),
    MAX_NUMERIC                  NUMBER(38,4),
    DATE_VALUE_COUNT             NUMBER,
    MIN_DATE                     DATE,
    MAX_DATE                     DATE,
    INVALID_CHAR_COUNT           NUMBER,
    SAMPLE_INVALID_VALUE         VARCHAR(1000),
    LEADING_TRAILING_SPACE_COUNT NUMBER,
    PROFILED_AT                  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-------------------------------------------------------------------------------
-- AUDIT: keyword file landing + load log (the "core job" in this project)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS AUDIT.KEYWORD_LANDING (
    BATCH_ID     VARCHAR(50),
    ENTITY_NAME  VARCHAR(50),
    FILE_NAME    VARCHAR(500),
    LINE_NO      NUMBER,
    LINE_TEXT    VARCHAR,
    LOADED_AT    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS AUDIT.KEYWORD_LOAD_LOG (
    BATCH_ID       VARCHAR(50),
    ENTITY_NAME    VARCHAR(50),
    FILE_NAME      VARCHAR(500),
    HEADER_OK      BOOLEAN,
    DETAIL_COUNT   NUMBER,
    TRAILER_COUNT  NUMBER,
    LOADED_COUNT   NUMBER,
    STATUS         VARCHAR(20),
    MESSAGE        VARCHAR(4000),
    LOADED_AT      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-------------------------------------------------------------------------------
-- AUDIT: dbt test results (written by the dbt on-run-end hook)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS AUDIT.DBT_TEST_RESULTS (
    BATCH_ID        VARCHAR(50),
    INVOCATION_ID   VARCHAR(100),
    TEST_NAME       VARCHAR(500),
    TEST_UNIQUE_ID  VARCHAR(1000),
    TESTED_OBJECT   VARCHAR(200),
    SEVERITY        VARCHAR(20),
    STATUS          VARCHAR(20),     -- pass / warn / fail / error
    FAILURES        NUMBER,
    MESSAGE         VARCHAR(4000),
    RUN_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-------------------------------------------------------------------------------
-- AUDIT: scorecard + error log (final output of every batch)
-------------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS AUDIT.MIGRATION_SCORECARD (
    BATCH_ID               VARCHAR(50),
    ENTITY_NAME            VARCHAR(50),
    LOAD_SEQ               NUMBER,
    SOURCE_COUNT           NUMBER,
    REJECT_COUNT           NUMBER,
    STAGED_COUNT           NUMBER,
    KEYWORD_DETAIL_COUNT   NUMBER,
    KEYWORD_TRAILER_COUNT  NUMBER,
    TARGET_COUNT           NUMBER,
    SOURCE_RECON_STATUS    VARCHAR(30),   -- BALANCED when source = staged + rejected
    TARGET_RECON_STATUS    VARCHAR(30),   -- MATCH when staged = keyword = target
    TEST_WARNING_COUNT     NUMBER,
    TEST_FAILURE_COUNT     NUMBER,
    OVERALL_STATUS         VARCHAR(30),   -- PASSED / PASSED_WITH_WARNINGS / FAILED
    CREATED_AT             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE TABLE IF NOT EXISTS AUDIT.MIGRATION_ERROR_LOG (
    BATCH_ID        VARCHAR(50),
    ENTITY_NAME     VARCHAR(100),
    SEVERITY        VARCHAR(20),       -- ERROR / WARNING / INFO
    ERROR_CATEGORY  VARCHAR(50),       -- TRANSFORM_REJECT / DBT_TEST / RECONCILIATION / SOURCE_PROFILING / KEYWORD_LOAD
    ERROR_CODE      VARCHAR(200),
    ERROR_DETAIL    VARCHAR(4000),
    RECORD_COUNT    NUMBER,
    SAMPLE_KEYS     VARCHAR(4000),
    LOGGED_AT       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

SHOW TABLES IN SCHEMA AUDIT;
