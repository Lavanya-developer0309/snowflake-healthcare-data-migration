-- Facets-like CLAIM LINE table (accepted lines of accepted claims)
select
    clcl_id::varchar(12)                    as clcl_id,
    line_number::number(4,0)                as cdml_seq_no,
    procedure_code::varchar(8)              as ipcd_id,
    procedure_modifier::varchar(2)          as cdml_ipcd_mod,
    service_date::date                      as cdml_from_dt,
    units::number(9,2)                      as cdml_units,
    charge_amt::number(12,2)                as cdml_chg_amt,
    allowed_amt::number(12,2)               as cdml_allow,
    paid_amt::number(12,2)                  as cdml_paid_amt,
    facets_status::varchar(2)               as cdml_cur_sts,
    warning_code::varchar(50)               as mig_warning_code,
    (claim_id || '-' || line_number)::varchar(50) as mig_legacy_key,
    batch_id::varchar(50)                   as mig_batch_id,
    current_timestamp()::timestamp_ntz      as mig_load_ts
from {{ ref('int_claim_line_prepared') }}
where reject_reason is null
