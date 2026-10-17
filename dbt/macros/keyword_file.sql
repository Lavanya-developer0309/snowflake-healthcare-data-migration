{#
  ============================================================================
  KEYWORD (LOAD) FILE GENERATION
  ----------------------------------------------------------------------------
  build_keyword_records(relation, entity)
      Turns a validated FACETS_STG table into keyword records:
          HDR|<ENTITY>|<BATCH_ID>|<YYYYMMDDHH24MISS>
          DTL|col1|col2|...|colN        (one per row, columns in table order)
          TRL|<ENTITY>|<detail count>
      Column list is read from the table itself, so adding a column to a
      Facets-like model automatically adds it to the keyword file.

  unload_keyword_file(entity)
      post-hook: COPY INTO @AUDIT.KEYWORD_STAGE/<BATCH_ID>/KW_<ENTITY>.txt
  ============================================================================
#}

{% macro keyword_field(col) -%}
    {%- set dtype = col.dtype | upper -%}
    {%- if dtype == 'DATE' -%}
        coalesce(to_varchar({{ col.name }}, 'YYYY-MM-DD'), '')
    {%- elif 'TIMESTAMP' in dtype -%}
        coalesce(to_varchar({{ col.name }}, 'YYYY-MM-DD HH24:MI:SS.FF3'), '')
    {%- elif col.is_number() -%}
        coalesce(to_varchar({{ col.name }}), '')
    {%- else -%}
        coalesce(replace(to_varchar({{ col.name }}), '|', ' '), '')
    {%- endif -%}
{%- endmacro %}

{% macro build_keyword_records(relation, entity) %}
    {%- if execute -%}
        {%- set cols = adapter.get_columns_in_relation(relation) -%}
    {%- else -%}
        {%- set cols = [] -%}
    {%- endif -%}
    {%- if cols | length == 0 -%}
        {# parse time / table missing: return an empty, correctly-shaped result #}
        select 0::number as kw_line_no, ''::varchar as kw_record where false
    {%- else -%}
with detail as (
    select
        row_number() over (order by {{ cols[0].name }}) as kw_line_no,
        'DTL|' || {% for c in cols %}{{ keyword_field(c) }}{% if not loop.last %} || '|' || {% endif %}{% endfor %} as kw_record
    from {{ relation }}
    where mig_batch_id = '{{ var("batch_id") }}'
)
select 0 as kw_line_no,
       'HDR|{{ entity }}|{{ var("batch_id") }}|' || to_varchar(current_timestamp(), 'YYYYMMDDHH24MISS') as kw_record
union all
select kw_line_no, kw_record from detail
union all
select count(*) + 1, 'TRL|{{ entity }}|' || count(*) from detail
    {%- endif -%}
{% endmacro %}

{% macro unload_keyword_file(entity) %}
    {%- if var('generate_keyword_files', true) -%}
copy into @{{ target.database }}.AUDIT.KEYWORD_STAGE/{{ var('batch_id') }}/KW_{{ entity }}.txt
from (select kw_record from {{ this }} order by kw_line_no)
file_format = (format_name = '{{ target.database }}.AUDIT.FF_KEYWORD')
single = true
overwrite = true
header = false
max_file_size = 1073741824
    {%- else -%}
select 'keyword file generation disabled' as msg
    {%- endif -%}
{% endmacro %}
