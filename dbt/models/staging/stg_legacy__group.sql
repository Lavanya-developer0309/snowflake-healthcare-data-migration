-- Cleansed + typed employer groups for the current batch
select
    {{ clean_code('group_number') }}        as group_number,
    {{ clean_text('group_name') }}          as group_name,
    {{ clean_code('lob_code') }}            as lob_code,
    {{ clean_code('group_status') }}        as group_status,
    group_eff_date                          as group_eff_date_raw,
    {{ legacy_to_date('group_eff_date') }}  as group_eff_date,
    {{ legacy_to_date('group_term_date') }} as group_term_date,
    {{ clean_text('address_line1') }}       as address_line1,
    {{ clean_text('city') }}                as city,
    {{ clean_code('state') }}               as state,
    {{ digits_only('zip_code') }}           as zip_code,
    {{ digits_only('phone') }}              as phone,
    batch_id,
    src_file_name,
    src_row_num
from {{ source('legacy', 'src_group') }}
where batch_id = '{{ var("batch_id") }}'
