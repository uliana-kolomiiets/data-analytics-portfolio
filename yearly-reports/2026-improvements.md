# 2026 — Year in Review: Analytics Foundation

This year was a transition from campaign operations into data analytics and modelling, and then from ad-hoc analysis into things that keep working without me. The through-line is the same one that ran through my earlier targeting work: get the definition right, prove the number, and make the process survive the next person who runs it.

---

## 1. A Propensity Modelling Programme Across Three Products

### What I Did

Built customer propensity models for three products in the catalogue, each with a different data situation, and each requiring a different answer to "can this even be modelled".

| Product | Situation | Approach |
|---|---|---|
| Flagship | Thousands of conversion events, long history | Full specification, ~113 parameters |
| Newest | Fewer than 400 events | Reduced 22-parameter specification, budgeted by events-per-parameter |
| Third | Apparently ~75 rows of history | History was hidden behind a product rename; recovered and modelled |

All three were validated out of time, not just in sample. All three landed at out-of-time AUC in the 0.84–0.89 range with no collapse against in-sample performance.

### Result

The entire national business register — around half a million entities — is scored and ranked. The addressable-market question moved from folklore to a sorted list.

### Skills Demonstrated
- Logistic regression on real multi-source commercial data
- Matching model complexity to available evidence rather than reusing a specification
- Entity resolution across a product rename that had made years of history invisible

---

## 2. Making Model Claims Survive Challenge

### What I Did

When a senior manager challenged the headline AUC as probable overfitting, I treated it as a hypothesis and tested it three ways — in-sample, cross-validated, and out-of-time — rather than defending the original number.

The model held. But running the validation properly surfaced something nobody had asked about: **calibration was poor**, over-predicting absolute probability by roughly a factor of four. The score is a valid ranking instrument and an invalid forecast.

### Result

That limitation is now a boxed warning on every scored list I hand over, not a footnote. Two other stakeholders had been about to use the percentages as conversion forecasts in planning.

### Skills Demonstrated
- Distinguishing which validation catches which failure mode
- Separating discrimination from calibration
- Publishing a limitation of my own work unprompted

---

## 3. Killing My Own Idea: Expected-Value Scoring

### What I Did

Proposed ranking prospects by expected value (probability × predicted contract value) instead of probability alone. Built the hedonic value model needed for it, and evaluated the result on captured value at fixed call volume — the commercial metric, not the statistical one.

### Result

The value model explained almost nothing (R² around 0.08). Contract value is driven by negotiated scope and budget cycle, not by observable organisation attributes. Uplift over plain propensity ranking came out at roughly +0.3% to +2% depending on the product.

**Recommended against adopting it.** A second model to maintain, re-validate and explain does not pay for a rounding error. Wrote the negative result up in full so the idea does not get re-run from scratch in a year.

### Skills Demonstrated
- Evaluating on the business metric rather than the model metric
- Cost/benefit reasoning about model maintenance, not just accuracy
- Documenting negative results properly

---

## 4. Reporting: From Manual Assembly to Two Clicks

### What I Did

Automated a weekly commercial report that had been assembled by hand — queries run manually, results pasted into a shared workbook, summary typed into an email.

My first architecture was ruled out on internal policy grounds: the shared cloud spreadsheet is a governed artefact and programmatic writes are not permitted. Rather than arguing or working around it, I re-architected onto the sanctioned path.

**Four components, three safety rules:**

| Rule | Why |
|---|---|
| Append-only | A reporting tool that can silently rewrite history is a liability |
| Backup before write | No backup, no run |
| Draft, not send | Automate the analysis; do not automate the assertion to management |

### Result

Hours of weekly assembly became two clicks plus a human read-through. Metric definitions moved out of one head and into versioned code. Packaged for handover with sanitized scripts, acceptance criteria and a README.

### Skills Demonstrated
- Re-architecting around a governance constraint instead of fighting it
- Destructive-operation safety as a default
- Parallel-running new against old before cutover

---

## 5. Guarding Against the Failure Mode Automation Creates

### What I Did

Built a read-only Monday verification job over both recurring reports. Automation converts loud failures into silent ones: a manual report that nobody runs is obviously missing; an automated report that quietly absorbs a configuration change looks fine for a month.

The job checks four things — missing evidence, metric drift beyond what that series has historically varied by, silent configuration-default changes, and cross-report consistency — and has no write path at all.

### Result

