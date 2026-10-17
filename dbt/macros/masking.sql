{#
  post-hook: attach a masking policy (created in sql/00_setup/04_masking_policies.sql)
  to a column of the model just built. dbt recreates the table on every run,
  so the policy is re-applied every run.
#}
{% macro apply_masking(column, policy) %}
    {%- if var('enable_masking', true) -%}
alter table {{ this }} modify column {{ column }}
    set masking policy {{ target.database }}.GOVERNANCE.{{ policy }} force
    {%- else -%}
select 'masking disabled' as msg
    {%- endif -%}
{% endmacro %}
