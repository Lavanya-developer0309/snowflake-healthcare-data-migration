{#
  Pre-load RECONCILIATION CHECK:
      source rows (RAW, this batch, optional filter)
    = rows in this Facets-like model + rows rejected for this entity
  If not, records were lost or duplicated in the transformation.
#}
{% test reconciles_with_source(model, source_table, entity_name, source_filter='1 = 1') %}
with src as (
    select count(*) as cnt
    from {{ source('legacy', source_table) }}
    where batch_id = '{{ var("batch_id") }}'
      and ({{ source_filter }})
),
staged as (
    select count(*) as cnt from {{ model }}
),
rejected as (
    select count(*) as cnt
    from {{ ref('mig_transform_rejects') }}
    where entity_name = '{{ entity_name }}'
)
select src.cnt      as source_count,
       staged.cnt   as staged_count,
       rejected.cnt as rejected_count
from src cross join staged cross join rejected
where src.cnt <> staged.cnt + rejected.cnt
{% endtest %}
