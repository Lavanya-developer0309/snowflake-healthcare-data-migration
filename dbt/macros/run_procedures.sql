{#
  ============================================================================
  Call the Snowflake stored procedures from dbt, so the whole pipeline can be
  driven from one command line (see orchestration/run_pipeline.*):

      dbt run-operation load_raw          -> AUDIT.SP_LOAD_RAW
      dbt run-operation profile_source    -> AUDIT.SP_PROFILE_ALL
      dbt build                           -> transformations + validation + keyword files
      dbt run-operation load_target       -> AUDIT.SP_LOAD_FACETS_TARGET
      dbt run-operation build_scorecard   -> AUDIT.SP_BUILD_SCORECARD

  The batch comes from var('batch_id'); override with
      dbt run-operation load_raw --vars "{batch_id: BATCH_002}"
  ============================================================================
#}

{% macro call_procedure(proc_name) %}
    {%- set sql -%}
        call {{ target.database }}.AUDIT.{{ proc_name }}('{{ var("batch_id") }}')
    {%- endset -%}
    {{ log("Running " ~ proc_name ~ " for batch " ~ var("batch_id") ~ " ...", info=True) }}
    {%- set result = run_query(sql) -%}
    {%- set message = result.columns[0].values()[0] -%}
    {{ log(proc_name ~ " -> " ~ message, info=True) }}
    {%- if 'error' in (message | lower) and 'with 0 error' not in (message | lower) -%}
        {{ exceptions.raise_compiler_error(proc_name ~ " reported errors: " ~ message) }}
    {%- endif -%}
{% endmacro %}

{% macro load_raw() %}{% do call_procedure('SP_LOAD_RAW') %}{% endmacro %}
{% macro profile_source() %}{% do call_procedure('SP_PROFILE_ALL') %}{% endmacro %}
{% macro load_target() %}{% do call_procedure('SP_LOAD_FACETS_TARGET') %}{% endmacro %}
{% macro build_scorecard() %}{% do call_procedure('SP_BUILD_SCORECARD') %}{% endmacro %}

{#
  Delete old keyword files of this batch before dbt build, so a failed
  validation can never leave a stale file behind for SP_LOAD_FACETS_TARGET.
#}
{% macro clear_keyword_files() %}
    {%- set sql -%}
        remove @{{ target.database }}.AUDIT.KEYWORD_STAGE/{{ var("batch_id") }}/
    {%- endset -%}
    {% do run_query(sql) %}
    {{ log("Removed old keyword files for batch " ~ var("batch_id"), info=True) }}
{% endmacro %}