Two latent bugs were found and fixed during construction, before either had produced a wrong report:

- **File selection by modification time**, which breaks the moment anyone opens an old report or re-saves a corrected week. Fixed to select by the date encoded in the filename
- **A positional-versus-named key mismatch** between the evidence store and the report columns, which would have silently compared the wrong pair of metrics after any column insertion

The configuration-default change that had previously gone unnoticed for weeks is now caught on the next run.

### Skills Demonstrated
- Read-only by construction as a design principle
- Thresholds derived from the data distribution rather than chosen round numbers
- Adversarial thinking applied to my own tooling

---

## 6. Cross-System Truth: Reconciling a Headline KPI

### What I Did

Traced the headline commercial KPI across all three systems it passes through, recovered the commissionable-amount formula out of stored procedures, and documented eight rules governing how money is distributed across products, sellers and periods.

Produced 21 numbered, evidenced findings.

### Result — including the part that went against me

I had initially concluded the reported KPI understated actual revenue by roughly 12%. On verification it does not — it matches almost exactly. What was inflated was a *different* aggregate built on a different amount column. **I published the correction with the same prominence as the original claim**, and marked two further findings as downgraded or withdrawn rather than deleting them, so the record shows what was tested and rejected.

Also found an accounting-basis mismatch: a date column that reads like a document date holds a payment date, making the KPI partly cash-basis while being described as accrual.

### Skills Demonstrated
- Reconstructing undocumented business logic across three systems
- Hand-tracing single records before trusting aggregates
- Retracting a prominent finding of my own at full volume

---

## 7. Investigations

Three that mattered:

**A price change that was invisible.** A supplier unit price dropped by roughly a fifth and no report showed it. Decomposing per transaction rather than averaging found the exact timestamp of the step change — and the reason it was hidden: units consumed per transaction had risen by roughly a third over the same window, almost exactly cancelling it. Two large offsetting changes had been reported as "nothing happened". I had previously stated the change had not occurred; I corrected that in writing. A third finding came out of it: the affected service had **no row in the official price list at all**, meaning commercial terms had changed outside the system of record. Escalated as governance, not analytics.

**A pilot that started three months earlier than everyone said.** Before analysing a large institutional pilot I checked the stated start date against the data. Usage records began roughly three months earlier. Anchoring on the assumed date would have understated the consumption baseline going into a pricing negotiation.

**Outliers that were not anomalies.** In the same pilot, the heaviest users consumed at an implausible-looking rate. Rather than trimming them, I traced individual sessions: they were submitting genuinely large documents, and the metered unit scales with input size. Real, legitimate, expensive usage — and precisely the pattern that needed to be priced correctly. The commercial reading changed from "we have a misuse problem" to "we have a power-user segment". The top hundred users account for close to 40% of everything consumed.

---

## 8. Data Modelling and Documentation

### What I Did

A lot of this year went into making structure explicit that previously lived only in people's heads:

- **A 74-value codebook reduced to 7 classes**, derived from concentration analysis, behavioural clustering and duration tiers rather than from a workshop — with a complete mapping from every legacy value, and a written evidence-based review of a competing proposal from the business side
- **A customer lifecycle model** derived from transaction history: a three-phase loop with sub-periods defined as offsets from each customer own contract end date, plus measured transition rates (renewal around 65%, win-back around 20%, and an additional-purchase rate of around +11% at the renewal moment that overturned the "renewal is defensive" framing)
- **Catalogue-layer documentation** distinguishing core products, add-ons and service contracts — including the trap that add-ons have no renewal cycle of their own and therefore silently distort any retention analysis that includes them
- **Warehouse and source-system catalogues**: which table lives where, which key joins to which, and which columns lie about their contents

### Skills Demonstrated
- Deriving taxonomies from measured behaviour rather than from names
- Turning analysis into operational artefacts: boards, interface mockups, specified tickets
- Documenting the traps, not just the schema

---

## Themes for Next Year

1. **From ranking to measurement.** The propensity models produce ranked lists; the next step is an A/B test of the ranking against current practice, so the uplift is measured rather than assumed
2. **Persistent history for the verification job.** Drift checks currently compare against a rolling window; they should compare against a stored series
3. **Closing the calibration gap.** Ranking is enough for a call list, but a properly calibrated probability would make the models usable in planning too
4. **Less of me in the loop.** Every deliverable this year shipped with a handover package. That should be the default, not the exception
