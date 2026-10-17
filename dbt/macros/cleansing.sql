{#
  Reusable cleansing rules (the same rules are listed in docs/mapping_document.xlsx)
#}

{# trim, blanks -> NULL #}
{% macro clean_text(column) -%}
    nullif(trim({{ column }}), '')
{%- endmacro %}

{# trim + upper-case codes #}
{% macro clean_code(column) -%}
    nullif(upper(trim({{ column }})), '')
{%- endmacro %}

{#
  Names: Facets expects plain ASCII.
    1. control characters (tab, etc.) -> space
    2. common accented letters -> base letter (JOSÉ -> JOSE)
    3. anything else outside printable ASCII is removed
    4. repeated spaces collapsed, trimmed, upper-cased
#}
{% macro clean_name(column) -%}
    nullif(upper(trim(regexp_replace(
        regexp_replace(
            translate(
                regexp_replace({{ column }}, '[[:cntrl:]]', ' '),
                'ÀÁÂÃÄÅàáâãäåÈÉÊËèéêëÌÍÎÏìíîïÒÓÔÕÖòóôõöÙÚÛÜùúûüÑñÇçÝýÿ',
                'AAAAAAaaaaaaEEEEeeeeIIIIiiiiOOOOOoooooUUUUuuuuNnCcYyy'
            ),
            '[^ -~]', ''),
        ' +', ' '))), '')
{%- endmacro %}

{# legacy MM/DD/YYYY text -> DATE (NULL when invalid) #}
{% macro legacy_to_date(column) -%}
    try_to_date(nullif(trim({{ column }}), ''), 'MM/DD/YYYY')
{%- endmacro %}

{# text amount -> NUMBER(12,2) (NULL when invalid) #}
{% macro to_amount(column) -%}
    try_to_number(nullif(trim({{ column }}), ''), 12, 2)
{%- endmacro %}

{# keep digits only #}
{% macro digits_only(column) -%}
    nullif(regexp_replace({{ column }}, '[^0-9]', ''), '')
{%- endmacro %}
