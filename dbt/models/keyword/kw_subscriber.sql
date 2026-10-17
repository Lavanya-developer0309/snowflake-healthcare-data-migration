{{ config(post_hook="{{ unload_keyword_file('SUBSCRIBER') }}") }}
-- depends_on: {{ ref('cmc_sbsb_subsc') }}
-- Keyword records for SUBSCRIBER; post-hook writes @AUDIT.KEYWORD_STAGE/<batch>/KW_SUBSCRIBER.txt
{{ build_keyword_records(ref('cmc_sbsb_subsc'), 'SUBSCRIBER') }}
