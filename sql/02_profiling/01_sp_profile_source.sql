/*==============================================================================
  STEP 02 : DATA PROFILING  (null check, min/max check, invalid character check)
  ----------------------------------------------------------------------------
  SP_PROFILE_SOURCE(batch, table)  profiles every column of one RAW table
                                   using dynamic SQL (like sp_executesql)
  SP_PROFILE_ALL(batch)            profiles all source tables, then unloads
                                   the client report to @AUDIT.REPORT_STAGE
  V_DQ_PROFILE_REPORT              readable report with observations

  Checks per column:
    - total rows, NULL count / %, blank count, distinct count
    - min / max length, min / max value (text)
    - min / max numeric (TRY_TO_NUMBER) and min / max date (TRY_TO_DATE MM/DD/YYYY)
    - invalid characters  = anything outside printable ASCII (space .. ~),
      e.g. accented letters, tabs, control characters
    - leading / trailing spaces

  Usage:
      CALL AUDIT.SP_PROFILE_ALL('BATCH_001');
      SELECT * FROM AUDIT.V_DQ_PROFILE_REPORT WHERE BATCH_ID = 'BATCH_001';
==============================================================================*/

USE ROLE MIG_DEVELOPER;
USE WAREHOUSE MIG_WH;
USE DATABASE HC_MIGRATION_DB;
USE SCHEMA AUDIT;

