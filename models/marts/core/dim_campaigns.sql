-- Grain: one row per campaign flight.
select
    campaign_id,
    campaign_name,
    channel as campaign_channel,
    start_date,
    end_date,
    budget
from {{ ref('stg_campaigns') }}
