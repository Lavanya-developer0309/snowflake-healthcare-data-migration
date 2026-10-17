"""
Migration Scorecard dashboard - Streamlit in Snowflake
=======================================================
Create it in Snowsight:
  Projects > Streamlit > + Streamlit App
    App title    : Migration Scorecard
    Location     : HC_MIGRATION_DB.AUDIT
    Warehouse    : MIG_WH
  then replace the sample code with this file and click Run.

Runs inside Snowflake with the viewer's role, so PHI masking still applies.
"""
import streamlit as st
from snowflake.snowpark.context import get_active_session

session = get_active_session()
st.set_page_config(page_title="Migration Scorecard", layout="wide")
st.title("Healthcare Data Migration - Scorecard")


def q(sql):
    return session.sql(sql).to_pandas()


batches = q("SELECT BATCH_ID, STATUS, STARTED_AT, ENDED_AT FROM HC_MIGRATION_DB.AUDIT.MIG_BATCH_CONTROL ORDER BY CREATED_AT DESC")
if batches.empty:
    st.info("No batches yet - run the pipeline first.")
    st.stop()

batch = st.selectbox("Batch", batches["BATCH_ID"].tolist())
info = batches[batches["BATCH_ID"] == batch].iloc[0]

score = q(f"""SELECT ENTITY_NAME, SOURCE_COUNT, REJECT_COUNT, STAGED_COUNT, KEYWORD_DETAIL_COUNT,
                     TARGET_COUNT, LOAD_PCT, SOURCE_RECON_STATUS, TARGET_RECON_STATUS,
                     TEST_WARNING_COUNT, TEST_FAILURE_COUNT, OVERALL_STATUS
              FROM HC_MIGRATION_DB.AUDIT.V_SCORECARD
              WHERE BATCH_ID = '{batch}'
              ORDER BY ENTITY_NAME""")

c1, c2, c3, c4 = st.columns(4)
c1.metric("Batch status", info["STATUS"])
c2.metric("Source records", f"{int(score['SOURCE_COUNT'].sum()):,}" if not score.empty else "-")
c3.metric("Loaded to target", f"{int(score['TARGET_COUNT'].sum()):,}" if not score.empty else "-")
c4.metric("Rejected", f"{int(score['REJECT_COUNT'].sum()):,}" if not score.empty else "-")

st.subheader("Source vs target reconciliation")


def colour(val):
    return {"PASSED": "background-color:#d4edda", "PASSED_WITH_WARNINGS": "background-color:#fff3cd",
            "FAILED": "background-color:#f8d7da", "BALANCED": "color:#155724", "MATCH": "color:#155724",
            "OUT_OF_BALANCE": "color:#721c24", "MISMATCH": "color:#721c24"}.get(val, "")


st.dataframe(score.style.map(colour), use_container_width=True, hide_index=True)

left, right = st.columns(2)
with left:
    st.subheader("Rejects by reason")
    rej = q(f"""SELECT ENTITY_NAME || ' - ' || REJECT_REASON AS REASON, COUNT(*) AS RECORDS
                FROM HC_MIGRATION_DB.FACETS_STG.MIG_TRANSFORM_REJECTS
                WHERE MIG_BATCH_ID = '{batch}' AND ENTITY_NAME NOT IN ('SUBSCRIBER', 'ELIGIBILITY')
                GROUP BY 1 ORDER BY 2 DESC""")
    if rej.empty:
        st.success("No rejects")
    else:
        st.bar_chart(rej, x="REASON", y="RECORDS")

with right:
    st.subheader("Error log")
    sev = st.multiselect("Severity", ["ERROR", "WARNING", "INFO"], default=["ERROR", "WARNING"])
    sev_list = ",".join(f"'{s}'" for s in sev) or "''"
    err = q(f"""SELECT SEVERITY, ERROR_CATEGORY, ENTITY_NAME, ERROR_CODE, RECORD_COUNT, SAMPLE_KEYS
                FROM HC_MIGRATION_DB.AUDIT.V_ERROR_SUMMARY
                WHERE BATCH_ID = '{batch}' AND SEVERITY IN ({sev_list})
                ORDER BY SEVERITY, ERROR_CATEGORY, ENTITY_NAME""")
    st.dataframe(err, use_container_width=True, hide_index=True)

st.subheader("Source data profiling observations")
prof = q(f"""SELECT TABLE_NAME, COLUMN_NAME, TOTAL_ROWS, NULL_COUNT, MIN_VALUE, MAX_VALUE, DQ_OBSERVATIONS
             FROM HC_MIGRATION_DB.AUDIT.V_DQ_PROFILE_REPORT
             WHERE BATCH_ID = '{batch}' AND DQ_OBSERVATIONS <> ''
             ORDER BY TABLE_NAME, COLUMN_POSITION""")
st.dataframe(prof, use_container_width=True, hide_index=True)

st.subheader("Pipeline log")
log = q(f"""SELECT LOGGED_AT, STEP_NAME, OBJECT_NAME, ROW_COUNT, STATUS, MESSAGE
            FROM HC_MIGRATION_DB.AUDIT.MIG_LOAD_LOG WHERE BATCH_ID = '{batch}' ORDER BY LOG_ID""")
st.dataframe(log, use_container_width=True, hide_index=True)
