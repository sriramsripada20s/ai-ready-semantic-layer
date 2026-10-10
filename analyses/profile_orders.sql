-- Profiling: RAW.ECOM.ORDERS
-- Compile:  dbt compile --select profile_orders
-- Then copy target/compiled/.../analyses/profile_orders.sql into Snowsight and Run All.

-- 1. Overview: size, key uniqueness, date range ----------------------------------
select
    count(*)                                        as total_rows,
    count(distinct order_id)                        as distinct_order_ids,
    count(*) - count(distinct order_id)             as duplicate_rows,
    count_if(order_id is null)                      as null_order_ids,
    min(ordered_at)                                 as first_order,
    max(ordered_at)                                 as last_order,
    count_if(ordered_at > _loaded_at)               as ordered_after_load,
    min(_loaded_at)                                 as first_load,
    max(_loaded_at)                                 as last_load
from {{ source('ecom', 'orders') }};

-- 2. Nulls per column -------------------------------------------------------------
select
    count(*)                                        as n,
    count_if(customer_id   is null)                 as customer_id_nulls,
    count_if(session_id    is null)                 as session_id_nulls,
    count_if(ordered_at    is null)                 as ordered_at_nulls,
    count_if(status        is null)                 as status_nulls,
    count_if(sales_channel is null)                 as sales_channel_nulls,
    count_if(promo_code    is null)                 as promo_code_nulls,
    count_if(item_count    is null)                 as item_count_nulls
from {{ source('ecom', 'orders') }};

-- 3. Duplicates: how do the copies differ? -----------------------------------------
select order_id, status, ordered_at, _loaded_at,
       count(*) over (partition by order_id) as copies
from {{ source('ecom', 'orders') }}
qualify count(*) over (partition by order_id) > 1
order by order_id, _loaded_at
limit 20;

-- 4. Status values (brackets reveal hidden spaces) ------------------------------------
select '[' || status || ']' as status_value, count(*) as n
from {{ source('ecom', 'orders') }}
group by 1 order by 2 desc;

-- 5. Promo code values --------------------------------------------------------------
select '[' || coalesce(promo_code, 'NULL') || ']' as promo_value, count(*) as n
from {{ source('ecom', 'orders') }}
group by 1 order by 2 desc;

-- 6. Sales channel values -------------------------------------------------------------
select sales_channel, count(*) as n
from {{ source('ecom', 'orders') }}
group by 1 order by 2 desc;

-- 7. Numeric range: items per order --------------------------------------------------
select min(item_count), max(item_count), avg(item_count)::number(5,2) as avg_items,
       count_if(item_count <= 0) as non_positive
from {{ source('ecom', 'orders') }};

-- 8. Future-dated orders: how far in the future? -------------------------------------
select order_id, ordered_at, _loaded_at,
       datediff(day, _loaded_at, ordered_at) as days_after_load
from {{ source('ecom', 'orders') }}
where ordered_at > _loaded_at
order by days_after_load desc
limit 10;

-- 9. Orphan keys: orders whose customer or session doesn't exist ---------------------
select
    count_if(c.customer_id is null) as orders_with_unknown_customer,
    count_if(s.session_id  is null) as orders_with_unknown_session
from {{ source('ecom', 'orders') }} o
left join {{ source('ecom', 'customers') }}    c on c.customer_id = o.customer_id
left join {{ source('ecom', 'web_sessions') }} s on s.session_id  = o.session_id;
