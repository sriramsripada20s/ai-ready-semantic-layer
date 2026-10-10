-- Grain: one row per session. ENFORCED contract.
select
    cast(session_id as bigint) as session_id,
    cast(customer_id as bigint) as customer_id,
    cast(campaign_id as bigint) as campaign_id,
    cast(session_started_at as timestamp) as session_started_at,
    cast(session_date as date) as session_date,
    cast(traffic_source as varchar) as traffic_source,
    cast(device_type as varchar) as device_type
from {{ ref('stg_web_sessions') }}
