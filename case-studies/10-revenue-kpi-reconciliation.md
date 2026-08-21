# Revenue KPI Reconciliation Across Three Systems

## Context

The company reports a headline commercial KPI that everyone calls "turnover". It travels through three systems before anyone sees it: the ERP where money is actually recorded, an intermediate staging layer built years ago for the intranet, and the data warehouse that feeds the dashboards.

Nobody could state the formula. Sales commission depends on a derived amount whose calculation existed only inside stored procedures. Different dashboards disagreed. And the question that triggered the work was a fair one from management: *is the number we look at every month actually our revenue?*

## Goal

Reconstruct the full lineage from the ERP source to the dashboard figure, document the formula, and establish how the reported KPI relates to actual revenue.

## My Role

Ran the whole audit, wrote the documentation, and — twice — withdrew findings of my own that did not survive verification.

## Data and Logic

Three layers, each with its own semantics:

| Layer | What it holds | Trap |
|---|---|---|
| ERP | Invoice and payment records | Several amount columns with similar names and different meanings |
| Staging | Denormalised intranet tables | Contains derived amounts whose formula lives in stored procedures |
| Warehouse | Dashboard-facing marts | Inherits the staging derivations without restating them |

The audit had to answer three separate questions that are easy to conflate:

- What is the **formula** for the commissionable amount
- How is money **distributed** across products, sellers and periods when an invoice covers several
- How does the reported KPI **compare** to actual revenue

The third question is where the accounting basis matters: one date column that reads like an invoice date is in fact a payment date, so the KPI is partly cash-basis while being described as accrual. A column name was lying about what it contains.

## Approach

1. Got read access to the ERP layer, which had not previously been queried directly for this purpose
2. Traced a single invoice by hand through all three layers, end to end, before writing any aggregate query
3. Read the stored procedures to recover the commissionable-amount formula rather than inferring it from data
4. Derived the money-distribution rules from the data and validated each one against known cases
5. Reconciled the reported KPI against the ERP revenue total for the same period
6. Wrote it all up as a single documented reference with every finding numbered and evidenced

## Sanitized SQL / Logic Example

```sql
-- Reconciliation: reported KPI vs. actual ERP revenue for the same period.
-- Both sides must be built from their own source of truth and compared,
-- never derived from one another.
WITH erp_revenue AS (
    SELECT
        DATE_TRUNC('month', document_date)::date AS period,
        SUM(net_amount)                          AS erp_net_revenue
    FROM erp.invoice_line
    WHERE document_type IN ('invoice', 'credit_note')
      AND document_date >= :period_start
    GROUP BY 1
),

reported_kpi AS (
    SELECT
        DATE_TRUNC('month', reporting_date)::date AS period,
        SUM(reported_amount)                      AS kpi_amount
    FROM warehouse.commercial_kpi
    WHERE reporting_date >= :period_start
    GROUP BY 1
),

-- The column that reads like an invoice date but holds a payment date.
-- Aggregating on it silently switches the accounting basis.
staging_derived AS (
    SELECT
        DATE_TRUNC('month', settlement_date)::date AS period,
        SUM(gross_amount_before_tax)               AS staging_amount
    FROM staging.intranet_turnover
    WHERE settlement_date >= :period_start
    GROUP BY 1
)

SELECT
    e.period,
    e.erp_net_revenue,
    k.kpi_amount,
    s.staging_amount,
    ROUND(100.0 * k.kpi_amount    / NULLIF(e.erp_net_revenue, 0), 2) AS kpi_pct_of_revenue,
    ROUND(100.0 * s.staging_amount / NULLIF(e.erp_net_revenue, 0), 2) AS staging_pct_of_revenue
FROM erp_revenue e
LEFT JOIN reported_kpi   k ON k.period = e.period
LEFT JOIN staging_derived s ON s.period = e.period
ORDER BY e.period;
```

## QA and Validation

- Hand-traced individual documents through all three layers before trusting any aggregate
- Built each side of the reconciliation from its own source, never one from the other
- Tested every distribution rule against cases where the correct answer was independently known
- Re-verified all findings before publication — which is how three of them fell over

## Outcome

- A single documented reference covering the full lineage, the recovered commissionable-amount formula, and eight rules governing how money is distributed across products, sellers and periods
- **21 findings**, each numbered and evidenced, ranging from a materially missing revenue component in one dashboard to naming and basis problems
- **A correction of my own headline finding.** I had initially concluded that the reported KPI represented roughly 88% of actual revenue — a significant understatement that would have prompted a fix. On verification it does not: the KPI matches actual revenue almost exactly. What was inflated was a *different* aggregate built on a different amount column, which overstated by a double-digit percentage. I published the correction with the same prominence as the original claim
- Two further findings were downgraded or withdrawn on verification and marked as such rather than deleted, so the record shows what was tested and rejected
- Delivered as a master reference document plus executive slide decks for different audiences

## What This Demonstrates

- Reconstructing undocumented business logic from stored procedures and data, across three systems
- Hand-tracing single records before trusting aggregates — the only way to catch layer-level semantic drift
- Detecting an accounting-basis mismatch hidden behind a misleading column name
- Correcting a prominent finding of my own at full volume, and keeping withdrawn findings visible in the record
- Producing one authoritative reference where previously there were disagreeing dashboards and no written formula
