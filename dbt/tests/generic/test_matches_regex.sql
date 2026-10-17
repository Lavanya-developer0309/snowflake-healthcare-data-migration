{#
  Fails for non-null values that do not match the pattern.
  Snowflake REGEXP_LIKE matches the WHOLE value, so "[0-9]{9}" means exactly 9 digits.
#}
{% test matches_regex(model, column_name, pattern) %}
select {{ column_name }} as invalid_value
from {{ model }}
where {{ column_name }} is not null
  and not regexp_like({{ column_name }}, '{{ pattern }}')
{% endtest %}
