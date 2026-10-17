{#
  Claim headers: member / provider lookups (only LOADED members and providers
  can have claims), status crosswalk, date rules.
#}
with clm as (
    select
        c.*,
        row_number() over (partition by claim_id order by src_row_num) as dup_rank
    from {{ ref('stg_legacy__claim_header') }} c
),

mem as (
    select member_id, reject_reason as member_reject_reason, meme_ck, sbsb_ck, grgr_ck
    from {{ ref('int_member_prepared') }}
    where dup_rank = 1
),

prov as (
    select provider_id, reject_reason as provider_reject_reason
    from {{ ref('int_provider_prepared') }}
    where dup_rank = 1
),

sts as (
    select src_status, facets_status from {{ ref('xwalk_claim_status') }} where status_level = 'CLAIM'
),

ctype as (
    select config_value from {{ ref('config_valid_values') }} where config_type = 'VALID_CLAIM_TYPE'
),

checked as (
    select
        clm.*,
        mem.meme_ck,
        mem.sbsb_ck,
        mem.grgr_ck,
        sts.facets_status,
        case
            when clm.claim_id is null                          then 'CLAIM_ID_MISSING'
            when clm.dup_rank > 1                              then 'DUPLICATE_SOURCE_RECORD'
            when mem.member_id is null                         then 'MEMBER_NOT_FOUND'
            when mem.member_reject_reason is not null          then 'MEMBER_NOT_LOADED'
            when prov.provider_id is null                      then 'PROVIDER_NOT_FOUND'
            when prov.provider_reject_reason is not null       then 'PROVIDER_NOT_LOADED'
            when sts.facets_status is null                     then 'CLAIM_STATUS_XWALK_NOT_FOUND'
            when ctype.config_value is null                    then 'INVALID_CLAIM_TYPE'
            when clm.service_from_date is null
              or clm.service_to_date is null                   then 'SERVICE_DATE_INVALID'
            when clm.service_from_date > clm.service_to_date   then 'SERVICE_FROM_AFTER_TO'
            when clm.total_charge_amt is null                  then 'CHARGE_AMOUNT_INVALID'
        end as reject_reason
    from clm
    left join mem   on clm.member_id    = mem.member_id
    left join prov  on clm.provider_id  = prov.provider_id
    left join sts   on clm.claim_status = sts.src_status
    left join ctype on clm.claim_type   = ctype.config_value
)

select
    checked.*,
    'CV' || claim_id as clcl_id     -- new 12-character Facets claim id, legacy id kept for lineage
from checked
