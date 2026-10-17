/*==============================================================================
  STEP 00-04 : DYNAMIC DATA MASKING FOR PHI / PII  (HIPAA "minimum necessary")
  ----------------------------------------------------------------------------
  Only the pipeline role (MIG_DEVELOPER) and admins see clear values.
  MIG_QA and MIG_ANALYST see masked values.

  Why CURRENT_ROLE() and not IS_ROLE_IN_SESSION()?
  Snowsight turns on all "secondary roles" by default. If your user has
  MIG_DEVELOPER granted, IS_ROLE_IN_SESSION('MIG_DEVELOPER') would be TRUE
  even after you switch to MIG_ANALYST, and the demo would show clear data.
  CURRENT_ROLE() only checks the primary role you selected.

  dbt applies these policies to FACETS_STG tables (post-hook). Script
  sql/06_security_and_recovery/01_apply_masking_to_target.sql applies them to
  FACETS_TGT after the first load.
==============================================================================*/

USE ROLE MIG_DEVELOPER;
USE DATABASE HC_MIGRATION_DB;
USE SCHEMA GOVERNANCE;

CREATE OR REPLACE MASKING POLICY GOVERNANCE.MP_MASK_SSN AS (VAL VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('MIG_DEVELOPER', 'SYSADMIN', 'ACCOUNTADMIN') THEN VAL
        WHEN VAL IS NULL THEN NULL
        ELSE 'XXX-XX-' || RIGHT(VAL, 4)
    END
    COMMENT = 'Shows only last 4 digits of SSN to non-privileged roles';

CREATE OR REPLACE MASKING POLICY GOVERNANCE.MP_MASK_DOB AS (VAL DATE) RETURNS DATE ->
    CASE
        WHEN CURRENT_ROLE() IN ('MIG_DEVELOPER', 'SYSADMIN', 'ACCOUNTADMIN') THEN VAL
        WHEN VAL IS NULL THEN NULL
        ELSE DATE_FROM_PARTS(YEAR(VAL), 1, 1)        -- keep birth year only
    END
    COMMENT = 'Generalises date of birth to 01-Jan of birth year';

CREATE OR REPLACE MASKING POLICY GOVERNANCE.MP_MASK_NAME AS (VAL VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('MIG_DEVELOPER', 'SYSADMIN', 'ACCOUNTADMIN') THEN VAL
        WHEN VAL IS NULL THEN NULL
        ELSE LEFT(VAL, 1) || '*****'
    END
    COMMENT = 'Shows first letter of a person name only';

CREATE OR REPLACE MASKING POLICY GOVERNANCE.MP_MASK_STRING AS (VAL VARCHAR) RETURNS VARCHAR ->
    CASE
        WHEN CURRENT_ROLE() IN ('MIG_DEVELOPER', 'SYSADMIN', 'ACCOUNTADMIN') THEN VAL
        WHEN VAL IS NULL THEN NULL
        ELSE '*** MASKED ***'
    END
    COMMENT = 'Full mask for raw PHI strings (raw SSN / DOB text)';

SHOW MASKING POLICIES IN SCHEMA GOVERNANCE;
