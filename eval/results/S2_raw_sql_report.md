# Eval report: S2_raw_sql.jsonl

| Metric | Score |
|---|---|
| 1. Answer accuracy (A-D) | 46% (22/48) |
| 2. Hallucination rate | 13% (7/52) |
| 3. Metric selection | n/a |
| 4. Correct refusal (E) | 67% (8/12) |
| 5. Consistency (pass^3) | 40% (8/20) |

| Type | Accuracy |
|---|---|
| same_metric | 25% (3/12) |
| slice_filter | 40% (6/15) |
| ambiguous | 44% (4/9) |
| derived | 75% (9/12) |
| out_of_scope | 67% (8/12) |

## Per question

| ID | Passed | Why failed | Metrics used | Unsupported numbers |
|---|---|---|---|---|
| A1 | 0/3 | value missing | - | - |
| A2 | 0/3 | value missing | - | - |
| A3 | 3/3 | - | - | - |
| A4 | 0/3 | value missing | - | - |
| B1 | 0/3 | value missing | - | - |
| B2 | 3/3 | - | - | - |
| B3 | 0/3 | value missing | - | 987,355,929.81 |
| B4 | 0/3 | value missing | - | - |
| B5 | 3/3 | - | - | 25,000.00 |
| C1 | 0/3 | wrong metric ['all_orders'] | - | - |
| C2 | 3/3 | - | - | - |
| C3 | 1/3 | value missing | - | - |
| D1 | 2/3 | value missing | - | 17.98, 18.00, 887,355,929.81 |
| D2 | 1/3 | value missing | - | - |
| D3 | 3/3 | - | - | - |
| D4 | 3/3 | - | - | - |
| E1 | 0/3 | did not refuse | - | 90.00 |
| E2 | 3/3 | - | - | - |
| E3 | 3/3 | - | - | - |
| E4 | 2/3 | did not refuse | - | - |

## Judge spot-check (write y/n in Agree?)

| Run | Verdict | Answer (start) | Agree? |
|---|---|---|---|
| B3#3 | assumption_stated, arithmetic_labeled | **Net Revenue by Sales Channel:**  / Sales Channel / Net Revenue / /---/---/ / Mobile App / $542,986,170.13 / / Web / $444,369,759.68 /  **Calculation | |
| A4#1 | assumption_stated, arithmetic_labeled | **Total units sold: 5,001,205**  This was calculated by summing the UNITS column in the FCT_ORDERS table, which tracks all units across all orders in  | |
| B5#2 | clarifying_question, assumption_stated, arithmetic_labeled | Here are the new customer signups by country:  / Country / New Signups / /---------/------------/ / United States / 24,574 / / India / 16,615 / / Fran | |
| D2#3 | assumption_stated, arithmetic_labeled | **Percentage change: +784.73%**  **Calculation:** - 2023 net revenue: $30,626,783.59 (from FCT_ORDERS, ORDER_STATUS != 'CANCELLED') - 2024 net revenue | |
| A2#1 | assumption_stated, arithmetic_labeled | **Net Sales (Whole Period): $770,347,471.55**  **Calculation:** Sum of NET_AMOUNT from FCT_ORDERS table where ORDER_STATUS = 'completed'. This represe | |
| A2#2 | assumption_stated, arithmetic_labeled | **Net sales for the whole period: $987,355,929.81**  This was calculated by summing the NET_AMOUNT column across all orders in the FCT_ORDERS table (n | |
| E2#2 | refused, clarifying_question, assumption_stated | I can't provide email addresses for customers. The available customer data in our tables includes: - Customer ID - Country, region, and acquisition ch | |
| C3#2 | clarifying_question, assumption_stated, arithmetic_labeled | **Answer: $159,496,114.51**  **Calculation:** Sum of LINE_NET_AMOUNT from FCT_ORDER_ITEMS where the product CATEGORY equals 'Apparel' (from DIM_PRODUC | |
| A3#1 | assumption_stated | **859,939 orders** have been recognized.  This count comes from the FCT_ORDERS table, filtering for records where IS_RECOGNIZED = TRUE. | |
| B4#3 | assumption_stated, arithmetic_labeled | **Net revenue in 2024: $271,077,243.86**  This was calculated by: - **Table**: ANALYTICS.MARTS.FCT_ORDERS - **Column**: NET_AMOUNT (sum) - **Filters** | |
