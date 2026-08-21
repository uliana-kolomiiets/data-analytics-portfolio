# Product-Basket and Add-On Analysis

## Context

The catalogue contains a core product, a layer of paid add-ons, and a separate service-contract layer, plus a long tail of items accumulated over two decades. Cross-sell planning was being done from intuition about which things "go together".

Nobody had measured the actual baskets: which products co-occur, which add-ons predict which others, and — the question nobody had asked — which items nobody buys at all any more.

## Goal

Measure real product co-occurrence, identify actionable cross-sell rules, group customers into interpretable personas, and surface dead catalogue items.

## My Role

Built the whole analysis and the deliverable workbook, and documented the catalogue structure that it exposed.

## Data and Logic

The first problem was semantic, not technical. "Customers who bought A also bought B" has at least two incompatible readings:

- **Exact basket** — customers whose holdings are *precisely* {A, B}
- **Support** — customers whose holdings *include* A and B, among possibly others

These give very different numbers and support different decisions, and mixing them is the standard way basket analysis goes wrong. I computed both, labelled them explicitly, and used exact baskets for portfolio description and support-based rules for cross-sell targeting.

The second problem was catalogue structure. The three layers behave differently:

| Layer | Behaviour |
|---|---|
| Core product | Has a renewal cycle; enters the retention lifecycle |
| Add-on | Has its own contract and can be purchased separately, but **has no renewal cycle of its own** — so it never appears in retention analysis unless deliberately included |
| Service contract | A payment model rather than a product; carries recurring revenue and behaves as a customer attribute |

That add-on distinction is the kind of thing that silently invalidates a retention analysis, so it went into the documentation alongside the numbers.

## Approach

1. Built the holdings matrix per customer, restricted to currently active items
2. Computed exact-basket frequencies and support/confidence/lift rules separately, and labelled every output with which it is
3. Ran k-means on the holdings and firmographic attributes to produce interpretable personas, keeping the cluster count low enough that each cluster has a describable identity
4. Flagged catalogue items with no recent sales as dead
5. Documented the three-layer structure and the bridge key that links add-ons to the service-contract layer
6. Delivered as a multi-sheet workbook with the queries included, so the analysis is reproducible without me

## Sanitized SQL / Logic Example

```sql
-- Pairwise co-occurrence with support, confidence and lift.
-- SUPPORT semantics: holdings INCLUDE both, not holdings EQUAL both.
WITH holdings AS (
    SELECT DISTINCT customer_id, product_key
    FROM crm.active_subscription
    WHERE valid_from <= CURRENT_DATE
      AND (valid_to IS NULL OR valid_to > CURRENT_DATE)
),

total AS (SELECT COUNT(DISTINCT customer_id) AS n_customers FROM holdings),

single AS (
    SELECT product_key, COUNT(DISTINCT customer_id) AS n_holding
    FROM holdings
    GROUP BY product_key
),

pairs AS (
    SELECT
        a.product_key AS product_a,
        b.product_key AS product_b,
        COUNT(DISTINCT a.customer_id) AS n_both
    FROM holdings a
    JOIN holdings b
      ON a.customer_id = b.customer_id
     AND a.product_key < b.product_key      -- each unordered pair once
    GROUP BY 1, 2
)

SELECT
    p.product_a,
    p.product_b,
    p.n_both,
    ROUND(100.0 * p.n_both / t.n_customers, 2)      AS support_pct,
    ROUND(100.0 * p.n_both / sa.n_holding, 2)       AS confidence_a_to_b_pct,
    ROUND((p.n_both::numeric / t.n_customers)
          / NULLIF((sa.n_holding::numeric / t.n_customers)
                 * (sb.n_holding::numeric / t.n_customers), 0), 2) AS lift
FROM pairs p
CROSS JOIN total t
JOIN single sa ON sa.product_key = p.product_a
JOIN single sb ON sb.product_key = p.product_b
WHERE p.n_both >= :min_basket_size          -- suppress noise from tiny cells
ORDER BY lift DESC;
```

## QA and Validation

- Deduplicated case-inconsistent product names before grouping, since the same product recorded under two capitalisations splits into two products in any naive aggregation
- Restricted to active holdings, and stated that restriction on every sheet
- Suppressed rules below a minimum basket count, because lift on a cell of three customers is noise with a decimal point
- Labelled every table with its basket semantics, exact or support
- Flagged the revenue caveat: holdings counts are not revenue, and the two must not be read interchangeably

## Outcome

- Full co-occurrence tables with support, confidence and lift, plus exact-basket portfolio frequencies
- The headline structural finding: **only around 14% of customers hold more than one product**, and the largest observed portfolio is five items. Cross-sell was being planned as if multi-product customers were the norm; they are the exception, and that reframes the size of the opportunity
- Interpretable customer personas from clustering on holdings and firmographics
- A list of dead catalogue items with no recent sales — candidates for retirement, which nobody had previously enumerated
- Documentation of the three-layer product structure, including the add-on/renewal-cycle trap that would otherwise distort retention analysis

## What This Demonstrates

- Getting the semantics right before the statistics: exact basket versus support is a decision, not a detail
- Suppressing small-cell noise instead of shipping impressive lift values computed on nothing
- Finding a structural fact that resizes the business question, not just ranks the options
- Documenting a catalogue-layer distinction that invalidates a whole class of downstream analysis
- Shipping the queries with the workbook so the analysis is reproducible
