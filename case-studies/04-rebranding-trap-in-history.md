# A Rebranding Trap in Historical Data

## Context

The third product in the modelling programme looked like a dead end. A first pass at the order history returned about seventy-five rows — nowhere near enough to fit anything. The obvious conclusion, and the one that had already been drawn informally, was: *this product has too little history, skip it.*

That conclusion was wrong, and the reason it was wrong is a data problem rather than a statistics problem: the product had been **renamed**. Years of sales history sat under the previous name, invisible to anyone searching for the current one.

## Goal

Establish the true addressable history for the product, then build and validate its propensity model — and, separately, work out whether the same trap was hiding elsewhere in the catalogue.

## My Role

I found the rename, rebuilt the history, fitted and validated the model, and wrote up both the finding and the general lesson for the team.

## Data and Logic

- **The trap:** the product catalogue stores the *current* commercial name. Order lines store the name as it was at the time of sale. A straightforward filter on the current name silently drops every pre-rename order
- **Detection:** rather than searching by name, I searched by product-class and by the internal item identifiers that survive a rename, then listed every distinct name those identifiers had ever carried
- **Result:** the true history was roughly three times larger than the seventy-five rows, with 214 recorded wins — enough to model
- **Additional check:** I ran the same identifier-based sweep across the whole catalogue looking for other name/identifier mismatches, and flagged case-inconsistent duplicates of the same product name (the same product recorded under two different capitalisations, which any naive `GROUP BY` splits into two products)

## Approach

1. Reproduced the seventy-five-row result to confirm the original method, then broke it deliberately
2. Traced the product through the class hierarchy instead of the name string
3. Pulled the full distinct name history per identifier to prove the rename rather than assume it
4. Rebuilt the label and feature table on the corrected history
5. Fitted, validated out-of-time, and compared the resulting customer profile against the two sibling products
6. Documented the identifier-not-name rule as a standing convention

## Sanitized SQL / Logic Example

```sql
-- WRONG: silently drops every order placed before the product was renamed.
SELECT COUNT(*)
FROM crm.order_line
WHERE product_name = :current_name;

-- RIGHT: resolve through the stable identifier, then inspect every historical
-- name it has carried. This is what surfaced the rename.
WITH product_ids AS (
    SELECT DISTINCT item_id
    FROM crm.catalogue_item
    WHERE product_class = :product_class
),

name_history AS (
    SELECT
        ol.item_id,
        TRIM(LOWER(ol.product_name_at_sale)) AS name_variant,
        MIN(ol.order_date)                   AS first_seen,
        MAX(ol.order_date)                   AS last_seen,
        COUNT(*)                             AS order_count
    FROM crm.order_line ol
    JOIN product_ids p ON p.item_id = ol.item_id
    GROUP BY 1, 2
)

SELECT *
FROM name_history
ORDER BY item_id, first_seen;
-- Two name variants with non-overlapping date ranges on the same item_id
-- is the signature of a rebrand, not of two products.
```

## QA and Validation

- Confirmed the two name variants had non-overlapping date ranges — an overlap would have meant two genuinely different products, not a rename
- Cross-checked the rebuilt order count against the finance ledger for the same period
- Verified that the pre-rename orders were not already counted under a different product family (no double counting)
- Re-ran the full-catalogue sweep to make sure no *other* product in the modelling programme had the same problem

## Outcome

- The product went from "not enough data to model" to a validated model: out-of-time AUC around 0.84 with **no degradation** against in-sample
- The customer profile turned out to be the **inverse** of the flagship product. Where the flagship sells heavily into the public sector, here the public-sector indicator was not significant at all and one public sub-segment was actively negative. The ideal customer is a large private company. Two products from the same catalogue, sold by the same sales force, with opposite ideal customers
- Two important limitations went into the report rather than being buried: every recorded win had been preceded by an outbound contact, so the model partly measures *who we called* rather than *who would buy*; and calibration was off by more than an order of magnitude, so again: ranking, not forecasting
- The identifier-not-name rule and the case-duplicate warning became standing conventions for the team

## What This Demonstrates

- Refusing to accept a convenient negative result ("not enough data") without testing how the data was retrieved
- Understanding that entity resolution across renames is a routine failure mode in commercial history, not an exotic one
- Proving a rename from date ranges instead of assuming it from a name similarity
- Generalising a single find into a reusable convention and sweeping the rest of the catalogue for it
- Reporting selection bias in the label honestly, including when it weakens my own result
