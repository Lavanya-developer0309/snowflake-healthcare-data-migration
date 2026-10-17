{#
  Fails for values that are present but are not a valid date in the legacy
  format (e.g. 02/30/1985, 13/01/1990, 1988-07-14).
#}
{% test valid_legacy_date(model, column_name, date_format='MM/DD/YYYY') %}
select {{ column_name }} as invalid_value
from {{ model }}
where nullif(trim({{ column_name }}), '') is not null
  and try_to_date(trim({{ column_name }}), '{{ date_format }}') is null
{% endtest %}
