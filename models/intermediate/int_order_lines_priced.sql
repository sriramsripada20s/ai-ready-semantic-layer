-- Grain: one row per order line.
-- The single place where line-level money is calculated. fct_order_items, fct_orders
-- (via int_orders_enriched) and bi_product_sales_monthly all inherit it, so "gross",
-- "discount" and "net" can never mean different things in different marts.
with items as (
    select * from {{ ref('stg_order_items') }}
),

orders as (
    select
        order_id,
        customer_id,
        order_date,
        order_status,
        sales_channel,
        promo_code
    from {{ ref('stg_orders') }}
),

products as (
    select
        product_id,
        list_price,
        unit_cost
    from {{ ref('stg_products') }}
),

promos as (
    select
        promo_code,
        discount_pct
    from {{ ref('promo_codes') }}
),

joined as (
    select
        items.order_item_id,
        items.order_id,
        items.line_number,
        -- [9] product not in the catalog yet -> 'Unknown product' member (-1), not dropped
        case when products.product_id is null then -1 else items.product_id end as product_id,
        orders.customer_id,
        orders.order_date,
        orders.order_status,
        orders.sales_channel,
        items.quantity,
        -- [7] price service outage -> fall back to the catalog list price
        coalesce(items.unit_price, products.list_price) as unit_price,
        -- unknown product -> unknown cost, counted as 0 until the product arrives
        coalesce(products.unit_cost, 0) as unit_cost,
        coalesce(promos.discount_pct, 0) as discount_pct
    from items
    inner join orders on items.order_id = orders.order_id
    left join products on items.product_id = products.product_id
    left join promos on orders.promo_code = promos.promo_code
)

select
    *,
    cast(quantity * unit_price as decimal(14, 2)) as line_gross_amount,
    cast(quantity * unit_price * discount_pct as decimal(14, 2)) as line_discount_amount,
    cast(quantity * unit_price * (1 - discount_pct) as decimal(14, 2)) as line_net_amount,
    cast(quantity * unit_cost as decimal(14, 2)) as line_cost_amount
from joined
