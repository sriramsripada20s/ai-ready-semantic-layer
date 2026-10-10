-- Grain: one row per product, plus one Unknown member (-1).
select
    product_id,
    product_name,
    category,
    brand,
    list_price,
    unit_cost,
    case
        when list_price < 50  then 'budget'
        when list_price < 200 then 'mid'
        else 'premium'
    end as price_tier
from {{ ref('stg_products') }}

-- [9] Unknown member: order lines whose product isn't in the catalog yet (late-arriving
-- products) point here, so revenue stays whole and the relationships test passes.
union all
select
    -1                as product_id,
    'Unknown product' as product_name,
    'Unknown'         as category,
    'Unknown'         as brand,
    null              as list_price,
    null              as unit_cost,
    'unknown'         as price_tier