# Codebook Redesign — 74 Values Into 7

## Context

The operational CRM has a status mechanism that marks accounts as reserved, blocked or otherwise constrained for a period. Over the years the codebook behind it had grown to **74 distinct types**. Nobody used all of them; several meant the same thing under different names; some had not been used in years; and the choice of which to apply was folklore that differed by team.

The practical effect was that reporting on the mechanism was impossible. Any grouping was arbitrary, so any conclusion drawn from it was arbitrary too.

## Goal

Replace the 74-value codebook with a small, defensible set of classes derived from how the mechanism is actually used, and provide the evidence for the mapping.

## My Role

Analysed usage, designed the new classification, wrote it up, and separately reviewed a competing proposal from the business side.

## Data and Logic

The redesign was driven by three measurements rather than by opinion:

- **Concentration.** How is usage distributed across the 74 types? A Gini-style concentration measure showed that a small handful of types account for the overwhelming majority of records — most of the codebook is decoration
- **Behavioural clustering.** Types were clustered on how they behave in practice: who applies them, to what kind of account, in what part of the sales cycle, and what happens afterwards. Types that cluster together are the same type wearing different labels
- **Duration tiers.** How long the status actually persists. Duration turned out to be the dimension that most cleanly separates genuinely different mechanisms — short operational holds, medium-term reservations, and effectively permanent assignments are three different things that were spread arbitrarily across all 74 values

The resulting seven classes are defined by role, applying team and duration tier, with an explicit mapping from every one of the 74 legacy values.

## Approach

1. Profiled all 74 types on volume, applying role, target account type, duration and outcome
2. Measured concentration to establish how much of the codebook carries any weight at all
3. Clustered on behaviour, not on name similarity — names were the least reliable signal in the whole dataset
4. Cut duration into tiers from the observed distribution
5. Derived seven classes and mapped every legacy value into exactly one, with the unmapped-remainder count reported
6. Documented the validity rules, the procedures that write these records, and query recipes for the new classes

## Sanitized SQL / Logic Example

```sql
-- Usage profile per legacy type: volume, who applies it, how long it lasts.
-- Concentration and duration are what drive the new classes; names are ignored.
WITH usage AS (
    SELECT
        s.status_type_id,
        t.status_type_name,
        s.applied_by_role,
        s.valid_from,
        COALESCE(s.valid_to, CURRENT_DATE) AS effective_to,
        COALESCE(s.valid_to, CURRENT_DATE) - s.valid_from AS duration_days
    FROM crm.account_status s
    JOIN crm.status_type_codebook t ON t.status_type_id = s.status_type_id
    WHERE s.valid_from >= :window_start
),

profile AS (
    SELECT
        status_type_id,
        status_type_name,
        COUNT(*)                                            AS record_count,
        COUNT(DISTINCT applied_by_role)                     AS distinct_roles,
        MODE() WITHIN GROUP (ORDER BY applied_by_role)      AS dominant_role,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_days) AS median_days,
        PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY duration_days) AS p90_days
    FROM usage
    GROUP BY 1, 2
)

SELECT
    status_type_name,
    record_count,
    dominant_role,
    median_days,
    p90_days,
    ROUND(100.0 * record_count / SUM(record_count) OVER (), 2) AS pct_of_all,
    ROUND(100.0 * SUM(record_count) OVER (ORDER BY record_count DESC)
          / SUM(record_count) OVER (), 2)                      AS cumulative_pct,
    CASE
        WHEN median_days <=  30 THEN 'short_hold'
        WHEN median_days <= 365 THEN 'reservation'
        ELSE                         'long_term_assignment'
    END AS duration_tier
FROM profile
ORDER BY record_count DESC;
```

## QA and Validation

- Checked that every one of the 74 legacy values maps to exactly one new class, with no silent remainder
- Verified the duration measurement handled open-ended records correctly, since a NULL end date is not a zero-length record
- Tested the clustering for stability across time windows — a classification that changes when the window moves is not a classification
- Compared the proposed classes against how the teams describe their own practice, and investigated every mismatch rather than overriding it

## Reviewing the counter-proposal

The business side independently produced their own restructuring proposal, organised around a set of use cases along two dimensions. I reviewed it in writing rather than defending my own version. The review confirmed the parts that were sound, identified concrete defects with evidence — cases that could not be distinguished from each other in the data, and dimensions that were not independent — and listed the open questions that neither proposal answered. The output was a comparison document, not a rebuttal.

## Outcome

- A seven-class scheme with a complete mapping from all 74 legacy values, each class defined by role, duration tier and applying team
- Reporting on the mechanism became possible for the first time, because the groups are now defined by behaviour rather than by whichever label someone picked
- A documented reference covering validity semantics, the writing procedures, and query recipes
- A written, evidence-based review of the competing proposal that moved the discussion from preference to testable disagreement

## What This Demonstrates

- Deriving a taxonomy from measured behaviour rather than from names or from a workshop
- Using concentration analysis to establish how much of a codebook is real
- Identifying duration as the separating dimension, which was not the obvious candidate
- Testing a classification for stability rather than accepting the first clustering result
- Reviewing a stakeholder counter-proposal on the merits, including confirming what it got right
