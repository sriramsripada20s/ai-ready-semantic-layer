-- =============================================================================
-- 02b_inject_data_issues.sql  —  make the raw data look like real-world data
--
-- 02_generate_data.sql produces perfectly clean data. Real source systems don't.
-- This script damages RAW.ECOM in 12 realistic, DOCUMENTED and COUNTED ways, so the
-- dbt staging layer has real cleaning to do and the tests have real problems to catch.
--
-- Every issue is chosen deterministically (MOD on ids), so the counts are the same on
-- every run and you can prove "N bad rows in, 0 out".
--
--   #  table        issue                                   real-world cause
--   1  orders       1,000 duplicate rows (later reload)     loader retried after a failure
--   2  orders       messy status: 'Completed', ' shipped ', 'COMPLETE'   app versions, manual edits
--   3  customers    country variants: USA, U.S., uk, 'de '  free-text form field
--   4  customers    emails with spaces/capitals; 100 invalid  user typing
--   5  customers    50 QA test accounts                     QA team testing in production
--   6  customers    400 soft-deleted accounts (deleted_at)  account closures
--   7  order_items  ~6,250 lines with NULL unit_price       price service outage
--   8  order_items  300 lines with quantity 0 or -1         returns keyed as negative lines
--   9  order_items  ~1,000 lines pointing at products 1001-1005 that don't exist yet
--                                                           product feed arrives late
--  10  orders       recent orders dated 1 year in the future  device clock bug
--  11  orders       promo codes in lower case with spaces   typed by users
--  12  campaigns    budget stored as text: '$2,450,000.00'  spreadsheet export
--
-- Run AFTER 02_generate_data.sql. It is NOT idempotent: to start over (including after
-- an error part-way through), re-run 02 and then this script. (Re-running 02 also drops masking policies: re-run 04 after.)
-- =============================================================================

use role transformer;
use warehouse transforming;
use schema raw.ecom;

-- 0. Widen text columns first ------------------------------------------------------
-- 02 builds tables with CREATE TABLE AS SELECT, so Snowflake sizes each text column to
-- its longest generated value: status is VARCHAR(9) ('cancelled'), promo_code
-- VARCHAR(6) ('SAVE10'). The messy values below are longer (' cancelled ', 'save10 '),
-- so without this step Snowflake fails with "String ... is too long and would be
-- truncated". Real source systems use wide VARCHARs, so this is also more realistic.
-- Plain VARCHAR = the maximum length. Snowflake only allows a VARCHAR to grow, and some
-- of these columns may already be at the maximum, so any smaller size could fail.
alter table raw.ecom.orders    alter column status       set data type varchar;
alter table raw.ecom.orders    alter column promo_code   set data type varchar;
alter table raw.ecom.customers alter column email        set data type varchar;
alter table raw.ecom.customers alter column country_code set data type varchar;
alter table raw.ecom.customers alter column full_name    set data type varchar;

-- 1. Duplicate orders -----------------------------------------------------------
-- A reload 6 hours later re-sent 1,000 orders. Some had moved on from 'placed' to
-- 'shipped' in the meantime, so the LATEST loaded row is the correct one to keep.
insert into raw.ecom.orders
select
    order_id, customer_id, session_id, ordered_at,
    case when status = 'placed' then 'shipped' else status end,
    sales_channel, promo_code, item_count,
    dateadd(hour, 6, _loaded_at)
from raw.ecom.orders
where mod(order_id, 1000) = 0;

-- 2. Messy order status -----------------------------------------------------------
update raw.ecom.orders
set status = case
        when mod(order_id, 40) = 1 then upper(left(status, 1)) || substr(status, 2)  -- 'Completed'
        when mod(order_id, 40) = 2 then ' ' || status || ' '                          -- ' shipped '
        when mod(order_id, 40) = 3 and status = 'completed' then 'COMPLETE'           -- different word
        else status
    end
where mod(order_id, 40) in (1, 2, 3);

-- 3. Country code variants ----------------------------------------------------------
update raw.ecom.customers
set country_code = case
        when country_code = 'US' and mod(customer_id, 20) = 1 then 'USA'
        when country_code = 'US' and mod(customer_id, 20) = 2 then 'U.S.'
        when country_code = 'GB' and mod(customer_id, 20) = 3 then 'uk'
        when country_code = 'DE' and mod(customer_id, 20) = 4 then 'de '
        else country_code
    end
where mod(customer_id, 20) in (1, 2, 3, 4);

-- 4. Emails: spaces + capitals (2,000), and 100 invalid ones --------------------------
update raw.ecom.customers
set email = '  ' || upper(email) || ' '
where mod(customer_id, 50) = 7;

