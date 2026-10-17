{{ config(post_hook="{{ unload_keyword_file('CLAIM_LINE') }}") }}
-- depends_on: {{ ref('cmc_cdml_cl_line') }}
-- Keyword records for CLAIM_LINE; post-hook writes @AUDIT.KEYWORD_STAGE/<batch>/KW_CLAIM_LINE.txt
{{ build_keyword_records(ref('cmc_cdml_cl_line'), 'CLAIM_LINE') }}
