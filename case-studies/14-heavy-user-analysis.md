# Heavy-User Analysis for a Large Pilot Deployment

## Context

A single large institutional customer was running a pilot of a metered product across a wide organisation — thousands of individual users spread over many separate offices. Consumption was high and rising, and the commercial question was whether that reflected genuine adoption or a small number of users behaving abnormally.

This mattered concretely: the pilot's consumption profile was going to be the basis for pricing the full contract.

## Goal

Characterise consumption across the pilot population — how concentrated it is, who the heaviest users are, and whether the top of the distribution is real usage or abuse — and produce a breakdown usable in a commercial negotiation.

## My Role

Built the analysis from the raw usage and identity data, verified the outliers individually, and delivered the multi-sheet breakdown.

## Data and Logic

- **Population:** all active users of the deployment across the whole pilot period
- **Dimensions:** individual user, organisational sub-unit derived from the email domain, and time
- **Metrics:** request count, metered consumption, and share of total
- **Concentration:** rank users by consumption and compute the cumulative share held by the top N

### The period assumption that was wrong

The pilot was universally described as having started on a particular date, and the first version of the analysis used that as the window start. The data disagreed: usage records began roughly three months earlier. Someone had been using the deployment during a preparatory phase that was not part of the official pilot narrative. Anchoring the analysis on the assumed start date would have excluded a substantial block of real consumption and understated the baseline going into a pricing negotiation.

I checked the assumption against the data rather than accepting the brief, and reported the true start.

## Approach

1. Established the true first and last usage timestamps before choosing any window
2. Derived the organisational sub-unit from the identity domain, with a mapping table rather than string parsing scattered through the queries
3. Ranked users by consumption and computed cumulative concentration
4. Investigated the extreme outliers individually rather than trimming them
5. Produced a multi-sheet workbook: overall summary, per-sub-unit breakdown, top-N users, and the time series

### Verifying the outliers

The top users consumed at a rate that looked implausible. Rather than treating them as anomalies to be removed, I traced individual sessions and found the explanation: these users were submitting genuinely large documents for analysis, and the metered unit scales with input size. High consumption per request, low request count. It was real, legitimate, expensive usage — and exactly the usage pattern that needed to be priced correctly, so removing it as an outlier would have been the worst possible handling.

## Sanitized SQL / Logic Example

```sql
-- Concentration: what share of total consumption do the top N users hold?
WITH per_user AS (
    SELECT
        u.user_id,
        d.sub_unit_name,
        COUNT(*)                   AS request_count,
        SUM(e.metered_units)       AS metered_units
    FROM usage.event e
    JOIN identity.user u        ON u.user_id = e.user_id
    JOIN identity.domain_map d  ON d.email_domain = u.email_domain
    WHERE e.customer_id = :customer_id
      AND e.event_ts BETWEEN :actual_first_event AND :actual_last_event
    GROUP BY 1, 2
),

ranked AS (
    SELECT
        user_id,
        sub_unit_name,
        request_count,
        metered_units,
        metered_units::numeric / NULLIF(request_count, 0) AS units_per_request,
        ROW_NUMBER() OVER (ORDER BY metered_units DESC)   AS consumption_rank,
        SUM(metered_units) OVER (ORDER BY metered_units DESC
                                 ROWS UNBOUNDED PRECEDING) AS running_units,
        SUM(metered_units) OVER ()                         AS total_units
    FROM per_user
)

SELECT
    consumption_rank,
    sub_unit_name,
    request_count,
    metered_units,
    ROUND(units_per_request, 1)                                  AS units_per_request,
    ROUND(100.0 * running_units / NULLIF(total_units, 0), 1)     AS cumulative_pct
FROM ranked
WHERE consumption_rank <= 100
ORDER BY consumption_rank;
-- units_per_request is what separates heavy legitimate use from abuse.
```

## QA and Validation

- Established the real data window empirically instead of taking the stated pilot start date
- Reconciled total metered consumption against the billing figures for the same period
- Verified the domain-to-sub-unit mapping covered every active domain, with unmapped domains reported rather than dropped
- Traced individual sessions for every extreme outlier before drawing any conclusion about them

## Outcome

- Several thousand active users across the pilot, with a full per-sub-unit breakdown delivered as a four-sheet workbook
- Consumption is heavily concentrated: the top hundred users account for close to **40%** of everything consumed. That is the number that matters for pricing a full rollout, because it means the cost profile is driven by a small identifiable group rather than by headcount
- Every extreme outlier verified as legitimate large-input usage, not abuse — which changed the commercial reading from "we have a misuse problem" to "we have a power-user segment to price for"
- A correction to the assumed pilot start date, with roughly three additional months of real usage brought into scope

## What This Demonstrates

- Checking a stated project timeline against the data before building on it
- Investigating outliers individually instead of trimming them, because in a metered product the outliers *are* the commercial question
- Distinguishing heavy legitimate use from abuse with a ratio metric rather than a threshold
- Producing concentration statistics that answer a pricing question rather than a usage question
- Reconciling against billing before publishing consumption figures
