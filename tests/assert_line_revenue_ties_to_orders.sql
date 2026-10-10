-- Order net revenue must equal the sum of its lines (returns rows = failure)
select o.order_id, o.net_amount, SUM(i.line_net_amount) as line_sum
from {{ ref('fct_orders') }} o
join {{ ref('fct_order_items') }} i 
on i.order_id = o.order_id
group by 1, 2
having ABS(o.net_amount - SUM(i.line_net_amount)) > 0.01