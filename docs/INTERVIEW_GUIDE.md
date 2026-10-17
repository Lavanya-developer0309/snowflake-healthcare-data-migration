# Interview Guide: how to present this project

## 1. Resume entry

**Healthcare Payer Data Migration on Snowflake + dbt** *(personal project · GitHub link)*
- Built an end-to-end migration pipeline converting legacy US payer extracts (groups, members, eligibility,
  providers, claims) into a Facets-like target on **Snowflake**, mirroring a production conversion workflow.
- Wrote metadata-driven **Snowflake Scripting stored procedures** for stage-based `COPY INTO` loading,
  dynamic-SQL **data profiling** (null, min/max, invalid-character checks) and a source-to-target
  **reconciliation scorecard**.
- Implemented the source-to-target mapping in **dbt Core** (staging → intermediate → target models, crosswalk
  seeds) with **80+ data tests** acting as a pre-load validation gate (duplicates, referential integrity,
  config values, record-count reconciliation).
- Generated header/trailer **load (keyword) files** with dbt post-hooks and loaded them transactionally;
  orchestrated with **Snowflake Tasks** and **GitHub Actions**.
- Secured PHI with **RBAC** and **dynamic data masking**; demonstrated **Time Travel**, UNDROP and
  **zero-copy cloning** for recovery and test environments.

**Skills line:** Snowflake (stages, COPY INTO, Snowflake Scripting, Tasks, Time Travel,
Cloning, Masking Policies, RBAC, Streamlit) · dbt Core (models, seeds, tests, macros, hooks) · SQL Server /
T-SQL · Data Migration · Data Profiling · Facets · Git / GitHub Actions · Python

> Always say it's a **personal project** that replicates your real-world process with synthetic data.
> Your 4+ years of real migration experience is what gives it weight.

---

## 2. The 2-minute walkthrough (practise saying this out loud)

> "In my current role I migrate US healthcare payer data from multiple clients into Facets, using SQL Server.
> To move into Snowflake I rebuilt that same process end to end, using synthetic data.
>
> **Source files** land in an internal stage, and a stored procedure loads them with COPY INTO into
> all-VARCHAR raw tables, adding batch and file lineage. It's driven by a config table, so a new file is a
> new row, not new code.
>
> **Profiling** is another procedure that uses dynamic SQL to profile every column: nulls, min/max, dates,
> numerics, invalid characters. It unloads a CSV report for the client.
>
> **Transformation** is in dbt. Staging models cleanse and type the data, intermediate models apply the
> mapping rules and crosswalks and decide accept or reject with a reason code, and the final models are
> Facets-like tables. Every source row ends up either in a target table or in a rejects table, so source
> equals target plus rejects, and that's a dbt test.
>
> **Validation** is dbt tests: duplicates, relationships, config values, and reconciliation. They act as a
> gate: if any fails, dbt skips the keyword model for that entity.
>
> The **keyword file** has header, detail and trailer records and is unloaded to a stage. A loader
> procedure checks the header and trailer count and loads the target in one transaction.
>
> Finally a **scorecard** procedure compares counts at every hop, from source to rejected, staged, keyword
> and target, and logs every warning.
> Tasks orchestrate it, masking policies protect PHI, and Time Travel and cloning cover recovery and test
> environments."

---

## 3. Questions you should expect, with answers

### Snowflake

**Q: How is Snowflake's architecture different from SQL Server?**
Storage and compute are separate. Data is stored once in compressed columnar micro-partitions; compute is
virtual warehouses that start, stop and resize independently. In SQL Server one server does everything, so
heavy loads compete with queries. In Snowflake I can give the migration its own warehouse.

**Q: Why are the RAW tables transient and all VARCHAR?**
VARCHAR so that nothing fails on load: a bad date is still loaded and then *reported* by profiling instead
of breaking the load. Transient because raw data can be reloaded from the stage, so we don't pay for 7 days
of fail-safe storage.

**Q: What is a stage? Internal vs external?**
A file location Snowflake can read and write. Internal stages are inside Snowflake (what I used, no cloud
account needed). External stages point to S3, Azure Blob or GCS through a storage integration. The COPY INTO
logic is the same either way, so moving to S3 is a config change.

**Q: How do you handle bad records during COPY INTO?**
`ON_ERROR = 'CONTINUE'` keeps loading; `VALIDATE(table, JOB_ID => '_last')` shows the rows that failed.
Mostly, because RAW is all VARCHAR, I don't need COPY to reject anything. Rejection happens in the
transformation, with a reason code.

**Q: Time Travel vs Fail-safe?**
Time Travel (1 day by default, up to 90 on Enterprise) is user-accessible: `AT` / `BEFORE` queries, UNDROP,
cloning at a point in time. Fail-safe is 7 extra days that only Snowflake support can recover from.
In the project I undo a bad UPDATE with `BEFORE(STATEMENT => query_id)`.

**Q: What is zero-copy cloning and how would you use it in a migration?**
`CREATE DATABASE QA CLONE DEV` copies metadata only; storage is shared until something changes. I'd use it
to give QA a full copy for each mock conversion, or to take a restore point before a risky fix.

**Q: How did you secure PHI?**
Role hierarchy (developer, QA, analyst) with least-privilege grants, and dynamic masking policies on SSN,
DOB and names. The developer role sees clear values, others see masked. One detail: I used
`CURRENT_ROLE()` instead of `IS_ROLE_IN_SESSION()`, because with secondary roles enabled a user who also
holds the developer role would otherwise see clear data even after switching roles.

