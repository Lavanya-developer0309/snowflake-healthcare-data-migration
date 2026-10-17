{{ config(post_hook="{{ unload_keyword_file('ELIGIBILITY') }}") }}
-- depends_on: {{ ref('cmc_mepe_prcs_elig') }}
-- Keyword records for ELIGIBILITY; post-hook writes @AUDIT.KEYWORD_STAGE/<batch>/KW_ELIGIBILITY.txt
{{ build_keyword_records(ref('cmc_mepe_prcs_elig'), 'ELIGIBILITY') }}
