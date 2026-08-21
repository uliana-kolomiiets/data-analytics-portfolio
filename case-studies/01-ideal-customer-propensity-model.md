# Ideal-Customer Propensity Model

## Context

Sales had a working definition of the "ideal customer" for the company's flagship product, but it was folklore: a handful of segment rules that everyone quoted and nobody had tested. Meanwhile the company sits on two large datasets that had never been joined for this purpose — its own CRM history (who was approached, who bought, who refused) and the national public business register covering roughly half a million legal entities.

The business question was blunt: *of all the organisations in the country that are not our customers, which ones should a salesperson call first?*

## Goal

Replace the folklore definition with a scored, ranked list of the entire addressable market, plus a written statement of which customer attributes actually predict a purchase and which ones only look like they do.

## My Role

I owned the whole thing end to end: sourcing and joining the data, designing the feature set, fitting and validating the model, scoring the register, writing the report, and presenting it to management.

## Data and Logic

- **Population:** every legal entity in the public business register, joined to the CRM by registration number
- **Label:** did this organisation ever convert into a paying customer of the product
- **Feature families (~113 parameters in the full specification):**
  - Legal form, size band, and age of the organisation
  - Industry classification (grouped, then selectively split where volume allowed)
  - Public-sector vs. private, and within public sector the sub-type (municipal, educational, state administration)
  - Geography, resolved to the true internal sales-territory key rather than an administrative-region proxy
  - Relationship history: prior contact, prior product ownership, prior refusals
- **Exclusions:** entities in liquidation, duplicates arising from case-inconsistent name records, and internal/test records

The single most important data decision was the geography key. The obvious column looked like a region, and using it would have produced a plausible but wrong territory story. The real territory assignment lives on a separate address-hierarchy table and had to be resolved through the municipal-district level.

## Approach

1. Rebuilt the customer/non-customer label from order history rather than trusting a CRM "is customer" flag, which turned out to be stale for a meaningful share of records
2. Built the feature table at entity level, one row per organisation, with every feature defined as of a fixed point in time
3. Fitted a logistic regression — deliberately chosen over a black-box model because the deliverable had to be *explainable to a sales director*, not just accurate
4. Checked each coefficient against a business reading; where a coefficient contradicted intuition, I went back to the data rather than to the model
5. Scored the full register and produced a ranked call list, plus a whitespace analysis
6. Wrote the findings as a standalone HTML report with an embedded interactive calculator so stakeholders could test their own hypothetical organisation

## Sanitized SQL / Logic Example

```sql
-- Feature table: one row per legal entity, features fixed as of the freeze date
WITH register AS (
  SELECT
      entity_id,
      legal_form_code,
      industry_code,
      employee_band,
      founded_year,
      municipality_id
  FROM public_register.entity
  WHERE status_code = 'active'
),

-- True sales territory: NOT the administrative region column on the entity,
-- which is a proxy that misassigns a whole border area.
territory AS (
  SELECT
      m.municipality_id,
      d.sales_branch_id AS territory_id
  FROM public_register.municipality m
  JOIN internal.municipal_district d
    ON m.district_id = d.district_id
),

-- Label built from actual orders, not from the CRM customer flag
converted AS (
  SELECT DISTINCT entity_id
  FROM crm.order_line
  WHERE product_family = :product_family
    AND order_date < :freeze_date
    AND order_status = 'confirmed'
)

SELECT
    r.entity_id,
    r.legal_form_code,
    r.industry_code,
    r.employee_band,
    DATE_PART('year', :freeze_date) - r.founded_year AS entity_age_years,
    t.territory_id,
    CASE WHEN c.entity_id IS NOT NULL THEN 1 ELSE 0 END AS is_converted
FROM register r
JOIN territory t ON r.municipality_id = t.municipality_id
LEFT JOIN converted c ON r.entity_id = c.entity_id;
```

## QA and Validation

- Compared the model-derived label count against the finance-side customer count and reconciled the difference before fitting anything
- Checked class balance per feature level and collapsed levels with too few positive events
- Verified that no feature was a post-outcome artefact (e.g. a support-contract flag that only exists *because* the entity is already a customer)
- Ran the score distribution against known customers as a sanity check — existing customers had to land high, and they did
- Full out-of-time validation was done separately and is written up in [case study 2](02-out-of-time-validation.md)

## Outcome

- A model with in-sample AUC ≈ 0.90 and a ranked score for every entity in the register
- A segment the folklore had badly underrated: one public-sector sub-type turned out to account for roughly 30% of all recent wins at a ~12.6% conversion rate, while the existing sales narrative barely mentioned it
- A whitespace finding that changed the sales plan more than the model did: among the highest-scoring prospects, only a few dozen had never been contacted at all, while roughly 1,500 had been contacted once and then left dormant for years. The opportunity was not "find new names", it was "reopen the ones we already dropped"
- The report and the scored register were handed to the CRM team for operational use, with an A/B test of the ranking as the agreed next step

## What This Demonstrates

- Building a predictive model on real, messy, multi-source data rather than a prepared dataset
- Choosing an explainable model because the audience, not the metric, demanded it
- Catching the difference between a convenient key and the correct key before it silently corrupts a territory story
- Distrusting a status flag and rebuilding the label from transactions
- Delivering a finding that reframes the business question, not just answers it
