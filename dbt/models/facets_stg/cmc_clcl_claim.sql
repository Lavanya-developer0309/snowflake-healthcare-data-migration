-- Facets-like CLAIM HEADER table (accepted claims)
select
    clcl_id::varchar(12)                    as clcl_id,
    meme_ck::number(10,0)                   as meme_ck,
    sbsb_ck::number(10,0)                   as sbsb_ck,
    grgr_ck::number(10,0)                   as grgr_ck,
    provider_id::varchar(12)                as prpr_id,
    claim_type::varchar(1)                  as clcl_cl_type,
    facets_status::varchar(2)               as clcl_cur_sts,
    received_date::date                     as clcl_recd_dt,
    service_from_date::date                 as clcl_low_svc_dt,
    service_to_date::date                   as clcl_high_svc_dt,
    total_charge_amt::number(12,2)          as clcl_tot_chg,
    total_paid_amt::number(12,2)            as clcl_tot_payable,
    primary_diag_code::varchar(10)          as clcl_diag_cd1,
    secondary_diag_code::varchar(10)        as clcl_diag_cd2,
    claim_id::varchar(50)                   as mig_legacy_key,
    batch_id::varchar(50)                   as mig_batch_id,
    current_timestamp()::timestamp_ntz      as mig_load_ts
from {{ ref('int_claim_prepared') }}
where reject_reason is null
