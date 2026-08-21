# Defending a Model Under Challenge — Out-of-Time Validation

## Context

When I presented the propensity model, a senior manager pushed back on the headline number. The objection was the right one: *"an AUC of 0.9 on a model fitted to your own history usually means the model has memorised the history."* It was not a hostile question — it was the question I would have asked — and it needed a real answer, not a reassurance.

There was a second, quieter problem underneath it. The model was being read by some stakeholders as a forecast ("this account has a 40% chance of buying"), when it was built as a ranking instrument.

## Goal

Establish whether the model was overfitted, and state plainly what the score can and cannot be used for.

## My Role

I designed and ran the validation, wrote the defence document, and — where the challenge was partly right — said so in writing.

## Data and Logic

Three independent checks, chosen because they fail in different ways:

- **In-sample AUC** — the number under dispute; kept as the reference point
- **k-fold cross-validation** — detects variance-driven overfitting (too many parameters for the data)
- **Out-of-time validation** — freeze the model on history up to a cut-off date, then score the period *after* it and measure how well it predicted conversions it had never seen. This is the only one of the three that detects the failure mode that actually matters commercially: the market changing under the model

A fourth, separate issue: **label dating**. A conversion has to be dated by when it actually happened, and the order history spread across several channels with different date semantics. Dating a conversion by only one channel would silently push events across the freeze line and leak the future into the training set.

## Approach

1. Rebuilt the conversion date as the earliest evidence across all order channels, not the date from the most convenient table
2. Split strictly on time — every feature computed as of the freeze date, no exceptions
3. Refitted on the pre-freeze period only and scored the post-freeze period
4. Compared all three metrics side by side
5. Separately tested **calibration**: how do predicted probabilities compare to observed conversion rates
6. Wrote up the result including the part that supported the challenge

## Sanitized SQL / Logic Example

```sql
-- A conversion must be dated by the EARLIEST evidence across all order channels.
-- Using a single channel date moves events across the freeze line and leaks.
WITH conversion_evidence AS (
    SELECT entity_id, first_order_date     AS event_date FROM crm.channel_renewals
    UNION ALL
    SELECT entity_id, contract_start_date  AS event_date FROM crm.channel_contracts
    UNION ALL
    SELECT entity_id, order_date           AS event_date FROM crm.channel_selfservice
    UNION ALL
    SELECT entity_id, activation_date      AS event_date FROM crm.channel_partner
),

conversion AS (
    SELECT entity_id, MIN(event_date) AS converted_on
    FROM conversion_evidence
    WHERE event_date IS NOT NULL
    GROUP BY entity_id
)

SELECT
    f.entity_id,
    CASE WHEN c.converted_on <  :freeze_date THEN 'train'
         WHEN c.converted_on >= :freeze_date THEN 'holdout'
         ELSE 'train' END                                      AS split,
    CASE WHEN c.converted_on <  :freeze_date THEN 1 ELSE 0 END AS y_train,
    CASE WHEN c.converted_on >= :freeze_date THEN 1 ELSE 0 END AS y_holdout
FROM model.features f
LEFT JOIN conversion c ON f.entity_id = c.entity_id;
```

## QA and Validation

- Confirmed the freeze date left enough post-freeze conversions to measure anything at all — a holdout with too few positive events produces a meaningless AUC
- Verified no feature in the training set was computed from post-freeze data
- Checked that the holdout period was not distorted by an unusual commercial event
- Compared predicted vs. observed conversion rates by score decile to measure calibration explicitly

## Outcome

| Check | Result | Reading |
|---|---|---|
| In-sample AUC | around 0.90 | The number under challenge |
| Cross-validated AUC | around 0.90 | No variance-driven overfit |
| **Out-of-time AUC** | **around 0.88** | Small, expected degradation — the model generalises |

The model held. A drop of roughly two points from in-sample to out-of-time is what a sound model looks like; a collapse to 0.6-0.7 is what overfitting looks like, and that did not happen.

**But the challenge was half right, on a point nobody had raised.** Calibration was poor: the model over-predicted absolute conversion probability by a factor of roughly four. So the score is a valid *ranking* instrument — call the top decile first — and an invalid *forecast* — do not put those percentages in a revenue plan. I wrote that limitation into the report as a boxed warning rather than a footnote, and it is now the standard caveat on every scored list I hand over.

## What This Demonstrates

- Treating a stakeholder challenge as a testable hypothesis rather than something to argue with
- Knowing which validation detects which failure mode, and running all three
- Understanding that time-based leakage usually enters through the label date, not the features
- Separating discrimination from calibration — and being explicit that a model can be good at one and bad at the other
- Publishing a limitation of my own work that nobody had asked about
