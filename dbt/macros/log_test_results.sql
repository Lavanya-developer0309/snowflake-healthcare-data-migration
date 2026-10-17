{#
  on-run-end hook: write the result of every dbt test in this invocation to
  AUDIT.DBT_TEST_RESULTS, so SP_BUILD_SCORECARD can report warnings / failures
  next to the reconciliation counts.
#}
{% macro log_test_results(results) %}
    {%- if execute -%}
        {%- set rows = [] -%}
        {%- for r in results if r.node.resource_type == 'test' -%}
            {%- set node = r.node -%}
            {%- if node.attached_node -%}
                {%- set tested = node.attached_node.split('.')[-1] -%}
            {%- elif node.depends_on.nodes | length > 0 -%}
                {%- set tested = node.depends_on.nodes[-1].split('.')[-1] -%}
            {%- else -%}
                {%- set tested = 'UNKNOWN' -%}
            {%- endif -%}
            {%- set msg = (r.message or '') | string | replace("\\", "/") | replace("'", "''") | truncate(3900) -%}
            {%- do rows.append(
                "('" ~ var('batch_id') ~ "', '" ~ invocation_id ~ "', '" ~ node.name ~ "', '"
                ~ node.unique_id ~ "', '" ~ (tested | upper) ~ "', '" ~ (node.config.severity | upper) ~ "', '"
                ~ r.status ~ "', " ~ (r.failures if r.failures is not none else 'null') ~ ", '" ~ msg ~ "', current_timestamp())"
            ) -%}
        {%- endfor -%}
        {%- if rows | length > 0 -%}
insert into {{ target.database }}.AUDIT.DBT_TEST_RESULTS
    (batch_id, invocation_id, test_name, test_unique_id, tested_object, severity, status, failures, message, run_at)
values
    {{ rows | join(',\n    ') }}
        {%- else -%}
select 'no tests in this run' as msg
        {%- endif -%}
    {%- endif -%}
{% endmacro %}
