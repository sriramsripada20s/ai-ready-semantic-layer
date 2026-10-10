-- Business rule: a customer can't have a session before they signed up.
{{ config(store_failures=true) }}
select s.session_id, s.customer_id, s.session_date, c.signup_date
from {{ ref('fct_web_sessions') }} s
join {{ ref('dim_customers') }} c on c.customer_id = s.customer_id
where s.session_date < c.signup_date