-------------------------------------------------------------------------------
-- Profile one table
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE AUDIT.SP_PROFILE_SOURCE(P_BATCH_ID VARCHAR, P_TABLE_NAME VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_col      VARCHAR;
    v_pos      INTEGER;
    v_sql      VARCHAR;
    v_cols     INTEGER DEFAULT 0;
    v_tbl      VARCHAR;
    rs         RESULTSET;
BEGIN
    v_tbl := UPPER(P_TABLE_NAME);

    DELETE FROM HC_MIGRATION_DB.AUDIT.DQ_PROFILE_RESULTS
     WHERE BATCH_ID = :P_BATCH_ID AND TABLE_NAME = :v_tbl;

    rs := (SELECT COLUMN_NAME, ORDINAL_POSITION
             FROM HC_MIGRATION_DB.INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_SCHEMA = 'RAW'
              AND TABLE_NAME   = :v_tbl
              AND COLUMN_NAME NOT IN ('BATCH_ID', 'SRC_FILE_NAME', 'SRC_ROW_NUM', 'LOAD_TS')
            ORDER BY ORDINAL_POSITION);

    LET c_cols CURSOR FOR rs;
    FOR rec IN c_cols DO
        v_col := rec.COLUMN_NAME;
        v_pos := rec.ORDINAL_POSITION;

        v_sql := 'INSERT INTO HC_MIGRATION_DB.AUDIT.DQ_PROFILE_RESULTS (' ||
                 '  BATCH_ID, TABLE_NAME, COLUMN_NAME, COLUMN_POSITION, TOTAL_ROWS, NULL_COUNT, NULL_PCT,' ||
                 '  BLANK_COUNT, DISTINCT_COUNT, MIN_LENGTH, MAX_LENGTH, MIN_VALUE, MAX_VALUE,' ||
                 '  NUMERIC_VALUE_COUNT, MIN_NUMERIC, MAX_NUMERIC, DATE_VALUE_COUNT, MIN_DATE, MAX_DATE,' ||
                 '  INVALID_CHAR_COUNT, SAMPLE_INVALID_VALUE, LEADING_TRAILING_SPACE_COUNT)' ||
                 ' SELECT ''' || P_BATCH_ID || ''', ''' || v_tbl || ''', ''' || v_col || ''', ' || v_pos || ',' ||
                 '  COUNT(*),' ||
                 '  COUNT_IF(' || v_col || ' IS NULL),' ||
                 '  ROUND(100 * COUNT_IF(' || v_col || ' IS NULL) / NULLIF(COUNT(*), 0), 2),' ||
                 '  COUNT_IF(' || v_col || ' IS NOT NULL AND TRIM(' || v_col || ') = ''''),' ||
                 '  COUNT(DISTINCT ' || v_col || '),' ||
                 '  MIN(LENGTH(' || v_col || ')),' ||
                 '  MAX(LENGTH(' || v_col || ')),' ||
                 '  LEFT(MIN(' || v_col || '), 1000),' ||
                 '  LEFT(MAX(' || v_col || '), 1000),' ||
                 '  COUNT(TRY_TO_NUMBER(' || v_col || ', 38, 4)),' ||
                 '  MIN(TRY_TO_NUMBER(' || v_col || ', 38, 4)),' ||
                 '  MAX(TRY_TO_NUMBER(' || v_col || ', 38, 4)),' ||
                 '  COUNT(TRY_TO_DATE(' || v_col || ', ''MM/DD/YYYY'')),' ||
                 '  MIN(TRY_TO_DATE(' || v_col || ', ''MM/DD/YYYY'')),' ||
                 '  MAX(TRY_TO_DATE(' || v_col || ', ''MM/DD/YYYY'')),' ||
                 '  COUNT_IF(REGEXP_COUNT(' || v_col || ', ''[^ -~]'') > 0),' ||
                 '  LEFT(MAX(IFF(REGEXP_COUNT(' || v_col || ', ''[^ -~]'') > 0, ' || v_col || ', NULL)), 1000),' ||
                 '  COUNT_IF(' || v_col || ' <> TRIM(' || v_col || '))' ||
                 ' FROM HC_MIGRATION_DB.RAW.' || v_tbl ||
                 ' WHERE BATCH_ID = ''' || P_BATCH_ID || '''';

        EXECUTE IMMEDIATE :v_sql;
        v_cols := v_cols + 1;
    END FOR;

    INSERT INTO HC_MIGRATION_DB.AUDIT.MIG_LOAD_LOG (BATCH_ID, STEP_NAME, OBJECT_NAME, ROW_COUNT, STATUS, MESSAGE)
    VALUES (:P_BATCH_ID, 'PROFILE_SOURCE', :v_tbl, :v_cols, 'SUCCESS', 'Columns profiled');

    RETURN v_tbl || ': ' || v_cols || ' columns profiled';
END;
$$;

-------------------------------------------------------------------------------
-- Readable report: one row per column + plain-English observations
-------------------------------------------------------------------------------
CREATE OR REPLACE VIEW AUDIT.V_DQ_PROFILE_REPORT AS
SELECT
    BATCH_ID,
    TABLE_NAME,
    COLUMN_NAME,
    COLUMN_POSITION,
    TOTAL_ROWS,
    NULL_COUNT,
    NULL_PCT,
    DISTINCT_COUNT,
    MIN_LENGTH,
    MAX_LENGTH,
    MIN_VALUE,
    MAX_VALUE,
    MIN_NUMERIC,
    MAX_NUMERIC,
    MIN_DATE,
    MAX_DATE,
    INVALID_CHAR_COUNT,
    SAMPLE_INVALID_VALUE,
    LEADING_TRAILING_SPACE_COUNT,
    ARRAY_TO_STRING(ARRAY_CONSTRUCT_COMPACT(
        IFF(NULL_COUNT > 0,
            'NULL values: ' || NULL_COUNT, NULL),
        IFF(BLANK_COUNT > 0,
            'Blank (spaces only) values: ' || BLANK_COUNT, NULL),
        IFF(INVALID_CHAR_COUNT > 0,
            'Invalid / non-ASCII characters: ' || INVALID_CHAR_COUNT, NULL),
        IFF(LEADING_TRAILING_SPACE_COUNT > 0,
            'Leading/trailing spaces: ' || LEADING_TRAILING_SPACE_COUNT, NULL),
        -- column is mostly dates but some values are not valid MM/DD/YYYY dates
        IFF(DATE_VALUE_COUNT > 0.5 * (TOTAL_ROWS - NULL_COUNT) AND DATE_VALUE_COUNT < (TOTAL_ROWS - NULL_COUNT),
            'Invalid dates: ' || ((TOTAL_ROWS - NULL_COUNT) - DATE_VALUE_COUNT), NULL),
        -- column is mostly numeric but some values are not numbers
        IFF(DATE_VALUE_COUNT = 0 AND NUMERIC_VALUE_COUNT > 0.5 * (TOTAL_ROWS - NULL_COUNT)
                AND NUMERIC_VALUE_COUNT < (TOTAL_ROWS - NULL_COUNT),
            'Non-numeric values: ' || ((TOTAL_ROWS - NULL_COUNT) - NUMERIC_VALUE_COUNT), NULL),
        IFF(MIN_NUMERIC < 0,
            'Negative values present (min ' || MIN_NUMERIC || ')', NULL),
        IFF(MIN_LENGTH <> MAX_LENGTH AND DISTINCT_COUNT > 0.9 * (TOTAL_ROWS - NULL_COUNT)
                AND MAX_LENGTH <= 12 AND NUMERIC_VALUE_COUNT > 0.5 * (TOTAL_ROWS - NULL_COUNT),
            'Inconsistent length for an ID column (' || MIN_LENGTH || '-' || MAX_LENGTH || ')', NULL)
    ), '; ') AS DQ_OBSERVATIONS,
    PROFILED_AT
FROM AUDIT.DQ_PROFILE_RESULTS;

-------------------------------------------------------------------------------
-- Profile every source table + unload the report for the client
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE AUDIT.SP_PROFILE_ALL(P_BATCH_ID VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_tbl      VARCHAR;
    v_sql      VARCHAR;
    v_summary  VARCHAR DEFAULT '';
    v_issues   INTEGER DEFAULT 0;
    c_tables CURSOR FOR
        SELECT DISTINCT RAW_TABLE
        FROM HC_MIGRATION_DB.AUDIT.MIG_SOURCE_FILE_CONFIG
        WHERE IS_ACTIVE;
BEGIN
    FOR t IN c_tables DO
        v_tbl := t.RAW_TABLE;
        CALL HC_MIGRATION_DB.AUDIT.SP_PROFILE_SOURCE(:P_BATCH_ID, :v_tbl);
        v_summary := v_summary || v_tbl || ' ';
    END FOR;

    -- the "send report to client" step: unload a CSV to the report stage
    v_sql := 'COPY INTO @HC_MIGRATION_DB.AUDIT.REPORT_STAGE/' || P_BATCH_ID || '/DQ_PROFILE_REPORT.csv' ||
             ' FROM (SELECT TABLE_NAME, COLUMN_NAME, TOTAL_ROWS, NULL_COUNT, NULL_PCT, DISTINCT_COUNT,' ||
             '              MIN_LENGTH, MAX_LENGTH, MIN_VALUE, MAX_VALUE, MIN_DATE, MAX_DATE,' ||
             '              INVALID_CHAR_COUNT, LEADING_TRAILING_SPACE_COUNT, DQ_OBSERVATIONS' ||
             '         FROM HC_MIGRATION_DB.AUDIT.V_DQ_PROFILE_REPORT' ||
             '        WHERE BATCH_ID = ''' || P_BATCH_ID || '''' ||
             '        ORDER BY TABLE_NAME, COLUMN_POSITION)' ||
             ' FILE_FORMAT = (FORMAT_NAME = ''HC_MIGRATION_DB.AUDIT.FF_REPORT_CSV'')' ||
             ' HEADER = TRUE SINGLE = TRUE OVERWRITE = TRUE MAX_FILE_SIZE = 104857600';
    EXECUTE IMMEDIATE :v_sql;

    SELECT COUNT(*) INTO :v_issues
      FROM HC_MIGRATION_DB.AUDIT.V_DQ_PROFILE_REPORT
     WHERE BATCH_ID = :P_BATCH_ID AND DQ_OBSERVATIONS <> '';

    INSERT INTO HC_MIGRATION_DB.AUDIT.MIG_LOAD_LOG (BATCH_ID, STEP_NAME, OBJECT_NAME, ROW_COUNT, STATUS, MESSAGE)
    VALUES (:P_BATCH_ID, 'PROFILE_REPORT', 'DQ_PROFILE_REPORT.csv', :v_issues, 'SUCCESS',
            'Profiling report unloaded to @AUDIT.REPORT_STAGE');

    RETURN 'Profiled: ' || v_summary || '| columns with observations: ' || v_issues ||
           ' | report: @AUDIT.REPORT_STAGE/' || P_BATCH_ID || '/DQ_PROFILE_REPORT.csv';
END;
$$;

-- Quick test:
-- CALL AUDIT.SP_PROFILE_ALL('BATCH_001');
-- SELECT TABLE_NAME, COLUMN_NAME, DQ_OBSERVATIONS FROM AUDIT.V_DQ_PROFILE_REPORT
--  WHERE BATCH_ID = 'BATCH_001' AND DQ_OBSERVATIONS <> '' ORDER BY TABLE_NAME, COLUMN_POSITION;
-- LIST @AUDIT.REPORT_STAGE;
