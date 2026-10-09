-- Cleaned products: one row per product.
-- No issues were injected here (snowflake/02b_inject_data_issues.sql); the only fix is money types.
with source as (
    select * from {{ source('ecom', 'products') }}
),

-- No duplicates today (single load), but the loader re-sends rows (see orders [1]).
-- Keep the LATEST loaded version, same rule as the other staging models.
deduplicated as (
    select *
    from source
    qualify row_number() over (partition by product_id order by _loaded_at desc) = 1
)

select
    product_id,
    product_name,
    category,
    brand,
    -- Money arrives as FLOAT: cast to fixed-point so sums don't pick up rounding noise
    cast(list_price as decimal(10, 2))  as list_price,
    cast(unit_cost as decimal(10, 2))   as unit_cost
from deduplicated
