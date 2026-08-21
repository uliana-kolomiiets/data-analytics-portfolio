/******************************************************************************
  reconciliation-qa.sql
  ---------------------------------------------------------------------------
  Cross-system reconciliation checks for a KPI that travels through several
  layers before anyone sees it:

      source of record  ->  staging / derived layer  ->  reporting mart

  THE ONE RULE
    Build each side of a reconciliation from its OWN source of truth.
    Never derive one side from the other - that produces a check which
    always passes and detects nothing.

  WHAT THIS CATCHES
    - Totals that diverge between layers
    - An accounting-basis switch hidden behind a misleading column name
    - Rows present in one layer and missing from the next
    - Aggregates built on the wrong amount column
 ******************************************************************************/

-- +-------------------------------------------------------------------------+
-- | 1. PERIOD TOTALS, THREE LAYERS SIDE BY SIDE
-- +-------------------------------------------------------------------------+
WITH source_total AS (
    SELECT
        DATE_TRUNC('month', document_date)::date AS period,
        SUM(net_amount)                          AS source_amount,
        COUNT(*)                                 AS source_rows
    FROM erp.invoice_line
    WHERE document_type IN ('invoice', 'credit_note')
      AND document_date >= :period_start
    GROUP BY 1
),

-- CAUTION: settlement_date reads like a document date and is not one.
-- Aggregating on it silently switches the report from accrual to cash basis.
staging_total AS (
    SELECT
        DATE_TRUNC('month', settlement_date)::date AS period,
        SUM(net_amount)                            AS staging_amount,
        SUM(gross_amount_before_tax)               AS staging_alt_amount,
        COUNT(*)                                   AS staging_rows
    FROM staging.derived_turnover
    WHERE settlement_date >= :period_start
    GROUP BY 1
),

mart_total AS (
    SELECT
        DATE_TRUNC('month', reporting_date)::date AS period,
        SUM(reported_amount)                      AS mart_amount,
        COUNT(*)                                  AS mart_rows
    FROM warehouse.commercial_kpi
    WHERE reporting_date >= :period_start
    GROUP BY 1
)

SELECT
    s.period,
    s.source_amount,
    st.staging_amount,
    m.mart_amount,
    ROUND(100.0 * st.staging_amount / NULLIF(s.source_amount, 0), 2) AS staging_pct_of_source,
    ROUND(100.0 * m.mart_amount     / NULLIF(s.source_amount, 0), 2) AS mart_pct_of_source,
    -- The alternative amount column, shown so the difference is visible.
    -- Picking the wrong one is how a KPI ends up overstated by double digits.
    ROUND(100.0 * st.staging_alt_amount / NULLIF(s.source_amount, 0), 2)
                                                                     AS alt_column_pct_of_source,
    s.source_rows,
    st.staging_rows,
    m.mart_rows,
    CASE
        WHEN ABS(1 - m.mart_amount / NULLIF(s.source_amount, 0)) > 0.02
        THEN 'INVESTIGATE'
        ELSE 'OK'
    END                                                              AS verdict
FROM source_total s
LEFT JOIN staging_total st ON st.period = s.period
LEFT JOIN mart_total    m  ON m.period  = s.period
ORDER BY s.period;


-- +-------------------------------------------------------------------------+
-- | 2. ROW-LEVEL COMPLETENESS: what fell out between layers?
-- |    A matching total does not prove matching rows - two errors can cancel.
-- +-------------------------------------------------------------------------+
SELECT
    'missing_in_staging' AS issue,
    e.document_id,
    e.document_date,
    e.net_amount
FROM erp.invoice_line e
LEFT JOIN staging.derived_turnover s ON s.document_id = e.document_id
WHERE e.document_date >= :period_start
  AND s.document_id IS NULL

UNION ALL

SELECT
    'missing_in_mart' AS issue,
    s.document_id,
    s.settlement_date AS document_date,
    s.net_amount
FROM staging.derived_turnover s
LEFT JOIN warehouse.commercial_kpi m ON m.document_id = s.document_id
WHERE s.settlement_date >= :period_start
  AND m.document_id IS NULL

ORDER BY issue, document_date;


-- +-------------------------------------------------------------------------+
-- | 3. HAND-TRACE A SINGLE DOCUMENT THROUGH ALL THREE LAYERS
-- |    Do this BEFORE trusting any aggregate. It is the only reliable way to
-- |    catch layer-level semantic drift, and it takes five minutes.
-- +-------------------------------------------------------------------------+
SELECT 'source'  AS layer, document_id, document_date   AS dt, net_amount AS amt
FROM erp.invoice_line              WHERE document_id = :document_id
UNION ALL
SELECT 'staging' AS layer, document_id, settlement_date AS dt, net_amount AS amt
FROM staging.derived_turnover      WHERE document_id = :document_id
UNION ALL
SELECT 'mart'    AS layer, document_id, reporting_date  AS dt, reported_amount AS amt
FROM warehouse.commercial_kpi      WHERE document_id = :document_id
ORDER BY layer;
