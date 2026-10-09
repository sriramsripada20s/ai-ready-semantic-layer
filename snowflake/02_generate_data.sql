-- =============================================================================
-- 02_generate_data.sql  â€”  synthetic e-commerce data, generated inside Snowflake
--
--   raw.ecom.customers      100,000 rows
--   raw.ecom.products         1,000 rows
--   raw.ecom.campaigns           36 rows   (3 paid channels x 12 quarterly flights)
--   raw.ecom.web_sessions 2,500,000 rows   (paid sessions carry a campaign_id)
--   raw.ecom.orders       1,000,000 rows   (weighted sample of sessions -> real funnel)
--   raw.ecom.order_items ~2,500,000 rows   (1-4 lines per order)
--
-- Window: the 1,095 days ending YESTERDAY (relative to when you run it), so the
-- data behaves like a live feed. Signups and traffic grow over time.
-- Runtime on an XSMALL warehouse: ~1-2 minutes.
-- =============================================================================

use role transformer;
use warehouse transforming;
use schema raw.ecom;

-- 1. Customers -----------------------------------------------------------------
create or replace table raw.ecom.customers as
with c as (
    select
        row_number() over (order by seq4())      as customer_id,
        uniform(0, 11, random())                 as r_country,
        uniform(1, 100, random())                as r_channel
    from table(generator(rowcount => 100000))
)
select
    customer_id,
    'Customer ' || customer_id                                   as full_name,
    'customer' || customer_id || '@example.com'                  as email,
    get(array_construct('US','US','US','CA','GB','DE','FR','IN','IN','BR','MX','AU'),
        r_country)::varchar                                      as country_code,
    case
        when r_channel <= 40 then 'organic'
        when r_channel <= 65 then 'paid_search'
        when r_channel <= 85 then 'social'
        else 'referral'
    end                                                          as acquisition_channel,
    -- signups accelerate over time; customer_id is in signup order
    dateadd(day, floor(1095 * sqrt((customer_id - 1) / 100000)), dateadd(day, -1095, current_date())) as signup_date,
    current_timestamp()                                          as _loaded_at
from c;

-- 2. Products ------------------------------------------------------------------
create or replace table raw.ecom.products as
with p as (
    select
        row_number() over (order by seq4())          as product_id,
        uniform(0, 7, random())                      as r_category,
        uniform(0, 5, random())                      as r_brand,
        round(uniform(5::float, 400::float, random()), 2) as list_price,
        uniform(0.35::float, 0.70::float, random())  as cost_ratio
    from table(generator(rowcount => 1000))
)
select
    product_id,
    get(array_construct('Electronics','Home','Apparel','Beauty','Sports','Toys','Books','Grocery'),
        r_category)::varchar || ' item ' || product_id          as product_name,
    get(array_construct('Electronics','Home','Apparel','Beauty','Sports','Toys','Books','Grocery'),
        r_category)::varchar                                    as category,
    get(array_construct('Acme','Globex','Initech','Umbrella','Stark','Wayne'),
        r_brand)::varchar                                       as brand,
    list_price,
    round(list_price * cost_ratio, 2)                           as unit_cost,
    current_timestamp()                                         as _loaded_at
from p;

