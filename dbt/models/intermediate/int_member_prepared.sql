{#
  Members: crosswalks (gender, relationship, plan), business rules, reject
  cascade (dependents follow their subscriber), and contrived keys:
     SBSB_CK  - one per accepted subscriber
     MEME_CK  - one per accepted member
     MEME_SFX - 0 = subscriber, 1.. = spouse first, then dependents by age
#}
with mem as (
    select
        m.*,
        row_number() over (partition by member_id order by src_row_num) as dup_rank
    from {{ ref('stg_legacy__member') }} m
),

grp_all as (
    select group_number, reject_reason as group_reject_reason, grgr_ck, lob_code as group_lob_code
    from {{ ref('int_group_prepared') }}
    where dup_rank = 1
),

joined as (
    select
        mem.*,
        g.group_number          as group_found,
        g.group_reject_reason,
        g.grgr_ck,
        g.group_lob_code,
        xg.facets_sex,
        xr.facets_rel,
        xp.pdpd_id,
        xp.cspi_id,
        xp.lob_code             as plan_lob_code
    from mem
    left join grp_all                           g  on mem.group_number      = g.group_number
    left join {{ ref('xwalk_gender') }}         xg on mem.gender_code       = xg.src_gender_code
    left join {{ ref('xwalk_relationship') }}   xr on mem.relationship_code = xr.src_relationship_code
    left join {{ ref('xwalk_plan') }}           xp on mem.plan_code         = xp.src_plan_code
),

member_rules as (
    select
        joined.*,
        case
            when member_id is null                          then 'MEMBER_ID_MISSING'
            when dup_rank > 1                               then 'DUPLICATE_SOURCE_RECORD'
            when group_found is null                        then 'GROUP_NOT_FOUND'
            when group_reject_reason is not null            then 'GROUP_NOT_LOADED'
            when facets_rel is null                         then 'RELATIONSHIP_XWALK_NOT_FOUND'
            when facets_sex is null                         then 'GENDER_XWALK_NOT_FOUND'
            when date_of_birth_raw is null                  then 'DOB_MISSING'
            when date_of_birth is null                      then 'DOB_INVALID_DATE'
            when date_of_birth > current_date()             then 'DOB_IN_FUTURE'
            when pdpd_id is null                            then 'PLAN_XWALK_NOT_FOUND'
            when plan_lob_code <> group_lob_code            then 'PLAN_LOB_MISMATCH'
            when coverage_eff_date is null                  then 'COVERAGE_EFF_DATE_INVALID'
            when coverage_term_date < coverage_eff_date     then 'COVERAGE_TERM_BEFORE_EFF'
        end as member_reject_reason
    from joined
),

-- one row per subscriber (first occurrence) with its own outcome
subscriber_outcome as (
    select member_id as sub_member_id, member_reject_reason as subscriber_reject_reason
    from member_rules
    where relationship_code = '18' and dup_rank = 1
),

with_cascade as (
    select
        mr.*,
        coalesce(
            mr.member_reject_reason,
            case
                when mr.relationship_code <> '18' and so.sub_member_id is null      then 'SUBSCRIBER_NOT_FOUND'
                when mr.relationship_code <> '18' and so.subscriber_reject_reason is not null
                                                                                  then 'SUBSCRIBER_NOT_LOADED'
            end
        ) as reject_reason,
        iff(mr.ssn is null, 'SSN_MISSING_OR_INVALID', null) as warning_code
    from member_rules mr
    left join subscriber_outcome so on mr.subscriber_id = so.sub_member_id
),

accepted_subscribers as (
    select
        member_id as sub_member_id,
        {{ var('sbsb_ck_start') }} + row_number() over (order by member_id) as sbsb_ck
    from with_cascade
    where reject_reason is null and relationship_code = '18'
),

accepted_keys as (
    select
        w.member_id,
        {{ var('meme_ck_start') }} + row_number() over (order by w.member_id) as meme_ck,
        s.sbsb_ck,
        row_number() over (
            partition by w.subscriber_id
            order by case w.relationship_code when '18' then 0 when '01' then 1 else 2 end,
                     w.date_of_birth, w.member_id
        ) - 1 as meme_sfx
    from with_cascade w
    join accepted_subscribers s on w.subscriber_id = s.sub_member_id
    where w.reject_reason is null
)

select
    w.*,
    k.meme_ck,
    k.sbsb_ck,
    k.meme_sfx
from with_cascade w
left join accepted_keys k
       on w.member_id = k.member_id
      and w.reject_reason is null
