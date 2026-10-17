{{ config(post_hook="{{ unload_keyword_file('GROUP') }}") }}
-- depends_on: {{ ref('cmc_grgr_group') }}
-- Keyword records for GROUP; post-hook writes @AUDIT.KEYWORD_STAGE/<batch>/KW_GROUP.txt
{{ build_keyword_records(ref('cmc_grgr_group'), 'GROUP') }}
