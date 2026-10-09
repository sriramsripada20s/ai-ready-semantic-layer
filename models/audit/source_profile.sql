-- One row per column of EVERY table in the `ecom` source, with profiling stats and a
-- suggested cleanup. Add a table to _sources.yml and it's profiled on the next run.
-- Run on demand (it scans every column):  dbt run --select source_profile
{{ config(materialized='table', tags=['profiling']) }}

{%- set source_tables = [] -%}
{%- if execute -%}
    {%- for node in graph.sources.values() if node.source_name == 'ecom' -%}
        {%- do source_tables.append(node.name) -%}
    {%- endfor -%}
{%- endif -%}

with profile as (
    {%- if source_tables | length == 0 %}
    select cast(null as {{ dbt.type_string() }}) as table_name where 1 = 0
    {%- else %}
    {%- for t in source_tables | sort %}
    {{ profile_relation(source('ecom', t), t) }}
    {% if not loop.last %} union all {% endif %}
    {%- endfor %}
    {%- endif %}
)

select
    *,
    case
        when left(column_name, 1) = '_'
            then 'Load metadata: use for freshness checks and deduplication'
        when column_position = 1 and repeated_values > 0
            then 'Key column has repeats: deduplicate'
        when untrimmed_count > 0 or case_or_space_variants > 0
            then 'Standardize: trim, fix casing, map synonyms'
        when column_kind = 'text' and numeric_text_count = row_count - null_count and null_count < row_count
            then 'Numbers stored as text: strip symbols and cast'
        when empty_string_count > 0
            then 'Empty strings: convert to NULL'
        when non_positive_count > 0
            then 'Zero or negative values: check the business rule'
        when future_count > 0
            then 'Dates in the future: investigate'
        when null_pct = 100
            then 'Always NULL: drop or ask the source team'
        when null_pct > 0
            then 'Has NULLs: expected (optional field) or a defect?'
        when column_position = 1 and distinct_count = row_count
            then 'Primary key: add unique + not_null tests'
        when column_kind = 'text' and distinct_count <= 20
            then 'Categorical: add an accepted_values test'
        when right(column_name, 3) = '_id'
            then 'Foreign key: add a relationships test'
        else 'No obvious issue'
    end as suggested_action
from profile