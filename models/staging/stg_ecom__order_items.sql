-- Cleaned order lines: one row per real sales line.
-- Each rule fixes an issue injected by snowflake/02b_inject_data_issues.sql [#n].
with source as (
    select * from {{ source('ecom', 'order_items') }}
),

-- No duplicates today, but the loader re-sends rows (see orders [1]).
-- Keep the LATEST loaded version, same rule as the other staging models.
deduplicated as (
    select *
    from source
    qualify row_number() over (partition by order_item_id order by _loaded_at desc) = 1
),

-- [8] 300 lines with quantity 0 or -1 (all line_number 9) are not sales lines:
--     they break orders.item_count, and returns are tracked by order_status = 'returned'.
--     Excluded here so they can never reach revenue.
sales_lines as (
    select *
    from deduplicated
    where quantity > 0
)

select
    order_item_id,
    order_id,
    line_number,
    -- [9] 1,000 lines point at product 1002 that doesn't exist yet (late product feed):
    --     kept, reported by a warn-level relationships test
    product_id,
    quantity,
    -- Money arrives as FLOAT: cast to fixed-point so sums don't pick up rounding noise
    -- [7] 6,250 NULL prices (price service outage): kept NULL here,
    --     backfilled from products.list_price in the intermediate layer
    cast(unit_price as decimal(10, 2))  as unit_price,
    unit_price is null                  as has_missing_price
from sales_lines
