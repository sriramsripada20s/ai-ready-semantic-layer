-- One row per calendar day, 2020-01-01 through early 2028.
-- MetricFlow needs it for cumulative, period-over-period and gap-filled metrics.
{{ config(materialized='table') }}

select dateadd(day, row_number() over (order by seq4()) - 1, '2020-01-01'::date) as date_day
from table(generator(rowcount => 3000))
