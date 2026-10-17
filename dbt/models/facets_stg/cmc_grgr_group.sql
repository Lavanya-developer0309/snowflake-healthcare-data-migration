-- Facets-like GROUP table (accepted groups only)
select
    grgr_ck::number(10,0)                                      as grgr_ck,
    group_number::varchar(8)                                   as grgr_id,
    coalesce(group_name, 'GROUP ' || group_number)::varchar(50) as grgr_name,
    coalesce(group_status, 'A')::varchar(1)                    as grgr_sts,
    lob_code::varchar(4)                                       as lobd_id,
    group_eff_date::date                                       as grgr_orig_eff_dt,
    coalesce(group_term_date, '9999-12-31'::date)::date        as grgr_term_dt,
    address_line1::varchar(40)                                 as grgr_addr1,
    city::varchar(19)                                          as grgr_city,
    state::varchar(2)                                          as grgr_state,
    zip_code::varchar(11)                                      as grgr_zip,
    phone::varchar(20)                                         as grgr_phone,
    -- migration lineage
    group_number::varchar(50)                                  as mig_legacy_key,
    batch_id::varchar(50)                                      as mig_batch_id,
    current_timestamp()::timestamp_ntz                         as mig_load_ts
from {{ ref('int_group_prepared') }}
where reject_reason is null
