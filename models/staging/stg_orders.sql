-- Cleaned orders: one row per order.
-- Each rule fixes an issue injected by snowflake/02b_inject_data_issues.sql [#n].
with source as (
    select * from {{ source('ecom', 'orders') }}
),

-- [1] The loader re-sends orders. Keep the LATEST loaded version:
--     a reload can carry a newer status (placed -> shipped), so "first" would be wrong.
deduplicated as (
    select *
    from source
    qualify row_number() over (partition by order_id order by _loaded_at desc) = 1
),

cleaned as (
    select
        order_id,
        customer_id,
        session_id,
        -- [10] device clock bug: orders dated in the future are
        -- shifted back exactly one year so they land on the real date
        case
            when ordered_at > _loaded_at then dateadd(year, -1, ordered_at)
            else ordered_at
        end as ordered_at,
        -- [2] Casing, stray spaces and one synonym ('complete') from older app versions
        case lower(trim(status))
            when 'complete' then 'completed'
            else lower(trim(status))
        end as order_status,
        sales_channel,
        -- [11] Promo codes typed by users: 'save10 ' -> 'SAVE10'; empty -> NULL
        nullif(upper(trim(promo_code)), '') as promo_code,
        item_count
    from deduplicated
)

select
    order_id,
    customer_id,
    session_id,
    cast(ordered_at as timestamp) as ordered_at,
    cast(ordered_at as date) as order_date,
    order_status,
    sales_channel,
    promo_code,
    item_count
from cleaned
