{#
  Claim lines: a line can only load if its claim header loads.
#}
with ln as (
    select
        l.*,
        row_number() over (partition by claim_id, line_number order by src_row_num) as dup_rank
    from {{ ref('stg_legacy__claim_line') }} l
),

hdr as (
    select claim_id, clcl_id, reject_reason as claim_reject_reason
    from {{ ref('int_claim_prepared') }}
    where dup_rank = 1
),

sts as (
    select src_status, facets_status from {{ ref('xwalk_claim_status') }} where status_level = 'LINE'
)

select
    ln.*,
    hdr.clcl_id,
    sts.facets_status,
    case
        when ln.claim_id is null or ln.line_number is null then 'CLAIM_LINE_KEY_MISSING'
        when ln.dup_rank > 1                               then 'DUPLICATE_SOURCE_RECORD'
        when hdr.claim_id is null                          then 'PARENT_CLAIM_NOT_FOUND'
        when hdr.claim_reject_reason is not null           then 'PARENT_CLAIM_NOT_LOADED'
        when sts.facets_status is null                     then 'LINE_STATUS_XWALK_NOT_FOUND'
        when ln.service_date is null                       then 'SERVICE_DATE_INVALID'
        when ln.units is null or ln.units <= 0             then 'UNITS_INVALID'
        when ln.charge_amt is null                         then 'CHARGE_AMOUNT_INVALID'
    end as reject_reason,
    iff(ln.paid_amt < 0, 'NEGATIVE_PAID_AMOUNT', null) as warning_code
from ln
left join hdr on ln.claim_id    = hdr.claim_id
left join sts on ln.line_status = sts.src_status
