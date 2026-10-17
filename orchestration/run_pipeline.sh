#!/usr/bin/env bash
# ==============================================================================
#  Run the full migration pipeline for one batch  (macOS / Linux / Git Bash)
#
#    ./orchestration/run_pipeline.sh              # BATCH_001
#    ./orchestration/run_pipeline.sh BATCH_002
#
#  Prerequisites: source files uploaded to @RAW.SRC_STAGE/<BATCH>/,
#  dbt installed, ~/.dbt/profiles.yml + environment variables set (docs/SETUP_GUIDE.md)
# ==============================================================================
set -uo pipefail

BATCH="${1:-BATCH_001}"
VARS="{batch_id: ${BATCH}}"
cd "$(dirname "$0")/../dbt"

step() { echo; echo "=================================================================="; echo " $1"; echo "=================================================================="; }

step "1/6  Load source extracts into RAW            (SP_LOAD_RAW)"
dbt run-operation load_raw --vars "$VARS" || exit 1

step "2/6  Profile source data + client report     (SP_PROFILE_ALL)"
dbt run-operation profile_source --vars "$VARS" || exit 1

step "3/6  Clear old keyword files"
dbt run-operation clear_keyword_files --vars "$VARS" || exit 1

step "4/6  dbt build: crosswalks, transformations, validation gate, keyword files"
dbt build --vars "$VARS"
DBT_STATUS=$?
if [ $DBT_STATUS -ne 0 ]; then
  echo "!! dbt build reported errors - entities that failed validation have NO keyword file."
  echo "!! Continuing so the scorecard shows exactly what did and did not load."
fi

step "5/6  Load keyword files into FACETS_TGT       (SP_LOAD_FACETS_TARGET)"
dbt run-operation load_target --vars "$VARS"
LOAD_STATUS=$?

step "6/6  Build reconciliation scorecard           (SP_BUILD_SCORECARD)"
dbt run-operation build_scorecard --vars "$VARS" || exit 1

echo
echo "Done. In Snowsight run:  SELECT * FROM HC_MIGRATION_DB.AUDIT.V_SCORECARD WHERE BATCH_ID = '${BATCH}';"
if [ $DBT_STATUS -ne 0 ] || [ $LOAD_STATUS -ne 0 ]; then exit 1; fi
