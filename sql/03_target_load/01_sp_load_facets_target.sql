/*==============================================================================
  STEP 03 : SP_LOAD_FACETS_TARGET  - the "core job" that loads keyword files
  ----------------------------------------------------------------------------
  In the real project a Facets batch job reads the keyword file and loads
  Facets. Here this procedure plays that role:

  For every entity in AUDIT.MIG_ENTITY_CONFIG (in LOAD_SEQ order: groups before
  subscribers before members ... before claim lines):
    1. reads @AUDIT.KEYWORD_STAGE/<BATCH_ID>/KW_<ENTITY>.txt into
       AUDIT.KEYWORD_LANDING (one row per line)
    2. validates the file:  exactly one HDR record for the right entity,
                            TRL record count = number of DTL records
    3. creates the FACETS_TGT table if needed (same structure as FACETS_STG)
    4. in ONE TRANSACTION: deletes this batch from the target and inserts
       the DTL records, splitting each line on '|'
    5. logs the result to AUDIT.KEYWORD_LOAD_LOG and AUDIT.MIG_LOAD_LOG
  A failure on one entity is logged and the next entity continues.

  Usage:
      CALL AUDIT.SP_LOAD_FACETS_TARGET('BATCH_001');
==============================================================================*/

USE ROLE MIG_DEVELOPER;
USE WAREHOUSE MIG_WH;
USE DATABASE HC_MIGRATION_DB;
USE SCHEMA AUDIT;

