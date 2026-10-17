-- Facets-like MEMBER ELIGIBILITY table (one coverage span per accepted member)
select
    meme_ck::number(10,0)                   as meme_ck,
    sbsb_ck::number(10,0)                   as sbsb_ck,
    grgr_ck::number(10,0)                   as grgr_ck,
    coverage_eff_date::date                 as mepe_eff_dt,
    coverage_term_date::date                as mepe_term_dt,
    'Y'::varchar(1)                         as mepe_elig_ind,
    pdpd_id::varchar(10)                    as pdpd_id,
    cspi_id::varchar(8)                     as cspi_id,
    plan_lob_code::varchar(4)               as lobd_id,
    member_id::varchar(50)                  as mig_legacy_key,
    batch_id::varchar(50)                   as mig_batch_id,
    current_timestamp()::timestamp_ntz      as mig_load_ts
from {{ ref('int_member_prepared') }}
where reject_reason is null
