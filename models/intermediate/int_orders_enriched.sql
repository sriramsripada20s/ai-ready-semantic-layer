-- Grain: one row per order (changes grain: order lines are summed up to the order).
-- Adds the business rules every order-level mart needs: revenue recognition,
-- first-order flag and last-touch campaign attribution.
with orders as (
    select * from {{ ref('stg_orders') }}
),

sessions as (
    select
        session_id,
        campaign_id
    from {{ ref('stg_web_sessions') }}
),

line_totals as (
    select
        order_id,
        sum(quantity) as units,
        sum(line_gross_amount) as gross_amount,
        sum(line_discount_amount) as discount_amount,
        sum(line_net_amount) as net_amount,
        sum(line_cost_amount) as cost_amount
    from {{ ref('int_order_lines_priced') }}
    group by 1
)

select
    orders.order_id,
    orders.customer_id,
    orders.session_id,
    -- last touch: campaign behind the order's session
    sessions.campaign_id,
    orders.ordered_at,
    orders.order_date,
    orders.order_status,
    orders.sales_channel,
    coalesce(orders.promo_code, 'none') as promo_code,
    orders.order_status in ('completed', 'shipped') as is_recognized,   -- revenue rule, decided once
    row_number() over (
        partition by orders.customer_id order by orders.ordered_at, orders.order_id
    ) = 1 as is_first_order,
    line_totals.units,
    line_totals.gross_amount,
    line_totals.discount_amount,
    line_totals.net_amount,
    line_totals.cost_amount,
    line_totals.net_amount - line_totals.cost_amount as gross_profit
from orders
inner join line_totals on orders.order_id = line_totals.order_id
left join sessions on orders.session_id = sessions.session_id
