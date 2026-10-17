{#
  Pre-load CONFIG VALUE CHECK: every value must exist in REF.CONFIG_VALID_VALUES
  for the given config type (e.g. VALID_STATE, VALID_LOB).
#}
{% test values_in_config(model, column_name, config_type) %}
select {{ column_name }} as invalid_value, count(*) as record_count
from {{ model }}
where {{ column_name }} is not null
  and {{ column_name }} not in (
        select config_value
        from {{ ref('config_valid_values') }}
        where config_type = '{{ config_type }}'
  )
group by 1
{% endtest %}