-- 3. Web sessions (always on/after the customer's signup date) -------------------
create or replace table raw.ecom.web_sessions as
with s as (
    select
        row_number() over (order by seq4())      as session_id,
        least(1094, floor(1095 * power(uniform(0::float, 1::float, random()), 0.75))) as day_offset,  -- traffic grows over time
        uniform(0::float, 1::float, random())    as r_cust,
        uniform(0, 86399, random())              as r_sec,
        uniform(1, 100, random())                as r_src,
        uniform(1, 100, random())                as r_dev
    from table(generator(rowcount => 2500000))
),
s2 as (
    select *,
        case
            when r_src <= 35 then 'organic_search'
            when r_src <= 55 then 'paid_search'
            when r_src <= 70 then 'email'
            when r_src <= 85 then 'social'
            else 'direct'
        end as traffic_source
    from s
)
select
    s.session_id,
    c.customer_id,
    dateadd(second, s.r_sec,
        dateadd(day, s.day_offset, dateadd(day, -1095, current_date())::timestamp_ntz)) as session_started_at,
    s.traffic_source,
    -- paid channels run one campaign "flight" per 92 days: id = channel*100 + flight
    case s.traffic_source
        when 'paid_search' then 100 when 'email' then 200 when 'social' then 300
    end + floor(s.day_offset / 92)                              as campaign_id,
    case
        when s.r_dev <= 55 then 'mobile'
        when s.r_dev <= 90 then 'desktop'
        else 'tablet'
    end                                                         as device_type,
    current_timestamp()                                         as _loaded_at
from s2 s
-- pick a customer who had already signed up by the session day,
-- skewed toward recent signups (older customers gradually go quiet)
join raw.ecom.customers c
  on c.customer_id = greatest(1, floor(power(s.r_cust, 0.35) * 100000 * power(s.day_offset / 1095, 2)));

-- 4. Campaigns: 3 paid channels x 12 flights of 92 days --------------------------
create or replace table raw.ecom.campaigns as
select
    ch.channel_code * 100 + fl.flight                           as campaign_id,
    upper(ch.channel) || '_FLIGHT_' || lpad((fl.flight + 1)::varchar, 2, '0') as campaign_name,
    ch.channel,
    dateadd(day, fl.flight * 92, dateadd(day, -1095, current_date()))       as start_date,
    least(dateadd(day, fl.flight * 92 + 91, dateadd(day, -1095, current_date())),
          dateadd(day, -1, current_date()))                    as end_date,
    round(uniform(1500000::float, 4500000::float, random()), 2) as budget,
    current_timestamp()                                         as _loaded_at
from (values (1, 'paid_search'), (2, 'email'), (3, 'social')) as ch(channel_code, channel)
cross join (
    select row_number() over (order by seq4()) - 1 as flight
    from table(generator(rowcount => 12))
) fl;

-- 5. Orders: weighted sample of 1M converting sessions ---------------------------
-- Exponential race (-ln(u)/weight) = weighted sampling without replacement.
-- Conversion propensity differs by traffic source and by campaign.
create or replace table raw.ecom.orders as
with weighted as (
    select *,
        case traffic_source
            when 'email' then 1.35 when 'direct' then 1.2 when 'paid_search' then 1.1
            when 'organic_search' then 1.0 else 0.75
        end
        * coalesce(0.6 + mod(campaign_id * 37, 11) / 10, 1.0)   as weight,
        uniform(1e-12::float, 1::float, random())               as u
    from raw.ecom.web_sessions
),
picked as (
    select * from weighted
    order by -ln(u) / weight
    limit 1000000
),
o as (
    select
        row_number() over (order by session_started_at, session_id) as order_id,
        session_id,
        customer_id,
        session_started_at,
        device_type,
        uniform(60, 259200, random()) as r_delay,
        uniform(1, 100, random())     as r_status,
        uniform(1, 4, random())       as item_count,
        uniform(1, 100, random())     as r_promo
    from picked
)
select
    order_id,
    customer_id,
    session_id,
    -- order lands 1 min - 3 days after the session, but never later than yesterday
    dateadd(second,
        least(r_delay, datediff(second, session_started_at, current_date()::timestamp_ntz) - 1),
        session_started_at)                                     as ordered_at,
    case
        when r_status <= 78 then 'completed'
        when r_status <= 86 then 'shipped'
        when r_status <= 90 then 'placed'
        when r_status <= 96 then 'returned'
        else 'cancelled'
    end                                                         as status,
    case device_type when 'mobile' then 'mobile_app' else 'web' end as sales_channel,
    case
        when r_promo <= 10 then 'SAVE10'
        when r_promo <= 15 then 'SAVE15'
        when r_promo <= 18 then 'SAVE20'
    end                                                         as promo_code,
    item_count,
    current_timestamp()                                         as _loaded_at
from o;

-- 6. Order items: exactly item_count lines per order ----------------------------
create or replace table raw.ecom.order_items as
with lines as (
    select row_number() over (order by seq4()) as line_number
    from table(generator(rowcount => 4))
),
x as (
    select
        o.order_id,
        l.line_number,
        uniform(1, 1000, random()) as product_id,
        uniform(1, 3, random())    as quantity
    from raw.ecom.orders o
    join lines l on l.line_number <= o.item_count
)
select
    row_number() over (order by x.order_id, x.line_number) as order_item_id,
    x.order_id,
    x.line_number,
    x.product_id,
    x.quantity,
    p.list_price               as unit_price,   -- price snapshot at order time
    current_timestamp()        as _loaded_at
from x
join raw.ecom.products p on p.product_id = x.product_id;

-- 7. Sanity check ---------------------------------------------------------------
select 'customers'    as tbl, count(*) as n from raw.ecom.customers    union all
select 'products',            count(*)      from raw.ecom.products     union all
select 'campaigns',           count(*)      from raw.ecom.campaigns    union all
select 'web_sessions',        count(*)      from raw.ecom.web_sessions union all
select 'orders',              count(*)      from raw.ecom.orders       union all
select 'order_items',         count(*)      from raw.ecom.order_items;
