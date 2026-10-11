{# Drop every schema a PR's CI run created: ci_pr_<n>, ci_pr_<n>_staging, _marts, ...
   Called by .github/workflows/ci_cleanup.yml when the PR closes. #}
{% macro drop_pr_schemas(pr_prefix) %}
    {# safety: never drop anything that isn't a CI schema #}
    {% if not pr_prefix.startswith('ci_pr_') %}
        {{ exceptions.raise_compiler_error("refusing to drop schemas not starting with ci_pr_: " ~ pr_prefix) }}
    {% endif %}
    {% for suffix in ['', '_staging', '_intermediate', '_marts', '_reference', '_audit', '_dbt_test__audit'] %}
        {% set relation = api.Relation.create(database=target.database, schema=pr_prefix ~ suffix) %}
        {% do adapter.drop_schema(relation) %}
        {{ log("dropped schema " ~ relation, info=True) }}
    {% endfor %}
{% endmacro %}
