/*==============================================================================
  STEP 06-02 : TIME TRAVEL + ZERO-COPY CLONING  (recovery & environments)
  ----------------------------------------------------------------------------
  In SQL Server, undoing a bad update or building a test copy means backups,
  restores and a lot of storage. In Snowflake:
    - TIME TRAVEL  : query / restore data as it was N seconds or minutes ago
    - UNDROP       : bring back a dropped table
    - ZERO-COPY CLONE : a full copy of a table / schema / database in seconds,
                        no extra storage until the copy changes

  Run each block one at a time and look at the result.
==============================================================================*/

USE ROLE MIG_DEVELOPER;
USE WAREHOUSE MIG_WH;
USE DATABASE HC_MIGRATION_DB;

-------------------------------------------------------------------------------
-- 1. A "restore point" before a risky change: clone the target schema
-------------------------------------------------------------------------------
CREATE OR REPLACE SCHEMA FACETS_TGT_BKP_BEFORE_FIX CLONE FACETS_TGT;

-------------------------------------------------------------------------------
-- 2. Oops - a bad update on the target (forgot the WHERE clause!)
-------------------------------------------------------------------------------
SELECT MEME_SEX, COUNT(*) FROM FACETS_TGT.CMC_MEME_MEMBER GROUP BY 1;

UPDATE FACETS_TGT.CMC_MEME_MEMBER SET MEME_SEX = 'U';
SET BAD_QUERY_ID = LAST_QUERY_ID();

SELECT MEME_SEX, COUNT(*) FROM FACETS_TGT.CMC_MEME_MEMBER GROUP BY 1;     -- all 'U' now

-------------------------------------------------------------------------------
-- 3a. Look at the data as it was BEFORE that statement
-------------------------------------------------------------------------------
SELECT MEME_SEX, COUNT(*)
FROM FACETS_TGT.CMC_MEME_MEMBER BEFORE (STATEMENT => $BAD_QUERY_ID)
GROUP BY 1;

-- 3b. Fix it: put the old values back from Time Travel
UPDATE FACETS_TGT.CMC_MEME_MEMBER t
   SET MEME_SEX = old.MEME_SEX
  FROM FACETS_TGT.CMC_MEME_MEMBER BEFORE (STATEMENT => $BAD_QUERY_ID) old
 WHERE t.MEME_CK = old.MEME_CK;

SELECT MEME_SEX, COUNT(*) FROM FACETS_TGT.CMC_MEME_MEMBER GROUP BY 1;     -- restored

-- (alternative: restore the whole table from a clone at that point in time)
-- CREATE OR REPLACE TABLE FACETS_TGT.CMC_MEME_MEMBER_RESTORED
--   CLONE FACETS_TGT.CMC_MEME_MEMBER BEFORE (STATEMENT => $BAD_QUERY_ID);

-------------------------------------------------------------------------------
-- 4. DROP + UNDROP
-------------------------------------------------------------------------------
DROP TABLE FACETS_TGT.CMC_CDML_CL_LINE;
SHOW TABLES HISTORY LIKE 'CMC_CDML_CL_LINE' IN SCHEMA FACETS_TGT;          -- DROPPED_ON is set
UNDROP TABLE FACETS_TGT.CMC_CDML_CL_LINE;
SELECT COUNT(*) FROM FACETS_TGT.CMC_CDML_CL_LINE;                          -- it's back

-------------------------------------------------------------------------------
-- 5. A complete QA environment in seconds (database clone)
-------------------------------------------------------------------------------
CREATE OR REPLACE DATABASE HC_MIGRATION_QA CLONE HC_MIGRATION_DB;
SHOW SCHEMAS IN DATABASE HC_MIGRATION_QA;
-- QA can now run mock conversions in HC_MIGRATION_QA without touching DEV.

-------------------------------------------------------------------------------
-- 6. Clean up the demo objects (they cost almost nothing, but keep it tidy)
-------------------------------------------------------------------------------
DROP SCHEMA IF EXISTS FACETS_TGT_BKP_BEFORE_FIX;
DROP DATABASE IF EXISTS HC_MIGRATION_QA;
