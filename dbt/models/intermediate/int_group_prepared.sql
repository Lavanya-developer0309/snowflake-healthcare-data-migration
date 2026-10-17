{#
  Groups: apply business rules, decide accept / reject, assign GRGR_CK.
  Every source row comes out of this model exactly once, with either
  reject_reason = NULL (will be loaded) or the FIRST rule it failed.
#}
with grp as (
    select
        g.*,
        row_number() over (partition by group_number order by src_row_num) as dup_rank
    from {{ ref('stg_legacy__group') }} g
),

lob as (
    select config_value from {{ ref('config_valid_values') }} where config_type = 'VALID_LOB'
),

st as (
    select config_value from {{ ref('config_valid_values') }} where config_type = 'VALID_STATE'
),

checked as (
    select
        grp.*,
        case
            when grp.group_number is null              then 'GROUP_NUMBER_MISSING'
            when grp.dup_rank > 1                      then 'DUPLICATE_SOURCE_RECORD'
            when lob.config_value is null              then 'INVALID_LOB_CODE'
            when grp.group_eff_date is null            then 'GROUP_EFF_DATE_INVALID'
            when grp.group_term_date < grp.group_eff_date then 'GROUP_TERM_BEFORE_EFF'
            when st.config_value is null               then 'INVALID_STATE_CODE'
        end as reject_reason,
        -- warning-level rule: name is mandatory in Facets, default it instead of rejecting
        iff(grp.group_name is null, 'GROUP_NAME_DEFAULTED', null) as warning_code
    from grp
    left join lob on grp.lob_code = lob.config_value
    left join st  on grp.state    = st.config_value
)

select
    checked.*,
    case when reject_reason is null then
        {{ var('grgr_ck_start') }} + row_number() over (
            partition by iff(reject_reason is null, 1, 0) order by group_number)
    end as grgr_ck
from checked
