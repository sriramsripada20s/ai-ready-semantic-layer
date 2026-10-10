-- Grain: one row per order line. Logic lives in int_order_lines_priced;
-- this mart only publishes it with explicit types (enforced contract).
select
    cast(order_item_id as bigint) as order_item_id,
    cast(order_id as bigint) as order_id,
    cast(line_number as integer) as line_number,
    cast(product_id as bigint) as product_id,
    cast(customer_id as bigint) as customer_id,
    cast(order_date as date) as order_date,
    cast(order_status as varchar) as order_status,
    cast(sales_channel as varchar) as sales_channel,
    cast(quantity as integer) as quantity,
    cast(unit_price as decimal(12, 2)) as unit_price,
    cast(unit_cost as decimal(12, 2)) as unit_cost,
    cast(discount_pct as decimal(5, 4)) as discount_pct,
    cast(line_gross_amount as decimal(14, 2)) as line_gross_amount,
    cast(line_discount_amount as decimal(14, 2)) as line_discount_amount,
    cast(line_net_amount as decimal(14, 2)) as line_net_amount,
    cast(line_cost_amount as decimal(14, 2)) as line_cost_amount
from {{ ref('int_order_lines_priced') }}
