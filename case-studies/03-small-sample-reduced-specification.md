# Small-Sample Modelling with a Reduced Specification

## Context

After the propensity model for the flagship product worked, the natural request was: *do the same for the newest product.* The newest product had been on the market for a fraction of the time. Where the flagship had thousands of conversion events to learn from, this one had fewer than four hundred.

The tempting move was to reuse the proven ~113-parameter specification. That would have produced a model with a beautiful in-sample AUC and no predictive value whatsoever — roughly three and a half conversion events per estimated parameter, well below any defensible threshold.

## Goal

Produce a genuinely predictive model for a product with a small event count, or establish that it cannot be done — and be honest about which.

## My Role

Full ownership: statistical design, fitting, validation, and the write-up explaining to a non-statistical audience why this model has fewer variables than the previous one and why that is a feature.

## Data and Logic

The binding constraint was **events per parameter (EPP)**, not row count. There were plenty of rows — hundreds of thousands of register entities — but only the positive events carry information about what a buyer looks like.

The reduction from the full specification to a reduced one:

- **Dropped** rare industry splits, keeping only grouped classifications with enough positive events
- **Dropped** interaction terms entirely
- **Collapsed** size bands from fine-grained to three tiers
- **Kept** the features that carried signal in the sibling model and were measurable here
- **Result:** 22 parameters, around 17.6 events per parameter — comfortably above the conventional floor

I also had to move the time freeze forward by a year compared to the sibling model, because the product simply did not exist earlier. That meant a shorter out-of-time window, and I noted the reduced statistical power that comes with it.

## Approach

1. Counted positive events *first*, before writing a single line of modelling code, and set the parameter budget from that number
2. Ranked candidate features by expected signal and spent the budget top-down
3. Fitted, then ran the same three-way validation as the sibling model
4. Explicitly tested the "is this just the same customers as the older product" hypothesis, because if it were, the model would be redundant
5. Diagnosed a collinearity trap discovered during fitting

### The collinearity trap

Two features — a broad industry classification and a public-sector sub-type indicator — were almost perfectly collinear in this population: nearly every entity with that industry code *was* that sub-type. Fitted together, they produced unstable coefficients with wide confidence intervals and opposite signs, which reads as "industry does not matter" when in fact it was the two variables cancelling each other out. I detected it on variance inflation, dropped one, and the signal reappeared.

## Sanitized SQL / Logic Example

```sql
-- Step zero of any small-sample model: how many positive events do I actually have?
-- The parameter budget is decided by this query, not by the feature wish-list.
SELECT
    SUM(CASE WHEN is_converted = 1 THEN 1 ELSE 0 END)      AS positive_events,
    COUNT(*)                                               AS total_rows,
    ROUND(100.0 * SUM(CASE WHEN is_converted = 1 THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 3)                        AS base_rate_pct,
    -- conventional floor is about 10 events per estimated parameter
    FLOOR(SUM(CASE WHEN is_converted = 1 THEN 1 ELSE 0 END) / 10.0)
                                                           AS max_defensible_params
FROM model.features
WHERE freeze_date = :freeze_date;

-- Collinearity screen before fitting: which candidate pairs are near-duplicates?
SELECT
    CORR(CASE WHEN industry_group = :public_admin_code THEN 1 ELSE 0 END,
         CASE WHEN is_municipal THEN 1 ELSE 0 END)         AS pearson_r,
    COUNT(*)                                               AS n
FROM model.features
WHERE freeze_date = :freeze_date;
```

## QA and Validation

- Verified the EPP ratio after every specification change, not once at the start
- Ran variance-inflation checks on the final specification
- Confirmed the out-of-time window contained enough positive events to be measurable, and stated the reduced power in the report
- Tested overlap with the sibling product customer base directly, with a significance test rather than eyeballing percentages

## Outcome

- Reduced 22-parameter model: in-sample AUC around 0.90, out-of-time AUC around 0.89 — essentially no degradation
- The overlap test produced the most useful finding: this product buyer profile is **the municipal half of the flagship product profile with the legal-professional half removed**. One public-sector segment appeared at statistically indistinguishable rates in both (p around 0.84), while the professional segment that makes up a substantial share of flagship customers was entirely absent here (0%)
- That reframed the go-to-market question from "who buys this product" to "this product sells into half of our existing base, and the other half will never buy it" — a sharper input to sales planning than a score alone
- The reduced specification is now the template for any future product with a short history

## What This Demonstrates

- Letting the data dictate model complexity instead of reusing a specification because it worked elsewhere
- Setting a parameter budget from positive-event count before modelling begins
- Diagnosing collinearity from unstable coefficients rather than accepting "this variable is not significant"
- Using a formal test to compare two customer populations instead of comparing percentages by eye
- Turning a modelling exercise into a market-structure finding
