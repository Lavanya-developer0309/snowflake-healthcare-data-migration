{#
  Fails for values containing anything outside printable ASCII (space to ~):
  accented letters, tabs, control characters - same rule as the profiling procedure.
#}
{% test no_invalid_characters(model, column_name) %}
select {{ column_name }} as invalid_value
from {{ model }}
where regexp_count({{ column_name }}, '[^ -~]') > 0
{% endtest %}
