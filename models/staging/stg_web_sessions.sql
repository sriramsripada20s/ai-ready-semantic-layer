-- Cleaned web sessions: one row per session.
-- No issues were injected here (snowflake/02b_inject_data_issues.sql); the only fix is the campaign_id type.
with source as (
    select * from {{ source('ecom', 'web_sessions') }}
),

-- No duplicates today (single load), but the loader re-sends rows (see orders [1]).
-- Keep the LATEST loaded version, same rule as the other staging models.
deduplicated as (
    select *
    from source
    qualify row_number() over (partition by session_id order by _loaded_at desc) = 1
)

select
    session_id,
    customer_id,
    cast(session_started_at as timestamp) as session_started_at,
    cast(session_started_at as date) as session_date,
    traffic_source,
    -- campaign_id arrives as FLOAT (all whole numbers): cast to integer so it joins cleanly to campaigns.
    -- NULL is expected: organic_search and direct traffic has no campaign.
    cast(campaign_id as integer) as campaign_id,
    device_type
from deduplicated
