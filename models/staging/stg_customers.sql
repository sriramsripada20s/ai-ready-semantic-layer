-- Cleaned customers: one row per customer.
-- Each rule fixes an issue injected by snowflake/02b_inject_data_issues.sql [#n].
with source as (
    select * from {{ source('ecom', 'customers') }}
),

-- No duplicates today, but the loader re-sends rows (see orders [1]).
-- Keep the LATEST loaded version, same rule as stg_orders.
deduplicated as (
    select *
    from source
    qualify row_number() over (partition by customer_id order by _loaded_at desc) = 1
),

country_aliases as (
    select * from {{ ref('country_code_aliases') }}
),

cleaned as (
    select
        d.customer_id,
        d.full_name,
        -- [4] 2,000 emails with stray spaces and capitals; empty -> NULL
        nullif(lower(trim(d.email)), '')                as email,
        -- [3] Free-text country field: 'de ' and 'uk' need trim/upper,
        --     'USA' / 'U.S.' / 'UK' are mapped by the country_code_aliases seed
        coalesce(a.country_code, upper(trim(d.country_code))) as country_code,
        d.acquisition_channel,
        d.signup_date,
        d.deleted_at
    from deduplicated as d
    left join country_aliases as a
        on upper(trim(d.country_code)) = a.alias
)

select
    customer_id,
    full_name,
    email,
    country_code,
    acquisition_channel,
    cast(signup_date as date)                           as signup_date,
    cast(deleted_at as timestamp)                       as deleted_at,
    -- [4] 100 emails with '@' replaced by '.at.': flagged, not repaired (we'd be guessing)
    coalesce(regexp_like(email, '^[^@ ]+@[^@ ]+\\.[^@ ]+$'), false) as is_valid_email,
    -- [5] 50 QA accounts. Uses only the domain, so it still works when email is masked ('*****@domain')
    coalesce(split_part(email, '@', 2) = 'test.example.com', false) as is_test_account,
    -- [6] Soft deletes. 21 deleted_at values are in the future (signup + 30 days):
    --     treated as scheduled closures, so the account stays active until that date
    coalesce(deleted_at <= current_timestamp, false)    as is_deleted
from cleaned
