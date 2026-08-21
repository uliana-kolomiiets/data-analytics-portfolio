# Expected-Value Scoring — A Negative Result

## Context

A propensity score ranks prospects by probability of buying. It says nothing about how much they would be worth. The natural improvement, and one I proposed myself, is to rank by **expected value** instead: probability multiplied by predicted contract value. A large organisation with a 10% chance is worth more than a small one with a 20% chance.

It is an obviously good idea. I built it, and then I had to recommend against shipping it.

## Goal

Determine whether expected-value ranking beats plain propensity ranking by enough to justify the added complexity — across all three products, not just the one where it looked best.

## My Role

Proposed the approach, built the value model, ran the comparison, and wrote the recommendation not to adopt it.

## Data and Logic

Two components:

- **P** — probability of conversion, from the existing propensity models
- **V** — predicted contract value, which had to be modelled, because for a prospect there is no contract yet

For **V** I fitted a hedonic price model: regress observed contract value on the observable attributes of the buying organisation (size band, sector, legal form, region, product configuration). If value is predictable from attributes, the model will show it.

Then I compared three rankings on the same holdout:
1. Rank by P
2. Rank by P × V
3. Rank by V alone (as a control)

Evaluated on realised value captured in the top decile, not on AUC — because the question is commercial, not statistical.

## Approach

1. Assembled the value dataset from actual closed contracts, deduplicated per organisation
2. Fitted the hedonic model and inspected its explanatory power *before* using it anywhere
3. Combined P and V into an expected-value score
4. Ranked the holdout under each of the three rules
5. Measured realised value captured at equal call volume
6. Repeated per product, since the products have very different value distributions

## Sanitized SQL / Logic Example

```sql
-- Value model input: one row per organisation, first contract value only,
-- so that renewals do not turn one customer into several observations.
WITH first_contract AS (
    SELECT
        customer_id,
        contract_value,
        contract_date,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY contract_date
        ) AS rn
    FROM crm.contract
    WHERE product_family = :product_family
      AND contract_status = 'confirmed'
),

value_base AS (
    SELECT
        f.customer_id,
        f.contract_value,
        e.employee_band,
        e.sector_group,
        e.legal_form_code,
        e.territory_id
    FROM first_contract f
    JOIN model.features e ON e.entity_id = f.customer_id
    WHERE f.rn = 1
)

-- How much of contract value is explained by observable attributes at all?
-- Variance of the group means over total variance is the ceiling for any
-- attribute-based value model. Here it was low, and that killed the idea.
SELECT
    sector_group,
    employee_band,
    COUNT(*)                    AS n,
    AVG(contract_value)         AS mean_value,
    STDDEV_POP(contract_value)  AS sd_within_cell
FROM value_base
GROUP BY sector_group, employee_band
ORDER BY n DESC;
```

## QA and Validation

- Deduplicated to first contract per organisation so renewals did not inflate the sample
- Checked the value distribution for the long right tail that makes mean-based models unstable, and tested a log specification as well
- Verified the comparison used the same holdout population and the same call volume for every rule
- Ran the comparison separately per product instead of pooling, because a pooled result would have hidden the variation

## Outcome

The hedonic value model explained very little: R² around 0.08. Contract value is driven mostly by things not visible in the register — negotiated scope, incumbent supplier, budget cycle — and almost not at all by organisation attributes.

Consequently, expected-value ranking produced:

| Product | Uplift in captured value vs. plain propensity ranking |
|---|---|
| Flagship | around +2% |
| Municipal product | around +0.3% |
| Private-sector product | not transferable (value model too weak to use) |

**Recommendation: do not adopt.** A 0.3–2% uplift does not pay for a second model that has to be maintained, re-validated and explained, and whose weakness would eventually be discovered by someone else at a worse moment. The plain propensity ranking stays.

I wrote the negative result up in full — the method, the diagnostics, the numbers — so that the next person to have this idea can see it was tested properly rather than re-running it from scratch.

## What This Demonstrates

- Proposing an improvement and then killing it on evidence, including when it was my own idea
- Evaluating on the commercial metric (value captured at fixed effort) rather than the statistical one
- Diagnosing *why* a model failed rather than reporting that it did
- Weighing model quality against maintenance cost, not just accuracy
- Documenting negative results so they are not silently repeated
