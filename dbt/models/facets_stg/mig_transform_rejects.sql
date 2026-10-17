{#
  All records rejected during transformation, one row per rejected source row.
  Used by: the reconciles_with_source test, SP_BUILD_SCORECARD, and the
  reject report sent back to the client for correction.
#}
{% set entities = [
    ('GROUP',       'int_group_prepared',      'group_number',                   "1 = 1"),
    ('SUBSCRIBER',  'int_member_prepared',     'member_id',                      "relationship_code = '18'"),
    ('MEMBER',      'int_member_prepared',     'member_id',                      "1 = 1"),
    ('ELIGIBILITY', 'int_member_prepared',     'member_id',                      "1 = 1"),
    ('PROVIDER',    'int_provider_prepared',   'provider_id',                    "1 = 1"),
    ('CLAIM',       'int_claim_prepared',      'claim_id',                       "1 = 1"),
    ('CLAIM_LINE',  'int_claim_line_prepared', "claim_id || '-' || line_number", "1 = 1"),
] %}

{% for entity, model, key_expr, filter in entities %}
select
    '{{ entity }}'::varchar(50)             as entity_name,
    ({{ key_expr }})::varchar(100)          as source_key,
    reject_reason::varchar(100)             as reject_reason,
    src_file_name::varchar(500)             as src_file_name,
    src_row_num::number                     as src_row_num,
    batch_id::varchar(50)                   as mig_batch_id,
    current_timestamp()::timestamp_ntz      as rejected_at
from {{ ref(model) }}
where reject_reason is not null
  and {{ filter }}
{% if not loop.last %}union all{% endif %}
{% endfor %}
