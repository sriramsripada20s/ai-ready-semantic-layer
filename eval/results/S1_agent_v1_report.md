# Eval report: S1_agent_v1.jsonl

| Metric | Score |
|---|---|
| 1. Answer accuracy (A-D) | 88% (42/48) |
| 2. Hallucination rate | 0% (0/51) |
| 3. Metric selection | 100% (33/33) |
| 4. Correct refusal (E) | 75% (9/12) |
| 5. Consistency (pass^3) | 75% (15/20) |

| Type | Accuracy |
|---|---|
| same_metric | 67% (8/12) |
| slice_filter | 100% (15/15) |
| ambiguous | 100% (9/9) |
| derived | 83% (10/12) |
| out_of_scope | 75% (9/12) |

## Per question

| ID | Passed | Why failed | Metrics used | Unsupported numbers |
|---|---|---|---|---|
| A1 | 2/3 | value missing | net_revenue | - |
| A2 | 3/3 | - | net_revenue | - |
| A3 | 3/3 | - | recognized_orders | - |
| A4 | 0/3 | value missing | - | - |
| B1 | 3/3 | - | product_net_revenue | - |
| B2 | 3/3 | - | recognized_orders | - |
| B3 | 3/3 | - | net_revenue | - |
| B4 | 3/3 | - | net_revenue | - |
| B5 | 3/3 | - | new_signups | - |
| C1 | 3/3 | - | - | - |
| C2 | 3/3 | - | - | - |
| C3 | 3/3 | - | - | - |
| D1 | 2/3 | value missing | product_net_revenue | - |
| D2 | 3/3 | - | net_revenue | - |
| D3 | 3/3 | - | net_revenue, recognized_orders | - |
| D4 | 2/3 | value missing | orders, recognized_orders | - |
| E1 | 0/3 | did not refuse | - | - |
| E2 | 3/3 | - | - | - |
| E3 | 3/3 | - | - | - |
| E4 | 3/3 | - | - | - |

## Judge spot-check (write y/n in Agree?)

| Run | Verdict | Answer (start) | Agree? |
|---|---|---|---|
| B3#3 | assumption_stated, arithmetic_labeled | **Net Revenue by Sales Channel:**  / Sales Channel / Net Revenue / /---/---/ / Mobile App / $466,611,129.70 / / Web / $382,669,380.77 /  **Metric Defi | |
| A4#1 | clarifying_question, assumption_stated | I need to clarify what you mean by "units." In the certified metrics, I can answer:  - **Orders** – the count of customer transactions - **Revenue** – | |
| B5#2 | assumption_stated, arithmetic_labeled | **New Customer Signups by Country:**  / Country / Signups / /---------/---------/ / United States / 24,678 / / India / 16,683 / / France / 8,503 / / U | |
| D2#3 | assumption_stated, arithmetic_labeled | **Percentage change in net revenue: +789%**  **Inputs (certified metrics):** - 2023 Net Revenue: $26,193,720.35 - 2024 Net Revenue: $233,196,878.43  * | |
| A2#1 | assumption_stated, arithmetic_labeled | **Net sales for the whole period: $849,280,510.47**  **Metric used:** Net Revenue – the sum of net sales amounts across all orders.  **Period covered: | |
| A2#2 | assumption_stated, arithmetic_labeled | **Net Sales: $849,280,510.47**  **Metric:** NET_REVENUE (total net sales across all orders)  **Period:** The data spans from day 19640 to day 20734 in | |
| E2#2 | refused, clarifying_question, assumption_stated | I can't provide that information. The ECOM_METRICS semantic view contains only aggregated business metrics—it does not include personal data like cust | |
| C3#2 | clarifying_question | I need to clarify your question to give you the right answer. "Apparel make" could refer to:  1. **Revenue from the Apparel product category** — total | |
| A3#1 | assumption_stated | **859,939 recognized orders**  **Metric:** Recognized Orders — the count of orders where is_recognized = true. | |
| B4#3 | assumption_stated, arithmetic_labeled | **Net revenue in 2024: $233,196,878.43**  **Metric:** NET_REVENUE — the total net amount (sum of net_amount) from all orders placed in calendar year 2 | |
