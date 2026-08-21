# Unit-Price Change Forensics

## Context

A supplier unit price for a metered service was expected to drop by roughly a fifth. Weeks later the weekly cost report showed no such drop. The reasonable readings were: the discount never took effect, or it took effect and something else got more expensive at the same time, or the report is wrong.

I had also previously stated in a report that the change had *not* happened — based on exactly this absence of movement in the averages. That statement was wrong, and correcting it was part of the job.

## Goal

Determine whether the price change took effect, when exactly, and why the reporting did not show it.

## My Role

Ran the investigation, found the answer, and issued a written correction of my own earlier conclusion.

## Data and Logic

The key realisation is that a cost-per-period metric is a **product of two moving quantities**: unit price and units consumed. If both move in opposite directions by similar magnitudes, the product barely changes, and any aggregate view — weekly average, monthly total, cost per customer — shows a flat line while two large changes are happening underneath it.

So the investigation had to decompose rather than aggregate:

- **Unit price** — reconstructed from the ratio of charged amount to metered units, per individual transaction, at the finest available time resolution
- **Units consumed** — measured separately per transaction
- **Effective date** — found by looking for the discontinuity in the reconstructed unit price, not by trusting any configuration record

## Approach

1. Stopped aggregating. Reconstructed the implied unit price transaction by transaction and plotted it against time
2. Located the discontinuity — a clean step change, at a specific evening timestamp on a specific date, not on the date it had been assumed to happen
3. Measured units consumed per transaction on both sides of the step, and found they had risen substantially — enough to cancel most of the price reduction in any aggregate
4. Went looking for the change in the official price-list table, and did not find it
5. Checked the source fields the reporting relied on for trustworthiness, and found one that lies

## Sanitized SQL / Logic Example

```sql
-- Do not average. Reconstruct the implied unit price per transaction and
-- look for a discontinuity. Aggregates hide step changes that are cancelled
-- out by a simultaneous change in volume.
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
),

hourly AS (
    SELECT
        DATE_TRUNC('hour', event_ts) AS hour_start,
        service_key,
        COUNT(*)                             AS tx_count,
        MIN(implied_unit_price)              AS min_price,
        MAX(implied_unit_price)              AS max_price,
        AVG(implied_unit_price)              AS avg_price,
        AVG(metered_units)                   AS avg_units_per_tx
    FROM tx
    GROUP BY 1, 2
)

SELECT
    hour_start,
    service_key,
    tx_count,
    ROUND(avg_price::numeric, 6)        AS unit_price,
    ROUND(avg_units_per_tx::numeric, 1) AS units_per_tx,
    ROUND((avg_price / NULLIF(LAG(avg_price)
        OVER (PARTITION BY service_key ORDER BY hour_start), 0))::numeric, 4)
                                        AS price_ratio_vs_prev_hour
FROM hourly
ORDER BY service_key, hour_start;
-- The step change is visible at hour resolution and invisible at week resolution.
```

## QA and Validation

- Confirmed the discontinuity was a genuine step and not a composition shift, by holding the service mix constant across the boundary
- Cross-checked the reconstructed unit price against the supplier invoice for the period
- Verified the volume increase was real usage, not a change in how units were counted
- Checked whether the unreliable source field was wrong everywhere or only for certain services, before recommending anything

## Outcome

Three findings, in increasing order of importance:

1. **The price change was real, and I had said it was not.** It took effect at a precise evening timestamp, several days earlier than assumed. I corrected my earlier written statement explicitly rather than quietly updating the number
2. **It was invisible because it was confounded.** Units consumed per transaction rose by roughly a third over the same period, almost exactly cancelling the price reduction in every aggregate view. Two large offsetting changes had been reported as "nothing happened"
3. **The change bypassed the official price list.** The price-list table had no row for the affected service generation at all, meaning commercial terms had changed outside the system that is supposed to be the record of commercial terms. That is a governance finding, not an analytical one, and it was escalated as such

A fourth, narrower finding: a service-identifier field in the transaction log does not reliably state which service actually handled the request, so any cost attribution built on it is unsound. Cost attribution was moved onto the fields that are trustworthy. Relatedly, auxiliary tooling calls turned out to cost more per invocation than the primary service they support — the opposite of the assumption in the cost model.

## What This Demonstrates

- Decomposing a flat metric instead of accepting it, on the reasoning that a ratio can hide two large offsetting movements
- Choosing a time resolution fine enough to see the event, when the reporting resolution was hiding it
- Retracting my own published conclusion in writing when the evidence went the other way
- Distinguishing an analytical finding from a governance finding and escalating the second appropriately
- Auditing source fields for trustworthiness before building attribution on them
