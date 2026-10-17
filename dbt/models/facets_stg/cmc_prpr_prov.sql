-- Facets-like PROVIDER table (accepted providers)
select
    provider_id::varchar(12)                as prpr_id,
    npi::varchar(10)                        as prpr_npi,
    prpr_entity::varchar(1)                 as prpr_entity,
    provider_name::varchar(55)              as prpr_name,
    specialty_code::varchar(10)             as prpr_mctr_spec,
    tax_id::varchar(9)                      as mctn_id,
    address_line1::varchar(40)              as prad_addr1,
    city::varchar(19)                       as prad_city,
    state::varchar(2)                       as prad_state,
    zip_code::varchar(11)                   as prad_zip,
    par_ind::varchar(1)                     as prpr_par_ind,
    provider_eff_date::date                 as prpr_eff_dt,
    warning_code::varchar(50)               as mig_warning_code,
    provider_id::varchar(50)                as mig_legacy_key,
    batch_id::varchar(50)                   as mig_batch_id,
    current_timestamp()::timestamp_ntz      as mig_load_ts
from {{ ref('int_provider_prepared') }}
where reject_reason is null
