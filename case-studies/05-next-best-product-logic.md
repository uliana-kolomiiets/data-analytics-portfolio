# Next-Best-Product Logic

## Context

With propensity models built for three products, the obvious next question from the business was: *given a customer who already owns something, what do we sell them next?*

The prevailing assumption in the room was that there is a natural product ladder — customers start with the entry product, then step up. Several people could describe the ladder from memory. It was worth checking before building anything on top of it.

## Goal

Produce a next-best-product recommendation rule that a salesperson can apply from a CRM card without a data scientist in the room, and test whether the assumed product ladder actually exists.

## My Role

Designed the rule, ran the backtest, and delivered the finding that contradicted the assumption.

## Data and Logic

- **Population:** all customers owning at least one product
- **Candidate rules tested:**
  - The assumed ladder (fixed canonical order)
  - Highest propensity score across the remaining products
  - A segment-conditional rule: score-ordered, but with the ordering allowed to differ by customer type
- **Backtest design:** freeze the customer portfolio as of a past date, apply each rule, and check against what those customers actually bought afterwards
- **Critical control:** ownership already held must be excluded from the recommendation, otherwise the rule scores well by recommending things people already have

### Why the ladder was an illusion

The apparent ladder is an artefact of **product launch dates**. If product A has existed for fifteen years and product C for two, then almost every C owner will also own A — not because A leads to C, but because A was the only thing available when they first bought. Ordering products by "how often they come first" reproduces the launch calendar, not customer behaviour.

I tested this by conditioning on customers who joined *after* all three products existed. In that cohort the ladder disappeared.

## Approach

1. Built the ownership matrix per customer as of the freeze date
2. Excluded already-owned products from each customer candidate set
3. Applied each candidate rule and recorded its recommendation
4. Compared recommendations to actual subsequent purchases
5. Re-ran the ladder test on the launch-date-controlled cohort
6. Expressed the winning rule in plain language that fits on a CRM card

## Sanitized SQL / Logic Example

```sql
-- Next-best-product candidates: score-ordered, already-owned removed.
WITH owned AS (
    SELECT DISTINCT customer_id, product_key
    FROM crm.active_subscription
    WHERE valid_from <= :freeze_date
      AND (valid_to IS NULL OR valid_to > :freeze_date)
),

candidates AS (
    SELECT
        s.customer_id,
        s.product_key,
        s.propensity_score,
        c.customer_segment
    FROM model.propensity_score s
    JOIN crm.customer c ON c.customer_id = s.customer_id
    LEFT JOIN owned o
           ON o.customer_id = s.customer_id
          AND o.product_key = s.product_key
    WHERE s.freeze_date  = :freeze_date
      AND o.product_key IS NULL      -- drop what they already own
),

ranked AS (
    SELECT
        customer_id,
        product_key,
        customer_segment,
        propensity_score,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY propensity_score DESC
        ) AS rn
    FROM candidates
)

SELECT customer_id, customer_segment, product_key AS next_best_product
FROM ranked
WHERE rn = 1;
```

## QA and Validation

- Verified that no recommendation matched a product the customer already owned
- Checked that customers with no remaining candidates were dropped rather than assigned a default
- Confirmed the backtest window did not overlap the model training period
- Ran the ladder test on the launch-controlled cohort as an explicit falsification attempt, not as a robustness afterthought

## Outcome

- The winning rule was the segment-conditional one, expressible in a single sentence a salesperson can act on: *lead with the flagship product; for public-sector customers offer the municipal product second, otherwise the private-sector product; skip anything already owned.* Backtest accuracy around 74%
- **There is no canonical product ladder.** It looks like one only because the products launched years apart. This was the finding management actually needed, because the informal ladder was already shaping how new products were positioned
- The rule was specified for the CRM team as a card-level recommendation with the ownership exclusion built in

## What This Demonstrates

- Testing an assumption the business treats as settled, and designing the test to falsify it
- Recognising a launch-date artefact masquerading as customer behaviour
- Backtesting a decision rule rather than reporting model accuracy and calling it done
- Building the trivial-but-fatal control (exclude what they already own) into the logic rather than the review checklist
- Compressing a model output into a rule a non-analyst can apply unaided
