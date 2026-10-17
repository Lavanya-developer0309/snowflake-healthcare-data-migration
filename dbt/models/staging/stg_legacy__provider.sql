-- Cleansed + typed providers for the current batch
select
    {{ clean_code('provider_id') }}           as provider_id,
    {{ digits_only('npi') }}                  as npi,
    {{ clean_code('provider_type') }}         as provider_type,
    {{ clean_name('first_name') }}            as first_name,
    {{ clean_name('last_name') }}             as last_name,
    {{ clean_name('organization_name') }}     as organization_name,
    {{ clean_code('specialty_code') }}        as specialty_code,
    {{ digits_only('tax_id') }}               as tax_id,
    {{ clean_text('address_line1') }}         as address_line1,
    {{ clean_text('city') }}                  as city,
    {{ clean_code('state') }}                 as state,
    {{ digits_only('zip_code') }}             as zip_code,
    {{ clean_code('network_status') }}        as network_status,
    {{ legacy_to_date('provider_eff_date') }} as provider_eff_date,
    batch_id,
    src_file_name,
    src_row_num
from {{ source('legacy', 'src_provider') }}
where batch_id = '{{ var("batch_id") }}'
