-- QA accounts must never reach the marts
select dim.customer_id
from {{ ref('dim_customers') }} dim
join {{ ref('stg_ecom__customers') }} stg on stg.customer_id = dim.customer_id
where stg.is_test_account