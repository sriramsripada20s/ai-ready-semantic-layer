"""Build an Apache Ossie (v0.1.1) document for Snowflake from dbt's semantic manifest.

Why not use target/osi_document.json as-is? dbt's built-in Ossie export (v0.1) leaves
MetricFlow references unresolved (e.g. `sales_order__is_recognized`), emits bare `SUM(1)`
with no table, and adds many-to-many "relationships" between facts. Snowflake rejects
those. This script reads the same source of truth - target/semantic_manifest.json - and
writes Snowflake-ready Ossie: every column table-qualified, every filter resolved,
only fact -> dimension relationships, no name clashes. Metric names are unchanged.

Usage:  dbt parse --target prod  &&  python scripts/build_snowflake_ossie.py
Output: target/ossie_snowflake.json  (paste into SYSTEM$CREATE_SEMANTIC_VIEW_FROM_OSSIE_YAML)
"""
import json
import re
import sys
from pathlib import Path

MANIFEST = Path("target/semantic_manifest.json")
OUT = Path("target/ossie_snowflake.json")
DIALECT = "ANSI_SQL"   # same label dbt uses; Snowflake accepts it (SNOWFLAKE preferred, ANSI_SQL fallback)
MODEL_NAME = "ecom_metrics"

AGG = {"sum": "SUM", "count": "COUNT", "average": "AVG", "min": "MIN", "max": "MAX", "median": "MEDIAN"}


def sql(expr):  # one dialect-tagged SQL expression
    return {"dialects": [{"dialect": DIALECT, "expression": expr}]}


def main():
    m = json.loads(MANIFEST.read_text())
    models = {sm["name"]: sm for sm in m["semantic_models"]}
    # Snowflake keeps table, fact and metric names in one namespace, so:
    # - logical tables use the dbt model name (fct_orders), never a metric name (orders)
    # - a fact column that shares a metric's name gets a _fact suffix
    table = {n: sm["node_relation"]["alias"].lower() for n, sm in models.items()}
    metric_names = {mt["name"] for mt in m["metrics"]}
    def fact_name(col):
        return f"{col}_fact" if col in metric_names else col

    # entity name -> (semantic model, column) where it is the primary key
    primary = {}
    for sm in models.values():
        for e in sm["entities"]:
            if e["type"] == "primary":
                primary[e["name"]] = (sm["name"], e["expr"] or e["name"])

    def column_of(model, dim_or_entity):
        sm = models[model]
        for d in sm["dimensions"] + sm["entities"]:
            if d["name"] == dim_or_entity:
                return d["expr"] or d["name"]
        raise KeyError(f"{dim_or_entity} not found in {model}")

    def resolve_filter(template, own_model):
        """{{ Dimension('sales_order__is_recognized') }} -> fct_orders.is_recognized"""
        def dim(mt):
            entity, name = mt.group(1).split("__", 1)
            model = primary[entity][0]
            return f"{table[model]}.{column_of(model, name)}"
        def ent(mt):  # Entity('campaign') or Entity('sales_order__campaign')
            return f"{table[own_model]}.{column_of(own_model, mt.group(1).split('__')[-1])}"
        out = re.sub(r"\{\{\s*Dimension\('([^']+)'\)\s*\}\}", dim, template)
        out = re.sub(r"\{\{\s*Entity\('([^']+)'\)\s*\}\}", ent, out)
        if "{{" in out:
            raise ValueError(f"unsupported filter: {template}")
        return out

    # ---- metrics (simple only) + the fact columns they use --------------------------
    metrics, facts = [], {name: set() for name in models}
    for mt in m["metrics"]:
        if mt["type"] != "simple":
            print(f"skip {mt['name']} ({mt['type']}): only simple metrics are exported", file=sys.stderr)
            continue
        p = mt["type_params"]["metric_aggregation_params"]
        model, agg = p["semantic_model"], p["agg"]
        expr = (mt["type_params"]["expr"] or mt["name"]).strip()
        pk_col = next(col for mdl, col in primary.values() if mdl == model)
        if expr == "1":                       # sum(1) = row count -> count the primary key
            agg, col = "count", f"{table[model]}.{pk_col}"
        else:
            col = f"{table[model]}.{fact_name(expr)}"
            facts[model].add(expr)
        filters = [resolve_filter(f["where_sql_template"], model)
                   for f in (mt.get("filter") or {}).get("where_filters", [])]
        if filters:
            col = f"CASE WHEN {' AND '.join(f'({f})' for f in filters)} THEN {col} END"
        body = f"COUNT(DISTINCT {col})" if agg == "count_distinct" else f"{AGG[agg]}({col})"
        metrics.append({"name": mt["name"], "expression": sql(body),
                        "description": (mt.get("description") or "").strip()})

    # ---- datasets (logical tables) -----------------------------------------------------
    datasets = []
    for name, sm in models.items():
        rel = sm["node_relation"]
        fields, seen = [], set()
        def add(col, desc, dimension=None, label=None, name=None):
            if col in seen:
                return
            seen.add(col)
            f = {"name": name or col, "expression": sql(col), "description": (desc or "").strip()}
            if dimension is not None:
                f["dimension"] = {"is_time": dimension}
            if label:
                f["label"] = label
            fields.append(f)
        for e in sm["entities"]:
            add(e["expr"] or e["name"], e.get("description"), dimension=False)
        for d in sm["dimensions"]:
            add(d["expr"] or d["name"], d.get("description"), dimension=(d["type"] == "time"), label=d.get("label"))
        for col in sorted(facts[name]):
            add(col, None, name=fact_name(col))  # no dimension marker -> fact
        pk = [e["expr"] or e["name"] for e in sm["entities"] if e["type"] == "primary"]
        datasets.append({
            "name": table[name],
            "source": f"{rel['database']}.{rel['schema_name']}.{rel['alias']}".upper(),
            "primary_key": pk,
            "description": (sm.get("description") or "").strip(),
            "fields": fields,
        })

    # ---- relationships: star schema only - a fact's foreign key -> a DIMENSION's primary
    # key. Fact-to-fact links (orders -> sessions, order_items -> orders) are skipped:
    # they create a second join path to the same dimension (ambiguous), the same reason
    # they were removed from the Power BI model.
    is_fact = {n: any(e["type"] == "foreign" for e in sm["entities"]) for n, sm in models.items()}
    relationships = []
    for name, sm in models.items():
        for e in sm["entities"]:
            if e["type"] == "foreign" and e["name"] in primary:
                to_model, to_col = primary[e["name"]]
                if to_model != name and not is_fact[to_model]:
                    relationships.append({"name": f"{table[name]}_to_{table[to_model]}",
                                          "from": table[name], "to": table[to_model],
                                          "from_columns": [e["expr"] or e["name"]], "to_columns": [to_col]})

    # Same top-level shape as dbt's own Ossie export (the shape Snowflake parsed).
    doc = {"version": "0.1.1", "dialects": [DIALECT],
           "semantic_model": [{"name": MODEL_NAME, "datasets": datasets,
                               "relationships": relationships, "metrics": metrics}]}
    # JSON is valid YAML, and pasting it into Snowsight can't break on indentation.
    OUT.write_text(json.dumps(doc, indent=1))
    print(f"wrote {OUT}: {len(datasets)} datasets, {len(relationships)} relationships, {len(metrics)} metrics")


if __name__ == "__main__":
    main()
