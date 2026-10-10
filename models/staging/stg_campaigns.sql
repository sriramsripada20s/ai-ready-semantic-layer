-- Cleaned campaigns: one row per campaign flight (3 paid channels x 12 quarterly flights).
-- Each rule fixes an issue injected by snowflake/02b_inject_data_issues.sql [#n].
with source as (
    select * from {{ source('ecom', 'campaigns') }}
),

-- No duplicates today (single load), but the loader re-sends rows (see orders [1]).
-- Keep the LATEST loaded version, same rule as the other staging models.
deduplicated as (
    select *
    from source
    qualify row_number() over (partition by campaign_id order by _loaded_at desc) = 1
)

select
    campaign_id,
    campaign_name,
    channel,
    cast(start_date as date) as start_date,
    cast(end_date as date) as end_date,
    -- [12] Budget exported from a spreadsheet as text ('$2,450,000.00'):
    --      strip '$' and ',' then cast. try_cast returns NULL on a bad value; the not_null test catches it.
    try_cast(replace(replace(budget, '$', ''), ',', '') as decimal(14, 2)) as budget
from deduplicated
