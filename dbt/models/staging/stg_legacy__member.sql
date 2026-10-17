-- Cleansed + typed members (subscribers and dependents) for the current batch
select
    {{ clean_code('member_id') }}               as member_id,
    {{ clean_code('subscriber_id') }}           as subscriber_id,
    {{ clean_code('relationship_code') }}       as relationship_code,
    {{ clean_name('first_name') }}              as first_name,
    {{ clean_name('last_name') }}               as last_name,
    left({{ clean_name('middle_initial') }}, 1) as middle_initial,
    date_of_birth                               as date_of_birth_raw,
    {{ legacy_to_date('date_of_birth') }}       as date_of_birth,
    {{ clean_code('gender_code') }}             as gender_code,
    -- SSN: keep digits only; anything that is not 9 digits becomes NULL (warning, not reject)
    iff(length({{ digits_only('ssn') }}) = 9, {{ digits_only('ssn') }}, null) as ssn,
    {{ clean_text('address_line1') }}           as address_line1,
    {{ clean_text('city') }}                    as city,
    {{ clean_code('state') }}                   as state,
    {{ digits_only('zip_code') }}               as zip_code,
    {{ digits_only('phone') }}                  as phone,
    {{ clean_code('group_number') }}            as group_number,
    {{ clean_code('plan_code') }}               as plan_code,
    coverage_eff_date                           as coverage_eff_date_raw,
    {{ legacy_to_date('coverage_eff_date') }}   as coverage_eff_date,
    coalesce({{ legacy_to_date('coverage_term_date') }}, '9999-12-31'::date) as coverage_term_date,
    batch_id,
    src_file_name,
    src_row_num
from {{ source('legacy', 'src_member') }}
where batch_id = '{{ var("batch_id") }}'
