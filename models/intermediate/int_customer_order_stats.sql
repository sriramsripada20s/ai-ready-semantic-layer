-- Grain: one row per customer who has ordered (changes grain: orders -> customer).
-- Lifetime order behaviour, used by dim_customers to assign the current segment.
select
    customer_id,
    min(order_date)                                              as first_order_date,
    count(*)                                                     as lifetime_orders,           -- every order counts
    sum(case when is_recognized then net_amount else 0 end)      as lifetime_net_revenue       -- only recognized revenue
from {{ ref('int_orders_enriched') }}
group by 1