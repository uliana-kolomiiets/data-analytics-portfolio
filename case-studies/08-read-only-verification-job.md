# Read-Only Verification Job

## Context

Once two recurring commercial reports were automated, a new risk replaced the old one. A manual report fails loudly — someone forgets to run it and it is obviously missing. An automated report fails quietly: it runs, produces a plausible-looking number, and nobody notices for a month that a configuration default changed underneath it.

I had already seen this happen. A model configuration default shifted, which changed how a whole class of usage was attributed, and the weekly averages absorbed it without any visible break.

## Goal

Build a Monday-morning check that inspects both reports and the data behind them, and tells a human what to look at — without being able to change anything.

## My Role

Designed and built it, including working out which failure modes are actually detectable and which are not.

## Data and Logic

Strictly **read-only by construction.** The job opens files, runs SELECT queries and prints findings. It has no write path at all — not a disabled write path, no write path. A verification tool that can modify the thing it verifies is not a verification tool.

Four classes of check:

| Check | What it catches |
|---|---|
| Evidence present | A week that was never produced, or produced and not recorded |
| Metric drift | A week-over-week change large enough to be a data problem rather than a business event |
| Silent default change | A configuration default that moved without anyone announcing it |
| Cross-report consistency | The same quantity reported differently by two reports that should agree |

### Two traps found while building it

**File selection by name, not by timestamp.** The obvious way to find "this week's report file" is the most recently modified file. That is wrong: opening an old report to look at it updates its modification time, and re-saving a corrected older week makes it look like the newest. The correct key is the date encoded in the filename. This is exactly the kind of bug that produces confidently wrong output.

**Positional keys versus labels.** The evidence store identifies metrics by column position, while the reports identify them by column name. Any check that assumes the two agree will silently compare the wrong pair the moment a column is inserted. The mapping had to be made explicit and asserted.

The job also reports what it *cannot* verify — for one of the reports, the supporting evidence had stopped being recorded weeks earlier, and rather than skipping that check silently it says so every run.

## Approach

1. Listed the ways each report could be wrong while still looking right, and kept only the ones that are detectable from data
2. Implemented each check as an independent assertion that reports rather than raises, so one failure does not hide the rest
3. Wired file selection to the filename date and asserted the mapping between positional and named keys
4. Set drift thresholds from historical week-over-week variation rather than picking round numbers
5. Made unverifiable checks announce themselves instead of passing silently

## Sanitized SQL / Logic Example

```sql
-- Drift check: flag week-over-week movement that is large relative to this
-- series own history, rather than against an arbitrary fixed threshold.
WITH weekly AS (
    SELECT
        DATE_TRUNC('week', event_ts)::date AS week_start,
        metric_key,
        SUM(metric_value)                  AS value
    FROM reporting.metric_fact
    WHERE event_ts >= :lookback_start
    GROUP BY 1, 2
),

with_lag AS (
    SELECT
        week_start,
        metric_key,
        value,
        LAG(value) OVER (PARTITION BY metric_key ORDER BY week_start) AS prev_value
    FROM weekly
),

stats AS (
    SELECT
        metric_key,
        AVG(value / NULLIF(prev_value, 0))        AS mean_ratio,
        STDDEV_POP(value / NULLIF(prev_value, 0)) AS sd_ratio
    FROM with_lag
    WHERE prev_value IS NOT NULL
    GROUP BY metric_key
)

SELECT
    w.week_start,
    w.metric_key,
    w.prev_value,
    w.value,
    ROUND((w.value / NULLIF(w.prev_value, 0))::numeric, 3) AS ratio,
    CASE
        WHEN w.prev_value IS NULL THEN 'NO BASELINE'
        WHEN ABS((w.value / NULLIF(w.prev_value, 0)) - s.mean_ratio)
             > 3 * NULLIF(s.sd_ratio, 0) THEN 'INVESTIGATE'
        ELSE 'OK'
    END AS verdict
FROM with_lag w
JOIN stats s ON s.metric_key = w.metric_key
WHERE w.week_start = :week_start
ORDER BY verdict, w.metric_key;
```

## QA and Validation

- Replayed the job over historical weeks and confirmed it would have caught the configuration-default change that originally went unnoticed
- Deliberately corrupted a test copy of a report to confirm each check fires
- Confirmed the job holds no write handle on any file or database connection
- Verified that a failing check reports and continues rather than aborting the run

## Outcome

- A single Monday command that produces a short list of things worth a human look, or says everything is fine
- The configuration-default failure mode that had previously gone undetected for weeks is now caught on the next run
- Two latent bugs — timestamp-based file selection and the positional/named key mismatch — were found and fixed during construction, before they had produced a wrong report
- Gaps in the evidence trail are now stated out loud every week instead of quietly skipped

## What This Demonstrates

- Recognising that automation converts loud failures into silent ones, and building for the new failure mode
- Read-only by construction as a design principle, not a convention
- Deriving thresholds from the data distribution rather than choosing round numbers
- Catching two subtle correctness bugs (file selection, key mapping) through adversarial thinking about my own tooling
- Reporting the limits of the check as part of its output
