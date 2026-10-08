# AI-Ready Semantic Layer: one certified definition per metric, served everywhere

**Business Problem:** When every team calculates revenue, AOV and ROAS its own way, dashboards disagree and leaders stop trusting the numbers.

**Solution:** Define each metric once in code, test and govern it, and serve the same certified numbers to every BI tool and AI agent.

**Stack:** Snowflake · dbt Core + MetricFlow · GitHub Actions CI/CD · Power BI (DAX) · LangGraph + Claude agent via MCP.

> **Status: building in public, phase by phase.** The code for phases 0–10 is in this repo
> and tested end to end on a local DuckDB copy of the warehouse. Each phase below is ticked
> once it runs on Snowflake, with screenshots added under `docs/images/`.

| # | Phase | Status |
|---|---|---|
| 0–2 | Snowflake foundation, dbt Core setup | ⬜ |
| 3–5 | Staging → marts, contracts, tests, MetricFlow semantic layer, SCD2 snapshot | ⬜ |
| 6–8 | Governance (masking, row access, catalog), metric exports, CI/CD with slim CI | ⬜ |
| 9–10 | Power BI: certified KPIs, DAX dashboard, drill-through, RLS, incremental refresh | ⬜ |
| 11–12 | Power BI as code (PBIP/TMDL), agent-built measures via Power BI Modeling MCP | ⬜ |
| 13–14 | dbt → Snowflake semantic view (Apache Ossie), conversational analytics via Snowflake MCP | ⬜ |
| 15–16 | LangGraph + Claude Metrics Analyst Agent, AI accuracy eval | ⬜ |

## How it works today

Metrics are defined once in dbt YAML (latest spec, dbt Core 1.12) and computed by MetricFlow outside Snowflake. 

Every metric has an owner, grain, refresh SLA and business definition. The marts feeding them have enforced contracts. 

PII is masked and kept out of marts. Customer segment history is tracked as SCD Type 2 with a dbt snapshot. 

Unit tests and business-rule tests guard the logic, and slim CI builds only what a PR changed. 

Power BI shows the certified metrics plus a DAX dashboard that reconciles to them, and every page traces back to raw data. The data is synthetic, generated inside Snowflake to look like a real online retailer.

