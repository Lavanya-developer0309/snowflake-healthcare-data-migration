/*==============================================================================
  STEP 04 : SP_BUILD_SCORECARD  - source vs target reconciliation + warnings
  ----------------------------------------------------------------------------
  For every entity it compares the counts at each hop of the pipeline:

     SOURCE (RAW)  ->  REJECTED in transformation
                   ->  STAGED  (FACETS_STG, passed dbt validation)
                   ->  KEYWORD (detail + trailer counts in the load file)
                   ->  TARGET  (FACETS_TGT)

     SOURCE_RECON_STATUS = BALANCED     when SOURCE = STAGED + REJECTED
     TARGET_RECON_STATUS = MATCH        when STAGED = KEYWORD = TARGET
     OVERALL_STATUS      = PASSED | PASSED_WITH_WARNINGS | FAILED

  Everything worth a look goes to AUDIT.MIGRATION_ERROR_LOG:
     TRANSFORM_REJECT  - rejected records grouped by reject reason (+ sample keys)
     DBT_TEST          - dbt tests that warned / failed in the latest run
     RECONCILIATION    - out-of-balance / mismatched counts
     KEYWORD_LOAD      - keyword file problems
     SOURCE_PROFILING  - observations from the profiling step

  Usage:
      CALL AUDIT.SP_BUILD_SCORECARD('BATCH_001');
      SELECT * FROM AUDIT.V_SCORECARD WHERE BATCH_ID = 'BATCH_001';
==============================================================================*/

USE ROLE MIG_DEVELOPER;
USE WAREHOUSE MIG_WH;
USE DATABASE HC_MIGRATION_DB;
USE SCHEMA AUDIT;

