-- Grain: one row per customer. No PII (name/email stay in staging, masked).
-- Every column is cast explicitly: this model has an ENFORCED contract.
with customers as (
    select * from {{ ref('stg_customers') }}
),

regions as (
    select * from {{ ref('country_regions') }}
),

order_stats as (
    select * from {{ ref('int_customer_order_stats') }}
)

select
    cast(customers.customer_id         as bigint)  as customer_id,
    cast(customers.country_code        as varchar) as country_code,
    cast(regions.country_name          as varchar) as country_name,
    cast(regions.region                as varchar) as region,
    cast(customers.acquisition_channel as varchar) as acquisition_channel,
    cast(customers.signup_date         as date)    as signup_date,
    cast(order_stats.first_order_date  as date)    as first_order_date,
    cast(coalesce(order_stats.lifetime_orders, 0) as bigint)                  as lifetime_orders,
    cast(coalesce(order_stats.lifetime_net_revenue, 0) as decimal(14, 2))     as lifetime_net_revenue,
    cast(case
        when coalesce(order_stats.lifetime_orders, 0) = 0 then 'prospect'
        when order_stats.lifetime_orders = 1              then 'one_time'
        when order_stats.lifetime_orders < 15             then 'repeat'
        else 'loyal'
    end as varchar)                                                           as customer_segment,
    -- [6] soft-deleted customers are kept (their orders still need a customer), just flagged
    cast(coalesce(customers.is_deleted, false) as boolean)                    as is_deleted
from customers
left join regions     on regions.country_code    = customers.country_code
left join order_stats on order_stats.customer_id = customers.customer_id
-- [5] QA test accounts never reach the marts (they would inflate signups and prospects)
where not coalesce(customers.is_test_account, false)