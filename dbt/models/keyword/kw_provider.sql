{{ config(post_hook="{{ unload_keyword_file('PROVIDER') }}") }}
-- depends_on: {{ ref('cmc_prpr_prov') }}
-- Keyword records for PROVIDER; post-hook writes @AUDIT.KEYWORD_STAGE/<batch>/KW_PROVIDER.txt
{{ build_keyword_records(ref('cmc_prpr_prov'), 'PROVIDER') }}
