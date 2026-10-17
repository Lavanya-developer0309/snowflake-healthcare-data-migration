-- Facets rule: every subscriber must have exactly one member row with suffix 0 and relationship M
select s.sbsb_ck, count(m.meme_ck) as suffix_zero_rows
from {{ ref('cmc_sbsb_subsc') }} s
left join {{ ref('cmc_meme_member') }} m
       on s.sbsb_ck = m.sbsb_ck and m.meme_sfx = 0 and m.meme_rel = 'M'
group by s.sbsb_ck
having count(m.meme_ck) <> 1
