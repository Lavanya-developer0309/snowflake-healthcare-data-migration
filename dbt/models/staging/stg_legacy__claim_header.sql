-- Cleansed + typed claim headers for the current batch
select
    {{ clean_code('claim_id') }}              as claim_id,
    {{ clean_code('member_id') }}             as member_id,
    {{ clean_code('provider_id') }}           as provider_id,
    {{ clean_code('claim_type') }}            as claim_type,
    {{ clean_code('claim_status') }}          as claim_status,
    {{ legacy_to_date('received_date') }}     as received_date,
    service_from_date                         as service_from_date_raw,
    {{ legacy_to_date('service_from_date') }} as service_from_date,
    {{ legacy_to_date('service_to_date') }}   as service_to_date,
    {{ to_amount('total_charge_amt') }}       as total_charge_amt,
    {{ to_amount('total_paid_amt') }}         as total_paid_amt,
    {{ clean_code('primary_diag_code') }}     as primary_diag_code,
    {{ clean_code('secondary_diag_code') }}   as secondary_diag_code,
    batch_id,
    src_file_name,
    src_row_num
from {{ source('legacy', 'src_claim_header') }}
where batch_id = '{{ var("batch_id") }}'
