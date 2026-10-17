{{ config(post_hook="{{ unload_keyword_file('MEMBER') }}") }}
-- depends_on: {{ ref('cmc_meme_member') }}
-- Keyword records for MEMBER; post-hook writes @AUDIT.KEYWORD_STAGE/<batch>/KW_MEMBER.txt
{{ build_keyword_records(ref('cmc_meme_member'), 'MEMBER') }}
