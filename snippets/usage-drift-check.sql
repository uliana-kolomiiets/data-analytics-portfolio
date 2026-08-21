/******************************************************************************
  usage-drift-check.sql
  ---------------------------------------------------------------------------
  Detects two things a weekly cost report will not show you:

    (a) a step change in unit price, and
    (b) a step change in units consumed per transaction

  A cost figure is a PRODUCT of these two. When they move in opposite
  directions by similar magnitudes, every aggregate view - weekly total,
  monthly average, cost per customer - stays flat while two large changes
  are happening underneath it.

  The fix is not a better average. It is to stop averaging and decompose.

  USAGE
    :window_start   -- how far back to reconstruct
    :week_start     -- week under review for the drift verdict
 ******************************************************************************/

-- +-------------------------------------------------------------------------+
-- | 1. RECONSTRUCT IMPLIED UNIT PRICE PER TRANSACTION
-- |    Never take the unit price from a configuration or price-list table.
-- |    Commercial terms change outside the system that is supposed to record
-- |    them; the transactions are the only reliable witness.
-- +-------------------------------------------------------------------------+
WITH tx AS (
    SELECT
        event_ts,
        service_key,
        metered_units,
        charged_amount,
        charged_amount / NULLIF(metered_units, 0) AS implied_unit_price
    FROM billing.transaction
    WHERE event_ts >= :window_start
      AND metered_units > 0
      AND charged_amount IS NOT NULL
),

-- +-------------------------------------------------------------------------+
-- | 2. HOURLY RESOLUTION
-- |    A step change is visible at hour resolution and invisible at week
-- |    resolution. Choose the resolution that can see the event.
-- +-------------------------------------------------------------------------+
hourly AS (
    SELECT
        DATE_TRUNC('hour', event_ts) AS hour_start,
        service_key,
        COUNT(*)                     AS tx_count,
        AVG(implied_unit_price)      AS unit_price,
        AVG(metered_units)           AS units_per_tx,
        SUM(charged_amount)          AS total_charged
    FROM tx
    GROUP BY 1, 2
),

-- +-------------------------------------------------------------------------+
-- | 3. LOCATE DISCONTINUITIES
-- +-------------------------------------------------------------------------+
stepped AS (
    SELECT
        hour_start,
        service_key,
        tx_count,
        unit_price,
        units_per_tx,
        total_charged,
        LAG(unit_price)   OVER (PARTITION BY service_key ORDER BY hour_start) AS prev_price,
        LAG(units_per_tx) OVER (PARTITION BY service_key ORDER BY hour_start) AS prev_units
    FROM hourly
    WHERE tx_count >= 5      -- ignore hours too thin to establish a level
)

SELECT
    hour_start,
    service_key,
    tx_count,
    ROUND(unit_price::numeric, 6)                                   AS unit_price,
    ROUND((unit_price / NULLIF(prev_price, 0))::numeric, 4)         AS price_ratio,
    ROUND(units_per_tx::numeric, 1)                                 AS units_per_tx,
    ROUND((units_per_tx / NULLIF(prev_units, 0))::numeric, 4)       AS units_ratio,
    -- The confounding case: both moved, and the cost total did not.
    CASE
        WHEN prev_price IS NULL                                        THEN 'no_baseline'
        WHEN ABS((unit_price   / NULLIF(prev_price, 0)) - 1) > 0.10
         AND ABS((units_per_tx / NULLIF(prev_units, 0)) - 1) > 0.10    THEN 'CONFOUNDED_BOTH_MOVED'
        WHEN ABS((unit_price   / NULLIF(prev_price, 0)) - 1) > 0.10    THEN 'PRICE_STEP'
        WHEN ABS((units_per_tx / NULLIF(prev_units, 0)) - 1) > 0.10    THEN 'VOLUME_STEP'
        ELSE                                                                'stable'
    END                                                             AS verdict
FROM stepped
ORDER BY service_key, hour_start;


/******************************************************************************
  4. PRICE-LIST GOVERNANCE CHECK

  Every service generation actually being charged for must have a row in the
  official price list. A service that is being billed but has no price-list
  entry means commercial terms changed outside the system of record - a
  governance finding, not an analytical one. Escalate rather than patch.
 ******************************************************************************/
SELECT DISTINCT
    t.service_key,
    MIN(t.event_ts) AS first_charged,
    MAX(t.event_ts) AS last_charged,
    COUNT(*)        AS tx_count
FROM billing.transaction t
LEFT JOIN billing.price_list p
       ON p.service_key = t.service_key
      AND t.event_ts BETWEEN p.valid_from AND COALESCE(p.valid_to, CURRENT_DATE)
WHERE p.service_key IS NULL
  AND t.event_ts >= :window_start
GROUP BY t.service_key
ORDER BY tx_count DESC;
