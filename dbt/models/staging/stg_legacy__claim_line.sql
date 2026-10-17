-- Cleansed + typed claim lines for the current batch
select
    {{ clean_code('claim_id') }}                       as claim_id,
    try_to_number(trim(line_number))                   as line_number,
    {{ clean_code('procedure_code') }}                 as procedure_code,
    {{ clean_code('procedure_modifier') }}             as procedure_modifier,
    {{ legacy_to_date('service_date') }}               as service_date,
    try_to_number(trim(units), 9, 2)                   as units,
    {{ to_amount('charge_amt') }}                      as charge_amt,
    {{ to_amount('allowed_amt') }}                     as allowed_amt,
    {{ to_amount('paid_amt') }}                        as paid_amt,
    {{ clean_code('line_status') }}                    as line_status,
    batch_id,
    src_file_name,
    src_row_num
from {{ source('legacy', 'src_claim_line') }}
where batch_id = '{{ var("batch_id") }}'
