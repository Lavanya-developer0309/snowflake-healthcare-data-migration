{#
  By default dbt builds schema names like STAGING_FACETS_STG (target + custom).
  For this project every layer has a fixed schema created by the setup script,
  so use the custom schema name exactly as written.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim | upper }}
    {%- endif -%}
{%- endmacro %}