**Q: How do Tasks work?**
Tasks run SQL or procedure calls on a schedule or after another task, forming a DAG. Child tasks must be
resumed; you can trigger the root with `EXECUTE TASK`. I split mine into a pre-dbt and post-dbt graph
because dbt Core runs outside Snowflake. With dbt Projects on Snowflake it could be one graph.

**Q: How do you control cost?**
X-Small warehouse, 60-second auto-suspend, a resource monitor that suspends at the credit quota, transient
tables for reloadable data, and looking at query history for the slowest queries.

**Q: Stored procedures in Snowflake vs T-SQL?**
Snowflake Scripting is very close to T-SQL: `DECLARE`, `BEGIN…END`, `IF`, `FOR` loops over cursors,
`EXCEPTION WHEN OTHER`, `EXECUTE IMMEDIATE` for dynamic SQL (like `sp_executesql`). Differences: variables
inside SQL need a colon (`:v_batch`), `IDENTIFIER(:var)` for dynamic table names, and `RESULTSET` instead
of temp tables for intermediate results.

### dbt

**Q: Why dbt and not just stored procedures?**
Transformations become version-controlled SELECT statements with dependencies dbt works out itself, tests
live next to the models, and I get documentation and a lineage graph for free. I kept stored procedures
for procedural work like file loads, dynamic profiling and the scorecard. That's the hybrid.

**Q: Explain your model layers.**
Staging: one view per source, cleanse and type only. Intermediate: business rules, crosswalks, reject
reasons, contrived keys. Facets_stg: target-shaped tables with only accepted rows. Keyword: load-file
records.

**Q: What are seeds? Why use them for crosswalks?**
Small CSVs dbt loads as tables. Crosswalks change with BA sign-off, so having them in Git gives history and
review through pull requests. I set `column_types` so codes like `01` aren't turned into numbers.

**Q: What tests did you write?**
Built-in `unique`, `not_null`, `relationships`, `accepted_values`; dbt_utils
`unique_combination_of_columns` and `expression_is_true`; and custom generic tests: `values_in_config`,
`reconciles_with_source`, `valid_legacy_date`, `matches_regex`, `no_invalid_characters`. Source tests are
`warn` (they document client data), pre-load tests are `error` (they block the load).

**Q: How does the "validation gate" work?**
`dbt build` runs models and tests in dependency order. The keyword models depend on the Facets-like
models, so if any error-level test on a parent fails, dbt skips the keyword model and no load file is
produced. I also clear old keyword files at the start of every run so a stale file can't be loaded.

**Q: How do test results reach the scorecard?**
An `on-run-end` hook loops over dbt's `results` object and inserts each test's status and failure count
into `AUDIT.DBT_TEST_RESULTS`. The scorecard procedure reads the latest run.

**Q: What are macros? Give an example.**
Jinja functions that generate SQL. `clean_name()` holds the name-cleansing rule used in several models;
`build_keyword_records()` reads a table's columns at run time and builds the pipe-delimited records, so
adding a column to a model automatically adds it to the keyword file.

**Q: What's `generate_schema_name` and why did you override it?**
By default dbt prefixes custom schemas with the target schema (`STAGING_FACETS_STG`). My schemas are created
by the setup script with grants, so I override it to use the exact name.

**Q: Incremental models?**
The initial conversion is a full load, so tables are rebuilt each run. For daily post-conversion files I'd
use `materialized='incremental'` with `unique_key` and `is_incremental()` filtering on the batch, or Streams.

### Migration / domain

**Q: How do you make sure no records are lost?**
Every source row is either loaded or rejected with a reason, never silently dropped. The
`reconciles_with_source` test checks `source = staged + rejected` per entity, and the scorecard checks
`staged = keyword detail = trailer count = target`.

**Q: How do you handle a dependent whose subscriber failed?**
Rejects cascade: group → subscriber → dependents → claims → claim lines, each with its own reason
(`SUBSCRIBER_NOT_LOADED`, `MEMBER_NOT_LOADED`, ...). It matches the target's referential rules, and the
client can see the root cause.

**Q: Reject or load with warning, how do you decide?**
If loading would break the target or the business (no DOB, unmapped plan) → reject. If the business agreed
to load and report (missing SSN, bad NPI length, negative paid line) → warning. In real projects the BA and
client sign this off in the mapping document; mine is in `docs/mapping_document.xlsx`.

**Q: What are MEME_SFX and contrived keys?**
Facets identifies a member by subscriber + suffix: 0 for the subscriber, then spouse, then dependents.
Contrived keys (GRGR_CK, SBSB_CK, MEME_CK) are surrogate numeric keys generated during conversion; I
generate them with ROW_NUMBER() from configurable starting numbers.

**Q: What would you change for production?**
S3 external stage + Snowpipe for ingestion, dbt Projects on Snowflake or Airflow for one orchestrated DAG,
separate DEV/QA/PROD databases via cloning, a passphrase-protected key in a secrets manager, alerts on
failed tasks, and incremental loads after go-live.

---

## 4. Things to have open during a technical interview
- The GitHub repo (README architecture diagram)
- The scorecard query result screenshot
- `dbt docs serve` lineage graph
- `int_member_prepared.sql` (shows reject logic + keys) and `SP_LOAD_FACETS_TARGET` (shows Snowflake Scripting)
