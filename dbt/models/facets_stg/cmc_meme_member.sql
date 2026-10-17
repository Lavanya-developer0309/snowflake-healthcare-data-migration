{{ config(post_hook=[
    "{{ apply_masking('MEME_SSN', 'MP_MASK_SSN') }}",
    "{{ apply_masking('MEME_BIRTH_DT', 'MP_MASK_DOB') }}",
    "{{ apply_masking('MEME_FIRST_NAME', 'MP_MASK_NAME') }}",
    "{{ apply_masking('MEME_LAST_NAME', 'MP_MASK_NAME') }}"
]) }}
-- Facets-like MEMBER table (accepted subscribers + dependents)
select
    meme_ck::number(10,0)                   as meme_ck,
    sbsb_ck::number(10,0)                   as sbsb_ck,
    grgr_ck::number(10,0)                   as grgr_ck,
    meme_sfx::number(3,0)                   as meme_sfx,
    facets_rel::varchar(1)                  as meme_rel,
    last_name::varchar(35)                  as meme_last_name,
    first_name::varchar(15)                 as meme_first_name,
    middle_initial::varchar(1)              as meme_mid_init,
    date_of_birth::date                     as meme_birth_dt,
    facets_sex::varchar(1)                  as meme_sex,
    ssn::varchar                            as meme_ssn,          -- no length: masked value XXX-XX-9999 is longer than 9
    member_id::varchar(20)                  as meme_legacy_id,
    member_id::varchar(50)                  as mig_legacy_key,
    batch_id::varchar(50)                   as mig_batch_id,
    current_timestamp()::timestamp_ntz      as mig_load_ts
from {{ ref('int_member_prepared') }}
where reject_reason is null
