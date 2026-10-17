{{ config(post_hook=[
    "{{ apply_masking('SBSB_FIRST_NAME', 'MP_MASK_NAME') }}",
    "{{ apply_masking('SBSB_LAST_NAME', 'MP_MASK_NAME') }}"
]) }}
-- Facets-like SUBSCRIBER table (one row per accepted subscriber)
select
    sbsb_ck::number(10,0)                   as sbsb_ck,
    member_id::varchar(9)                   as sbsb_id,
    grgr_ck::number(10,0)                   as grgr_ck,
    last_name::varchar(35)                  as sbsb_last_name,
    first_name::varchar(15)                 as sbsb_first_name,
    middle_initial::varchar(1)              as sbsb_mid_init,
    coverage_eff_date::date                 as sbsb_orig_eff_dt,
    address_line1::varchar(40)              as sbsb_addr1,
    city::varchar(19)                       as sbsb_city,
    state::varchar(2)                       as sbsb_state,
    zip_code::varchar(11)                   as sbsb_zip,
    phone::varchar(20)                      as sbsb_phone,
    member_id::varchar(50)                  as mig_legacy_key,
    batch_id::varchar(50)                   as mig_batch_id,
    current_timestamp()::timestamp_ntz      as mig_load_ts
from {{ ref('int_member_prepared') }}
where reject_reason is null
  and relationship_code = '18'
