{{ config(severity='warn') }}
-- Business-rule check: a claim's total charge must equal the sum of its line charges.
-- WARN only - differences are reported in the scorecard for the BA to review.
select
    c.clcl_id,
    c.clcl_tot_chg,
    sum(l.cdml_chg_amt) as line_total
from {{ ref('cmc_clcl_claim') }} c
join {{ ref('cmc_cdml_cl_line') }} l on c.clcl_id = l.clcl_id
group by c.clcl_id, c.clcl_tot_chg
having abs(c.clcl_tot_chg - sum(l.cdml_chg_amt)) > 0.01
