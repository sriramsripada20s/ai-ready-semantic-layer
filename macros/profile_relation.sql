{#
  profile_relation(relation, table_label)
  Returns SQL that profiles EVERY column of `relation`: one row per column with
  null %, distinct count, min/max, sample values, and pattern checks that point to
  the cleanup a staging model needs (spaces, casing variants, negatives, future dates).
  Columns are discovered at run time from the warehouse, so a new column is profiled
  automatically.
#}
{% macro profile_relation(relation, table_label) %}
    {%- set columns = adapter.get_columns_in_relation(relation) -%}
    {%- for col in columns %}
    {%- set c = adapter.quote(col.name) -%}
    {%- set dtype = col.data_type | upper -%}
    {%- set is_text = col.is_string() -%}
    {%- set is_num = col.is_numeric() or col.is_number() -%}
    {%- set is_time = ('DATE' in dtype or 'TIME' in dtype) and not is_text -%}
    select
        '{{ table_label }}'                                              as table_name,
        {{ loop.index }}                                                 as column_position,
        '{{ col.name | lower }}'                                         as column_name,
        '{{ dtype }}'                                                    as data_type,
        '{{ "text" if is_text else ("number" if is_num else ("time" if is_time else "other")) }}' as column_kind,
        count(*)                                                         as row_count,
        sum(case when {{ c }} is null then 1 else 0 end)                 as null_count,
        round(100.0 * sum(case when {{ c }} is null then 1 else 0 end) / nullif(count(*), 0), 2) as null_pct,
        count(distinct {{ c }})                                          as distinct_count,
        count(*) - count(distinct {{ c }}) - sum(case when {{ c }} is null then 1 else 0 end) as repeated_values,
        cast(min({{ c }}) as {{ dbt.type_string() }})                    as min_value,
        cast(max({{ c }}) as {{ dbt.type_string() }})                    as max_value,
        {%- if is_text %}
        sum(case when {{ c }} <> trim({{ c }}) then 1 else 0 end)        as untrimmed_count,
        count(distinct {{ c }}) - count(distinct lower(trim({{ c }})))   as case_or_space_variants,
        sum(case when trim({{ c }}) = '' then 1 else 0 end)              as empty_string_count,
        -- text that parses as a number once $ and , are removed (e.g. '$2,450,000.00')
        sum(case when try_cast(replace(replace(trim({{ c }}), '$', ''), ',', '') as double) is not null
                 then 1 else 0 end)                                      as numeric_text_count,
        cast(null as {{ dbt.type_bigint() }})                            as non_positive_count,
        cast(null as {{ dbt.type_bigint() }})                            as future_count,
        {%- elif is_num %}
        cast(null as {{ dbt.type_bigint() }})                            as untrimmed_count,
        cast(null as {{ dbt.type_bigint() }})                            as case_or_space_variants,
        cast(null as {{ dbt.type_bigint() }})                            as empty_string_count,
        cast(null as {{ dbt.type_bigint() }})                            as numeric_text_count,
        sum(case when {{ c }} <= 0 then 1 else 0 end)                    as non_positive_count,
        cast(null as {{ dbt.type_bigint() }})                            as future_count,
        {%- elif is_time %}
        cast(null as {{ dbt.type_bigint() }})                            as untrimmed_count,
        cast(null as {{ dbt.type_bigint() }})                            as case_or_space_variants,
        cast(null as {{ dbt.type_bigint() }})                            as empty_string_count,
        cast(null as {{ dbt.type_bigint() }})                            as numeric_text_count,
        cast(null as {{ dbt.type_bigint() }})                            as non_positive_count,
        sum(case when cast({{ c }} as date) > current_date then 1 else 0 end) as future_count,
        {%- else %}
        cast(null as {{ dbt.type_bigint() }})                            as untrimmed_count,
        cast(null as {{ dbt.type_bigint() }})                            as case_or_space_variants,
        cast(null as {{ dbt.type_bigint() }})                            as empty_string_count,
        cast(null as {{ dbt.type_bigint() }})                            as numeric_text_count,
        cast(null as {{ dbt.type_bigint() }})                            as non_positive_count,
        cast(null as {{ dbt.type_bigint() }})                            as future_count,
        {%- endif %}
        (
            select {{ dbt.listagg('v', "' | '", 'order by v') }}
            from (
                select distinct cast({{ c }} as {{ dbt.type_string() }}) as v
                from {{ relation }}
                where {{ c }} is not null
                order by 1
                limit 8
            ) samples
        )                                                                as sample_values
    from {{ relation }}
    {% if not loop.last %} union all {% endif %}
    {%- endfor %}
{% endmacro %}
