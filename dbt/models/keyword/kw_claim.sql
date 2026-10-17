{{ config(post_hook="{{ unload_keyword_file('CLAIM') }}") }}
-- depends_on: {{ ref('cmc_clcl_claim') }}
-- Keyword records for CLAIM; post-hook writes @AUDIT.KEYWORD_STAGE/<batch>/KW_CLAIM.txt
{{ build_keyword_records(ref('cmc_clcl_claim'), 'CLAIM') }}
