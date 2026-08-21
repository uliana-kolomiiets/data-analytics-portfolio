# Data Analytics and BI Engineering Portfolio

This repository highlights selected case studies from my current work in customer analytics, predictive modelling, and BI/reporting engineering. The projects focus on propensity modelling, model validation, usage and revenue analytics, cross-system data reconciliation, pipeline maintenance, and turning ad-hoc analysis into automated, reviewable products.

The examples are sanitized and simplified to protect internal systems, commercial terms, and customer data while still showing how I approach an analytical problem from business question to production artefact.

> This is the second chapter of my public portfolio. The earlier one — [targeting-campaign-portfolio](https://github.com/uliana-kolomiiets/targeting-campaign-portfolio) — covers lifecycle marketing targeting and campaign operations. Together they show the move from campaign execution into data analytics and modelling.

## About Me

Data analyst / analytics engineer at a professional-information and software group in Central Europe, working on the products' commercial data: who buys, why they churn, what they consume, and what it costs.

I sit between the operational CRM, the ERP, the product databases and the warehouse — turning business questions into models and reports that survive being challenged. A large share of my work is not "produce a number" but "prove the number is right", including proving my own earlier numbers wrong.

**Core skills:** SQL (PostgreSQL, MS SQL, BigQuery), Python (pandas, statsmodels, scikit-learn), logistic regression and propensity scoring, out-of-time validation, Airflow, data modelling and lineage, Excel/Office automation, executive reporting

## Case Studies

| # | Project | Type | Skills Demonstrated |
|---|---------|------|---------------------|
| 1 | [Ideal-Customer Propensity Model](case-studies/01-ideal-customer-propensity-model.md) | Predictive Modelling | Logistic regression, feature design, scoring a national register, whitespace analysis |
| 2 | [Defending a Model Under Challenge](case-studies/02-out-of-time-validation.md) | Model Validation | Out-of-time split, cross-validation, calibration vs. ranking, label-date correctness |
| 3 | [Small-Sample Modelling](case-studies/03-small-sample-reduced-specification.md) | Statistical Rigour | Events-per-parameter budgeting, specification reduction, collinearity diagnosis |
| 4 | [A Rebranding Trap in Historical Data](case-studies/04-rebranding-trap-in-history.md) | Data Investigation | Entity resolution across renames, disproving a wrong conclusion, segment inversion |
| 5 | [Next-Best-Product Logic](case-studies/05-next-best-product-logic.md) | Applied Modelling | Sequencing rules, backtesting, exposing a false pattern in launch-date data |
| 6 | [Expected-Value Scoring: A Negative Result](case-studies/06-expected-value-negative-result.md) | Analytical Honesty | Hedonic value model, cost/benefit of added complexity, recommending "don't ship" |
| 7 | [Weekly Reporting Automation](case-studies/07-weekly-reporting-automation.md) | Automation | Python generator, Office COM, append-only writes, mandatory backups, governance constraints |
| 8 | [Read-Only Verification Job](case-studies/08-read-only-verification-job.md) | Data Quality | Drift detection, silent config-change detection, evidence gaps, safe-by-design tooling |
| 9 | [Unit-Price Change Forensics](case-studies/09-unit-price-change-forensics.md) | Production Investigation | Confounded metrics, timestamp forensics, untrustworthy source fields |
| 10 | [Revenue KPI Reconciliation](case-studies/10-revenue-kpi-reconciliation.md) | Cross-System Audit | Three-layer lineage, formula reverse-engineering, retracting my own findings |
| 11 | [Codebook Redesign: 74 Values to 7](case-studies/11-codebook-redesign.md) | Data Modelling | Concentration analysis, clustering, duration tiers, reviewing a stakeholder counter-proposal |
| 12 | [Customer Lifecycle Model](case-studies/12-customer-lifecycle-model.md) | Business Modelling | Phase/period modelling from transactional history, measured renewal and win-back rates |
| 13 | [Pipeline Fix: Orphaned Foreign Keys](case-studies/13-pipeline-fk-violation-fix.md) | Data Engineering | Airflow DAG debugging, minimal guarded fix, review-gated deployment |
| 14 | [Heavy-User Analysis for a Large Pilot](case-studies/14-heavy-user-analysis.md) | Usage Analytics | Concentration metrics, outlier verification, correcting a wrong period assumption |
| 15 | [Product-Basket and Add-On Analysis](case-studies/15-product-basket-analysis.md) | Segmentation | Association rules, k-means personas, basket semantics, dead-SKU detection |

## Yearly Reports

Impact summaries highlighting key improvements and initiatives by year.

- [**2026** — Analytics Foundation](yearly-reports/2026-improvements.md): propensity modelling programme across three products, weekly reporting automation, cross-system revenue reconciliation, data-model documentation

## SQL Snippets

Sanitized examples of patterns I build regularly:

- [`propensity-feature-build.sql`](snippets/propensity-feature-build.sql) — Feature table for a customer propensity model
- [`out-of-time-split.sql`](snippets/out-of-time-split.sql) — Train/holdout construction with a hard time freeze
- [`conversion-date-resolution.sql`](snippets/conversion-date-resolution.sql) — Earliest-evidence label dating across several order channels
- [`usage-drift-check.sql`](snippets/usage-drift-check.sql) — Unit-price and consumption drift detection
- [`basket-association.sql`](snippets/basket-association.sql) — Product co-occurrence, support, confidence and lift
- [`reconciliation-qa.sql`](snippets/reconciliation-qa.sql) — Cross-system totals and row-level reconciliation checks

## How I Work

1. **Clarify** what business decision the number will actually be used for — ranking, forecasting, or reporting
2. **Model** with a specification the data can carry, not the one that looks most complete
3. **Validate** out-of-time, not just in-sample — and state where the model is wrong
4. **Automate** once the analysis is repeated, with backups and read-only checks around it
5. **Retract** my own findings when verification does not hold them up, in writing