update raw.ecom.customers
set email = replace(email, '@', '.at.')
where mod(customer_id, 1000) = 13;

-- 5. QA test accounts -----------------------------------------------------------------
insert into raw.ecom.customers (customer_id, full_name, email, country_code, acquisition_channel, signup_date, _loaded_at)
select
    900000 + n,
    'Test User ' || n,
    'qa+' || n || '@test.example.com',
    'US',
    'organic',
    dateadd(day, -1 - mod(n, 30), current_date()),
    current_timestamp()
from (select row_number() over (order by seq4()) as n from table(generator(rowcount => 50)));

-- 6. Soft-deleted customers -------------------------------------------------------------
alter table raw.ecom.customers add column if not exists deleted_at timestamp_ntz;
update raw.ecom.customers
set deleted_at = dateadd(day, 30, signup_date)::timestamp_ntz
where mod(customer_id, 250) = 17;

-- 7. Missing unit prices ------------------------------------------------------------------
update raw.ecom.order_items
set unit_price = null
where mod(order_item_id, 400) = 17;

-- 8. Zero / negative quantity lines (300 extra lines) ----------------------------------------
insert into raw.ecom.order_items (order_item_id, order_id, line_number, product_id, quantity, unit_price, _loaded_at)
select
    10000000 + o.order_id,
    o.order_id,
    9,
    1 + mod(o.order_id, 1000),
    case when mod(o.order_id, 2) = 0 then 0 else -1 end,
    p.list_price,
    current_timestamp()
from raw.ecom.orders o
join raw.ecom.products p on p.product_id = 1 + mod(o.order_id, 1000)
where mod(o.order_id, 3333) = 1
  and mod(o.order_id, 1000) <> 0;          -- skip the duplicated orders: one extra line per order

-- 9. Orphan product ids (late-arriving products 1001-1005) -------------------------------------
-- (MOD 2500 = 11 never overlaps MOD 400 = 17, so these lines keep their price.)
update raw.ecom.order_items
set product_id = 1001 + mod(order_item_id, 5)
where mod(order_item_id, 2500) = 11;

-- 10. Future-dated orders (device clock bug added exactly 1 year) --------------------------------
update raw.ecom.orders
set ordered_at = dateadd(year, 1, ordered_at)
where mod(order_id, 500) = 123
  and ordered_at >= dateadd(day, -60, current_date());

-- 11. Promo codes typed by users ------------------------------------------------------------------
update raw.ecom.orders
set promo_code = lower(promo_code) || ' '
where promo_code is not null
  and mod(order_id, 25) = 4;

-- 12. Campaign budget exported as text -------------------------------------------------------------
create or replace table raw.ecom.campaigns as
select
    campaign_id,
    campaign_name,
    channel,
    start_date,
    end_date,
    '$' || trim(to_varchar(budget, '999,999,990.00')) as budget,
    _loaded_at
from raw.ecom.campaigns;

-- What was injected (keep this output: it is your "before" picture) ---------------------------------
select '1 duplicate order rows'            as issue, count(*) - count(distinct order_id) as n from raw.ecom.orders
union all select '2 non-standard status',       count(*) from raw.ecom.orders
          where status not in ('placed', 'shipped', 'completed', 'returned', 'cancelled')
union all select '3 non-standard country code', count(*) from raw.ecom.customers
          where country_code not in ('US', 'CA', 'GB', 'DE', 'FR', 'IN', 'BR', 'MX', 'AU')
union all select '4a emails needing trim/lower', count(*) from raw.ecom.customers where email <> lower(trim(email))
union all select '4b invalid emails',           count(*) from raw.ecom.customers where email not like '%_@_%._%'
union all select '5 test accounts',             count(*) from raw.ecom.customers where email like '%@test.example.com'
union all select '6 soft-deleted customers',    count(*) from raw.ecom.customers where deleted_at is not null
union all select '7 lines missing unit_price',  count(*) from raw.ecom.order_items where unit_price is null
union all select '8 lines with quantity <= 0',  count(*) from raw.ecom.order_items where quantity <= 0
union all select '9 lines with unknown product', count(*) from raw.ecom.order_items i
          where not exists (select 1 from raw.ecom.products p where p.product_id = i.product_id)
union all select '10 future-dated orders',      count(*) from raw.ecom.orders where ordered_at > _loaded_at
union all select '11 promo codes needing upper/trim', count(*) from raw.ecom.orders
          where promo_code is not null and promo_code <> upper(trim(promo_code))
union all select '12 campaign budgets as text', count(*) from raw.ecom.campaigns where budget like '$%'
order by 1;
