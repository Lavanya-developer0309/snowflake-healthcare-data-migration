{#
  Providers: validation rules + derived Facets provider attributes.
#}
with prov as (
    select
        p.*,
        row_number() over (partition by provider_id order by src_row_num) as dup_rank
    from {{ ref('stg_legacy__provider') }} p
),

cfg as (
    select config_type, config_value from {{ ref('config_valid_values') }}
),

checked as (
    select
        prov.*,
        case
            when prov.provider_id is null       then 'PROVIDER_ID_MISSING'
            when prov.dup_rank > 1              then 'DUPLICATE_SOURCE_RECORD'
            when typ.config_value is null       then 'INVALID_PROVIDER_TYPE'
            when st.config_value is null        then 'INVALID_STATE_CODE'
            when net.config_value is null       then 'INVALID_NETWORK_STATUS'
            when prov.provider_type = 'IND' and prov.last_name is null         then 'PROVIDER_NAME_MISSING'
            when prov.provider_type = 'ORG' and prov.organization_name is null then 'PROVIDER_NAME_MISSING'
        end as reject_reason,
        -- warning-level rule: an NPI must be 10 digits; load it but flag it
        iff(prov.npi is null or length(prov.npi) <> 10, 'NPI_INVALID_LENGTH', null) as warning_code
    from prov
    left join cfg typ on typ.config_type = 'VALID_PROVIDER_TYPE'  and prov.provider_type  = typ.config_value
    left join cfg st  on st.config_type  = 'VALID_STATE'          and prov.state          = st.config_value
    left join cfg net on net.config_type = 'VALID_NETWORK_STATUS' and prov.network_status = net.config_value
)

select
    checked.*,
    case provider_type when 'IND' then 'P' when 'ORG' then 'F' end            as prpr_entity,
    case provider_type
        when 'IND' then last_name || ', ' || coalesce(first_name, '')
        else organization_name
    end                                                                     as provider_name,
    iff(network_status = 'PAR', 'Y', 'N')                                   as par_ind
from checked
