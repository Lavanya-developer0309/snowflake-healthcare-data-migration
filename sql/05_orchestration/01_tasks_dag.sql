/*==============================================================================
  STEP 05 : ORCHESTRATION WITH SNOWFLAKE TASKS  (replaces the SQL Agent / core jobs)
  ----------------------------------------------------------------------------
  SP_RUN_STEP(step) reads the CURRENT batch from AUDIT.MIG_BATCH_CONTROL and
  calls the right procedure - so tasks never need a hard-coded batch id.

  Because dbt Core runs outside Snowflake (on a laptop or GitHub Actions),
  the pipeline is split into two task graphs with dbt in the middle:

     DAG 1  T_MIG_PRE_ROOT  : LOAD_RAW  -->  T_MIG_PRE_PROFILE : PROFILE
                     |
              dbt build  (seeds, transformations, validation tests, keyword files)
                     |
     DAG 2  T_MIG_POST_ROOT : LOAD_TARGET -->  T_MIG_POST_SCORECARD : SCORECARD

  Future enhancement: run dbt natively with "dbt Projects on Snowflake"
  (EXECUTE DBT PROJECT) as a task between PROFILE and LOAD_TARGET, making it
  one single DAG.

  Root tasks have a daily CRON schedule but are left SUSPENDED, so nothing
  runs (or costs credits) until you say so. Run them on demand with
  EXECUTE TASK. To switch the schedule on:  ALTER TASK <root> RESUME;
==============================================================================*/

USE ROLE MIG_DEVELOPER;
USE WAREHOUSE MIG_WH;
USE DATABASE HC_MIGRATION_DB;
USE SCHEMA AUDIT;

-------------------------------------------------------------------------------
-- Step dispatcher
-------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE AUDIT.SP_RUN_STEP(P_STEP VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    v_batch   VARCHAR;
    v_result  VARCHAR;
BEGIN
    SELECT MAX(BATCH_ID) INTO :v_batch
      FROM HC_MIGRATION_DB.AUDIT.MIG_BATCH_CONTROL
     WHERE IS_CURRENT;

    IF (v_batch IS NULL) THEN
        RETURN 'No current batch in AUDIT.MIG_BATCH_CONTROL - nothing to do';
    END IF;

    CASE (UPPER(P_STEP))
        WHEN 'LOAD_RAW' THEN
            CALL HC_MIGRATION_DB.AUDIT.SP_LOAD_RAW(:v_batch);
        WHEN 'PROFILE' THEN
            CALL HC_MIGRATION_DB.AUDIT.SP_PROFILE_ALL(:v_batch);
        WHEN 'LOAD_TARGET' THEN
            CALL HC_MIGRATION_DB.AUDIT.SP_LOAD_FACETS_TARGET(:v_batch);
        WHEN 'SCORECARD' THEN
            CALL HC_MIGRATION_DB.AUDIT.SP_BUILD_SCORECARD(:v_batch);
        ELSE
            RETURN 'Unknown step: ' || P_STEP;
    END CASE;

    SELECT $1 INTO :v_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    RETURN P_STEP || ' [' || v_batch || '] -> ' || v_result;
END;
$$;

-------------------------------------------------------------------------------
-- DAG 1 : before dbt
-------------------------------------------------------------------------------
CREATE OR REPLACE TASK AUDIT.T_MIG_PRE_ROOT
    WAREHOUSE = MIG_WH
    SCHEDULE  = 'USING CRON 0 6 * * * Asia/Kolkata'
    COMMENT   = 'Load source extracts from stage into RAW for the current batch'
AS
    CALL HC_MIGRATION_DB.AUDIT.SP_RUN_STEP('LOAD_RAW');

CREATE OR REPLACE TASK AUDIT.T_MIG_PRE_PROFILE
    WAREHOUSE = MIG_WH
    COMMENT   = 'Profile RAW tables and unload the client profiling report'
    AFTER AUDIT.T_MIG_PRE_ROOT
AS
    CALL HC_MIGRATION_DB.AUDIT.SP_RUN_STEP('PROFILE');

-------------------------------------------------------------------------------
-- DAG 2 : after dbt
-------------------------------------------------------------------------------
CREATE OR REPLACE TASK AUDIT.T_MIG_POST_ROOT
    WAREHOUSE = MIG_WH
    SCHEDULE  = 'USING CRON 0 8 * * * Asia/Kolkata'
    COMMENT   = 'Load keyword files into FACETS_TGT for the current batch'
AS
    CALL HC_MIGRATION_DB.AUDIT.SP_RUN_STEP('LOAD_TARGET');

CREATE OR REPLACE TASK AUDIT.T_MIG_POST_SCORECARD
    WAREHOUSE = MIG_WH
    COMMENT   = 'Build reconciliation scorecard + error log'
    AFTER AUDIT.T_MIG_POST_ROOT
AS
    CALL HC_MIGRATION_DB.AUDIT.SP_RUN_STEP('SCORECARD');

-- child tasks must be RESUMED for EXECUTE TASK to run the whole graph.
-- Root tasks stay SUSPENDED (schedule off) - EXECUTE TASK still works on them.
ALTER TASK AUDIT.T_MIG_PRE_PROFILE    RESUME;
ALTER TASK AUDIT.T_MIG_POST_SCORECARD RESUME;

SHOW TASKS IN SCHEMA AUDIT;

/*------------------------------------------------------------------------------
  HOW TO RUN

  -- 1) before dbt
  EXECUTE TASK AUDIT.T_MIG_PRE_ROOT;

  -- 2) run dbt build from your laptop:   cd dbt  &&  dbt build

  -- 3) after dbt
  EXECUTE TASK AUDIT.T_MIG_POST_ROOT;

  -- monitor runs (tasks are asynchronous - refresh after ~1 minute)
  SELECT NAME, STATE, SCHEDULED_TIME, COMPLETED_TIME, RETURN_VALUE, ERROR_MESSAGE
    FROM TABLE(HC_MIGRATION_DB.INFORMATION_SCHEMA.TASK_HISTORY(
               SCHEDULED_TIME_RANGE_START => DATEADD('hour', -2, CURRENT_TIMESTAMP())))
   ORDER BY SCHEDULED_TIME DESC;

  -- Snowsight UI: Data > Databases > HC_MIGRATION_DB > AUDIT > Tasks > Run History / Graph
------------------------------------------------------------------------------*/