CREATE OR REPLACE PROCEDURE AUDIT.SP_LOAD_FACETS_TARGET(P_BATCH_ID VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_entity       VARCHAR;
    v_stg          VARCHAR;
    v_tgt          VARCHAR;
    v_tgt_fqn      VARCHAR;
    v_file         VARCHAR;
    v_sql          VARCHAR;
    v_cols         VARCHAR;
    v_exprs        VARCHAR;
    v_hdr_count    INTEGER;
    v_hdr_entity   VARCHAR;
    v_dtl_count    INTEGER;
    v_trl_count    INTEGER;
    v_loaded       INTEGER;
    v_header_ok    BOOLEAN;
    v_status       VARCHAR;
    v_msg          VARCHAR;
    v_errors       INTEGER DEFAULT 0;
    v_summary      VARCHAR DEFAULT '';
    c_entities CURSOR FOR
        SELECT ENTITY_NAME, STG_TABLE, TGT_TABLE
        FROM HC_MIGRATION_DB.AUDIT.MIG_ENTITY_CONFIG
        WHERE IS_ACTIVE
        ORDER BY LOAD_SEQ;
BEGIN
    FOR e IN c_entities DO
        v_entity    := e.ENTITY_NAME;
        v_stg       := e.STG_TABLE;
        v_tgt       := e.TGT_TABLE;
        v_tgt_fqn   := 'HC_MIGRATION_DB.FACETS_TGT.' || v_tgt;
        v_file      := 'KW_' || v_entity || '.txt';
        v_loaded    := 0;
        v_dtl_count := 0;
        v_trl_count := NULL;
        v_header_ok := FALSE;

        BEGIN
            ------------------------------------------------------------------
            -- 1. land the keyword file, one row per line
            ------------------------------------------------------------------
            DELETE FROM HC_MIGRATION_DB.AUDIT.KEYWORD_LANDING
             WHERE BATCH_ID = :P_BATCH_ID AND ENTITY_NAME = :v_entity;

            v_sql := 'COPY INTO HC_MIGRATION_DB.AUDIT.KEYWORD_LANDING (BATCH_ID, ENTITY_NAME, FILE_NAME, LINE_NO, LINE_TEXT)' ||
                     ' FROM (SELECT ''' || P_BATCH_ID || ''', ''' || v_entity || ''',' ||
                     '              METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, $1' ||
                     '         FROM @HC_MIGRATION_DB.AUDIT.KEYWORD_STAGE/' || P_BATCH_ID || '/)' ||
                     ' FILES = (''' || v_file || ''')' ||
                     ' FILE_FORMAT = (FORMAT_NAME = ''HC_MIGRATION_DB.AUDIT.FF_KEYWORD'')' ||
                     ' ON_ERROR = ''ABORT_STATEMENT'' FORCE = TRUE';
            EXECUTE IMMEDIATE :v_sql;

            ------------------------------------------------------------------
            -- 2. validate header / trailer
            ------------------------------------------------------------------
            SELECT COUNT_IF(SPLIT_PART(LINE_TEXT, '|', 1) = 'HDR'),
                   MAX(IFF(SPLIT_PART(LINE_TEXT, '|', 1) = 'HDR', SPLIT_PART(LINE_TEXT, '|', 2), NULL)),
                   COUNT_IF(SPLIT_PART(LINE_TEXT, '|', 1) = 'DTL'),
                   MAX(IFF(SPLIT_PART(LINE_TEXT, '|', 1) = 'TRL', TRY_TO_NUMBER(SPLIT_PART(LINE_TEXT, '|', 3)), NULL))
              INTO :v_hdr_count, :v_hdr_entity, :v_dtl_count, :v_trl_count
              FROM HC_MIGRATION_DB.AUDIT.KEYWORD_LANDING
             WHERE BATCH_ID = :P_BATCH_ID AND ENTITY_NAME = :v_entity;

            v_header_ok := COALESCE(v_hdr_count = 1 AND v_hdr_entity = v_entity, FALSE);

            IF (NOT v_header_ok) THEN
                v_status := 'ERROR';
                v_msg    := 'Invalid header record (found ' || v_hdr_count || ' HDR for entity ' || COALESCE(v_hdr_entity, 'NULL') || ')';
            ELSEIF (v_trl_count IS NULL OR v_trl_count <> v_dtl_count) THEN
                v_status := 'ERROR';
                v_msg    := 'Trailer count ' || COALESCE(TO_VARCHAR(v_trl_count), 'missing') ||
                            ' does not match detail count ' || v_dtl_count;
            ELSE
                --------------------------------------------------------------
                -- 3. target table = same structure as the validated stage table
                --------------------------------------------------------------
                v_sql := 'CREATE TABLE IF NOT EXISTS ' || v_tgt_fqn ||
                         ' LIKE HC_MIGRATION_DB.FACETS_STG.' || v_stg;
                EXECUTE IMMEDIATE :v_sql;

                -- column list + "split the line" expressions, in column order
                -- (DTL|col1|col2|...  -> array index 1 = column 1)
                SELECT LISTAGG(COLUMN_NAME, ', ') WITHIN GROUP (ORDER BY ORDINAL_POSITION),
                       LISTAGG('NULLIF(SPLIT(LINE_TEXT, ''|'')[' || ORDINAL_POSITION || ']::VARCHAR, '''')', ', ')
                           WITHIN GROUP (ORDER BY ORDINAL_POSITION)
                  INTO :v_cols, :v_exprs
                  FROM HC_MIGRATION_DB.INFORMATION_SCHEMA.COLUMNS
                 WHERE TABLE_SCHEMA = 'FACETS_TGT' AND TABLE_NAME = :v_tgt;

                --------------------------------------------------------------
                -- 4. delete + insert as one unit of work
                --------------------------------------------------------------
                BEGIN TRANSACTION;

                DELETE FROM IDENTIFIER(:v_tgt_fqn) WHERE MIG_BATCH_ID = :P_BATCH_ID;

                v_sql := 'INSERT INTO ' || v_tgt_fqn || ' (' || v_cols || ')' ||
                         ' SELECT ' || v_exprs ||
                         ' FROM HC_MIGRATION_DB.AUDIT.KEYWORD_LANDING' ||
                         ' WHERE BATCH_ID = ''' || P_BATCH_ID || '''' ||
                         '   AND ENTITY_NAME = ''' || v_entity || '''' ||
                         '   AND SPLIT_PART(LINE_TEXT, ''|'', 1) = ''DTL''' ||
                         ' ORDER BY LINE_NO';
                EXECUTE IMMEDIATE :v_sql;

                COMMIT;

                SELECT COUNT(*) INTO :v_loaded FROM IDENTIFIER(:v_tgt_fqn) WHERE MIG_BATCH_ID = :P_BATCH_ID;

                IF (v_loaded = v_dtl_count) THEN
                    v_status := 'SUCCESS';
                    v_msg    := 'Loaded ' || v_loaded || ' records into FACETS_TGT.' || v_tgt;
                ELSE
                    v_status := 'ERROR';
                    v_msg    := 'Loaded ' || v_loaded || ' but file had ' || v_dtl_count || ' detail records';
                END IF;
            END IF;
        EXCEPTION
            WHEN OTHER THEN
                ROLLBACK;
                v_status := 'ERROR';
                v_msg    := 'Keyword load failed for ' || v_file || ': ' || SQLERRM;
        END;

        IF (v_status = 'ERROR') THEN
            v_errors := v_errors + 1;
        END IF;

        INSERT INTO HC_MIGRATION_DB.AUDIT.KEYWORD_LOAD_LOG
            (BATCH_ID, ENTITY_NAME, FILE_NAME, HEADER_OK, DETAIL_COUNT, TRAILER_COUNT, LOADED_COUNT, STATUS, MESSAGE)
        VALUES (:P_BATCH_ID, :v_entity, :v_file, :v_header_ok, :v_dtl_count, :v_trl_count, :v_loaded, :v_status, :v_msg);

        INSERT INTO HC_MIGRATION_DB.AUDIT.MIG_LOAD_LOG (BATCH_ID, STEP_NAME, OBJECT_NAME, ROW_COUNT, STATUS, MESSAGE)
        VALUES (:P_BATCH_ID, 'LOAD_FACETS_TARGET', :v_tgt, :v_loaded, :v_status, :v_msg);

        v_summary := v_summary || v_entity || '=' || v_loaded || ' (' || v_status || ') ';
    END FOR;

    IF (v_errors > 0) THEN
        RETURN 'LOAD_FACETS_TARGET finished with ' || v_errors || ' error(s): ' || v_summary;
    END IF;
    RETURN 'LOAD_FACETS_TARGET complete: ' || v_summary;
END;
$$;

-- Quick test (after dbt build has produced the keyword files):
-- LIST @AUDIT.KEYWORD_STAGE/BATCH_001/;
-- CALL AUDIT.SP_LOAD_FACETS_TARGET('BATCH_001');
-- SELECT * FROM AUDIT.KEYWORD_LOAD_LOG ORDER BY LOADED_AT DESC;
