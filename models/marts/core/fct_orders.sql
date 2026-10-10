-- Grain: one row per order. All logic (dedupe, recognition rule, first order,
-- attribution, line totals) lives in int_orders_enriched; this mart only publishes
-- it with explicit types, because it has an ENFORCED contract.
select
    cast(order_id as bigint) as order_id,
    cast(customer_id as bigint) as customer_id,
    cast(session_id as bigint) as session_id,
    cast(campaign_id as bigint) as campaign_id,
    cast(ordered_at as timestamp) as ordered_at,
    cast(order_date as date) as order_date,
    cast(order_status as varchar) as order_status,
    cast(sales_channel as varchar) as sales_channel,
    cast(promo_code as varchar) as promo_code,
    cast(is_recognized as boolean) as is_recognized,
    cast(is_first_order as boolean) as is_first_order,
    cast(units as bigint) as units,
    cast(gross_amount as decimal(14, 2)) as gross_amount,
    cast(discount_amount as decimal(14, 2)) as discount_amount,
    cast(net_amount as decimal(14, 2)) as net_amount,
    cast(cost_amount as decimal(14, 2)) as cost_amount,
    cast(gross_profit as decimal(14, 2)) as gross_profit
from {{ ref('int_orders_enriched') }}