CREATE OR REPLACE PROCEDURE AUDIT.SP_BUILD_SCORECARD(P_BATCH_ID VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_entity        VARCHAR;
    v_seq           INTEGER;
    v_raw_table     VARCHAR;
    v_raw_filter    VARCHAR;
    v_stg           VARCHAR;
    v_tgt           VARCHAR;
    v_stg_fqn       VARCHAR;
    v_tgt_fqn       VARCHAR;
    v_sql           VARCHAR;
    v_src           INTEGER;
    v_rej           INTEGER;
    v_staged        INTEGER;
    v_kw_dtl        INTEGER;
    v_kw_trl        INTEGER;
    v_target        INTEGER;
    v_tgt_exists    INTEGER;
    v_test_warn     INTEGER;
    v_test_fail     INTEGER;
    v_src_status    VARCHAR;
    v_tgt_status    VARCHAR;
    v_overall       VARCHAR;
    v_invocation    VARCHAR;
    v_n_pass        INTEGER DEFAULT 0;
    v_n_warn        INTEGER DEFAULT 0;
    v_n_fail        INTEGER DEFAULT 0;
    v_batch_status  VARCHAR;
    c_entities CURSOR FOR
        SELECT ENTITY_NAME, LOAD_SEQ, RAW_TABLE, RAW_FILTER, STG_TABLE, TGT_TABLE
        FROM HC_MIGRATION_DB.AUDIT.MIG_ENTITY_CONFIG
        WHERE IS_ACTIVE
        ORDER BY LOAD_SEQ;
BEGIN
    -- re-runnable
    DELETE FROM HC_MIGRATION_DB.AUDIT.MIGRATION_SCORECARD WHERE BATCH_ID = :P_BATCH_ID;
    DELETE FROM HC_MIGRATION_DB.AUDIT.MIGRATION_ERROR_LOG WHERE BATCH_ID = :P_BATCH_ID;

    -- latest dbt invocation for this batch
    SELECT MAX_BY(INVOCATION_ID, RUN_AT) INTO :v_invocation
      FROM HC_MIGRATION_DB.AUDIT.DBT_TEST_RESULTS
     WHERE BATCH_ID = :P_BATCH_ID;

    FOR e IN c_entities DO
        v_entity     := e.ENTITY_NAME;
        v_seq        := e.LOAD_SEQ;
        v_raw_table  := e.RAW_TABLE;
        v_raw_filter := e.RAW_FILTER;
        v_stg        := e.STG_TABLE;
        v_tgt        := e.TGT_TABLE;
        v_stg_fqn    := 'HC_MIGRATION_DB.FACETS_STG.' || v_stg;
        v_tgt_fqn    := 'HC_MIGRATION_DB.FACETS_TGT.' || v_tgt;

        -- SOURCE count (dynamic because of the per-entity filter)
        v_sql := 'SELECT COUNT(*) FROM HC_MIGRATION_DB.RAW.' || v_raw_table ||
                 ' WHERE BATCH_ID = ''' || P_BATCH_ID || ''' AND (' || v_raw_filter || ')';
        EXECUTE IMMEDIATE :v_sql;
        SELECT $1 INTO :v_src FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

        -- REJECTED in transformation (dbt model)
        SELECT COUNT(*) INTO :v_rej
          FROM HC_MIGRATION_DB.FACETS_STG.MIG_TRANSFORM_REJECTS
         WHERE MIG_BATCH_ID = :P_BATCH_ID AND ENTITY_NAME = :v_entity;

        -- STAGED (validated Facets-like table)
        SELECT COUNT(*) INTO :v_staged FROM IDENTIFIER(:v_stg_fqn) WHERE MIG_BATCH_ID = :P_BATCH_ID;

        -- KEYWORD file counts (latest load attempt)
        SELECT MAX_BY(DETAIL_COUNT, LOADED_AT), MAX_BY(TRAILER_COUNT, LOADED_AT)
          INTO :v_kw_dtl, :v_kw_trl
          FROM HC_MIGRATION_DB.AUDIT.KEYWORD_LOAD_LOG
         WHERE BATCH_ID = :P_BATCH_ID AND ENTITY_NAME = :v_entity;

        -- TARGET count (table exists only after a successful keyword load)
        SELECT COUNT(*) INTO :v_tgt_exists
          FROM HC_MIGRATION_DB.INFORMATION_SCHEMA.TABLES
         WHERE TABLE_SCHEMA = 'FACETS_TGT' AND TABLE_NAME = :v_tgt;
        v_target := 0;
        IF (v_tgt_exists > 0) THEN
            SELECT COUNT(*) INTO :v_target FROM IDENTIFIER(:v_tgt_fqn) WHERE MIG_BATCH_ID = :P_BATCH_ID;
        END IF;

        -- dbt test outcome for this entity's Facets-like table
        SELECT COUNT_IF(STATUS = 'warn'), COUNT_IF(STATUS IN ('fail', 'error'))
          INTO :v_test_warn, :v_test_fail
          FROM HC_MIGRATION_DB.AUDIT.DBT_TEST_RESULTS
         WHERE BATCH_ID = :P_BATCH_ID
           AND INVOCATION_ID = :v_invocation
           AND TESTED_OBJECT = :v_stg;

        -- statuses
        IF (v_src = v_staged + v_rej) THEN
            v_src_status := 'BALANCED';
        ELSE
            v_src_status := 'OUT_OF_BALANCE';
        END IF;

        IF (v_staged = v_target AND v_staged = COALESCE(v_kw_dtl, -1) AND v_kw_dtl = COALESCE(v_kw_trl, -1)) THEN
            v_tgt_status := 'MATCH';
        ELSE
            v_tgt_status := 'MISMATCH';
        END IF;

        IF (v_src_status <> 'BALANCED' OR v_tgt_status <> 'MATCH' OR v_test_fail > 0) THEN
            v_overall := 'FAILED';
            v_n_fail  := v_n_fail + 1;
        ELSEIF (v_rej > 0 OR v_test_warn > 0) THEN
            v_overall := 'PASSED_WITH_WARNINGS';
            v_n_warn  := v_n_warn + 1;
        ELSE
            v_overall := 'PASSED';
            v_n_pass  := v_n_pass + 1;
        END IF;

        INSERT INTO HC_MIGRATION_DB.AUDIT.MIGRATION_SCORECARD
            (BATCH_ID, ENTITY_NAME, LOAD_SEQ, SOURCE_COUNT, REJECT_COUNT, STAGED_COUNT,
             KEYWORD_DETAIL_COUNT, KEYWORD_TRAILER_COUNT, TARGET_COUNT,
             SOURCE_RECON_STATUS, TARGET_RECON_STATUS, TEST_WARNING_COUNT, TEST_FAILURE_COUNT, OVERALL_STATUS)
        VALUES (:P_BATCH_ID, :v_entity, :v_seq, :v_src, :v_rej, :v_staged,
                :v_kw_dtl, :v_kw_trl, :v_target,
                :v_src_status, :v_tgt_status, :v_test_warn, :v_test_fail, :v_overall);

        ----------------------------------------------------------------------
        -- error log entries for this entity
        ----------------------------------------------------------------------
        -- a) transformation rejects, grouped by reason, with up to 5 sample keys
        INSERT INTO HC_MIGRATION_DB.AUDIT.MIGRATION_ERROR_LOG
            (BATCH_ID, ENTITY_NAME, SEVERITY, ERROR_CATEGORY, ERROR_CODE, ERROR_DETAIL, RECORD_COUNT, SAMPLE_KEYS)
        SELECT :P_BATCH_ID, :v_entity, 'WARNING', 'TRANSFORM_REJECT', REJECT_REASON,
               'Records rejected during transformation - not loaded to target',
               COUNT(*),
               ARRAY_TO_STRING(ARRAY_SLICE(ARRAY_AGG(SOURCE_KEY) WITHIN GROUP (ORDER BY SOURCE_KEY), 0, 5), ', ')
          FROM HC_MIGRATION_DB.FACETS_STG.MIG_TRANSFORM_REJECTS
         WHERE MIG_BATCH_ID = :P_BATCH_ID AND ENTITY_NAME = :v_entity
         GROUP BY REJECT_REASON;

        -- b) dbt tests that warned / failed
        INSERT INTO HC_MIGRATION_DB.AUDIT.MIGRATION_ERROR_LOG
            (BATCH_ID, ENTITY_NAME, SEVERITY, ERROR_CATEGORY, ERROR_CODE, ERROR_DETAIL, RECORD_COUNT)
        SELECT :P_BATCH_ID, :v_entity, IFF(STATUS = 'warn', 'WARNING', 'ERROR'), 'DBT_TEST',
               TEST_NAME, MESSAGE, FAILURES
          FROM HC_MIGRATION_DB.AUDIT.DBT_TEST_RESULTS
         WHERE BATCH_ID = :P_BATCH_ID
           AND INVOCATION_ID = :v_invocation
           AND TESTED_OBJECT = :v_stg
           AND STATUS IN ('warn', 'fail', 'error');

        -- c) reconciliation problems
        IF (v_src_status <> 'BALANCED') THEN
            INSERT INTO HC_MIGRATION_DB.AUDIT.MIGRATION_ERROR_LOG
                (BATCH_ID, ENTITY_NAME, SEVERITY, ERROR_CATEGORY, ERROR_CODE, ERROR_DETAIL, RECORD_COUNT)
            VALUES (:P_BATCH_ID, :v_entity, 'ERROR', 'RECONCILIATION', 'SOURCE_OUT_OF_BALANCE',
                    'Source count does not equal staged + rejected',
                    ABS(:v_src - (:v_staged + :v_rej)));
        END IF;
        IF (v_tgt_status <> 'MATCH') THEN
            INSERT INTO HC_MIGRATION_DB.AUDIT.MIGRATION_ERROR_LOG
                (BATCH_ID, ENTITY_NAME, SEVERITY, ERROR_CATEGORY, ERROR_CODE, ERROR_DETAIL, RECORD_COUNT)
            VALUES (:P_BATCH_ID, :v_entity, 'ERROR', 'RECONCILIATION', 'TARGET_COUNT_MISMATCH',
                    'Staged / keyword / target counts differ - check AUDIT.KEYWORD_LOAD_LOG',
                    ABS(:v_staged - :v_target));
        END IF;
    END FOR;

    -- d) keyword load errors
    INSERT INTO HC_MIGRATION_DB.AUDIT.MIGRATION_ERROR_LOG
        (BATCH_ID, ENTITY_NAME, SEVERITY, ERROR_CATEGORY, ERROR_CODE, ERROR_DETAIL, RECORD_COUNT)
    SELECT BATCH_ID, ENTITY_NAME, 'ERROR', 'KEYWORD_LOAD', 'KEYWORD_LOAD_FAILED', MESSAGE, DETAIL_COUNT
      FROM HC_MIGRATION_DB.AUDIT.KEYWORD_LOAD_LOG
     WHERE BATCH_ID = :P_BATCH_ID AND STATUS = 'ERROR'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ENTITY_NAME ORDER BY LOADED_AT DESC) = 1;

    -- e) dbt tests on sources / other objects (e.g. source-level warn tests)
    INSERT INTO HC_MIGRATION_DB.AUDIT.MIGRATION_ERROR_LOG
        (BATCH_ID, ENTITY_NAME, SEVERITY, ERROR_CATEGORY, ERROR_CODE, ERROR_DETAIL, RECORD_COUNT)
    SELECT :P_BATCH_ID, TESTED_OBJECT, IFF(STATUS = 'warn', 'WARNING', 'ERROR'), 'DBT_TEST',
           TEST_NAME, MESSAGE, FAILURES
      FROM HC_MIGRATION_DB.AUDIT.DBT_TEST_RESULTS
     WHERE BATCH_ID = :P_BATCH_ID
       AND INVOCATION_ID = :v_invocation
       AND STATUS IN ('warn', 'fail', 'error')
       AND TESTED_OBJECT NOT IN (SELECT STG_TABLE FROM HC_MIGRATION_DB.AUDIT.MIG_ENTITY_CONFIG WHERE IS_ACTIVE);

    -- f) source profiling observations (information for the client)
    INSERT INTO HC_MIGRATION_DB.AUDIT.MIGRATION_ERROR_LOG
        (BATCH_ID, ENTITY_NAME, SEVERITY, ERROR_CATEGORY, ERROR_CODE, ERROR_DETAIL, RECORD_COUNT, SAMPLE_KEYS)
    SELECT BATCH_ID, TABLE_NAME, 'INFO', 'SOURCE_PROFILING', COLUMN_NAME, DQ_OBSERVATIONS,
           TOTAL_ROWS, SAMPLE_INVALID_VALUE
      FROM HC_MIGRATION_DB.AUDIT.V_DQ_PROFILE_REPORT
     WHERE BATCH_ID = :P_BATCH_ID AND DQ_OBSERVATIONS <> '';

    -- close the batch
    IF (v_n_fail > 0) THEN
        v_batch_status := 'FAILED';
    ELSEIF (v_n_warn > 0) THEN
        v_batch_status := 'PASSED_WITH_WARNINGS';
    ELSE
        v_batch_status := 'PASSED';
    END IF;

    UPDATE HC_MIGRATION_DB.AUDIT.MIG_BATCH_CONTROL
       SET STATUS = :v_batch_status, ENDED_AT = CURRENT_TIMESTAMP()
     WHERE BATCH_ID = :P_BATCH_ID;

    INSERT INTO HC_MIGRATION_DB.AUDIT.MIG_LOAD_LOG (BATCH_ID, STEP_NAME, OBJECT_NAME, ROW_COUNT, STATUS, MESSAGE)
    VALUES (:P_BATCH_ID, 'BUILD_SCORECARD', 'MIGRATION_SCORECARD', :v_n_pass + :v_n_warn + :v_n_fail, 'SUCCESS',
            'Batch status: ' || :v_batch_status);

    RETURN 'Scorecard built for ' || P_BATCH_ID || ': ' || v_n_pass || ' passed, ' || v_n_warn ||
           ' passed with warnings, ' || v_n_fail || ' failed. Batch status = ' || v_batch_status;
END;
$$;

-------------------------------------------------------------------------------
-- Reporting views
-------------------------------------------------------------------------------
CREATE OR REPLACE VIEW AUDIT.V_SCORECARD AS
SELECT BATCH_ID,
       ENTITY_NAME,
       SOURCE_COUNT,
       REJECT_COUNT,
       STAGED_COUNT,
       KEYWORD_DETAIL_COUNT,
       TARGET_COUNT,
       ROUND(100 * TARGET_COUNT / NULLIF(SOURCE_COUNT, 0), 2) AS LOAD_PCT,
       SOURCE_RECON_STATUS,
       TARGET_RECON_STATUS,
       TEST_WARNING_COUNT,
       TEST_FAILURE_COUNT,
       OVERALL_STATUS,
       CREATED_AT
FROM AUDIT.MIGRATION_SCORECARD;

CREATE OR REPLACE VIEW AUDIT.V_ERROR_SUMMARY AS
SELECT BATCH_ID, SEVERITY, ERROR_CATEGORY, ENTITY_NAME, ERROR_CODE,
       SUM(RECORD_COUNT) AS RECORD_COUNT,
       MAX(ERROR_DETAIL) AS ERROR_DETAIL,
       MAX(SAMPLE_KEYS)  AS SAMPLE_KEYS
FROM AUDIT.MIGRATION_ERROR_LOG
GROUP BY ALL;

-- Quick test:
-- CALL AUDIT.SP_BUILD_SCORECARD('BATCH_001');
-- SELECT * FROM AUDIT.V_SCORECARD WHERE BATCH_ID = 'BATCH_001' ORDER BY ENTITY_NAME;
-- SELECT * FROM AUDIT.V_ERROR_SUMMARY WHERE BATCH_ID = 'BATCH_001' ORDER BY SEVERITY, ERROR_CATEGORY;
