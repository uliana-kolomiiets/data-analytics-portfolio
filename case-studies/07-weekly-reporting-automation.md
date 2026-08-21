# Weekly Reporting Automation

## Context

A weekly commercial report on product usage and consumption was assembled by hand: several SQL queries run manually, results pasted into a shared workbook, a summary written into an email, sent every Monday. It took a meaningful slice of someone's week, and because it was manual it drifted — definitions changed quietly, a column got pasted one row off, a week got skipped.

The first design I proposed was to automate the shared cloud spreadsheet directly through its API. That was ruled out on internal policy grounds: the spreadsheet is a governed artefact and programmatic writes to it are not permitted. The constraint was legitimate, so the architecture had to change rather than the rule.

## Goal

Automate the report end to end within the permitted architecture, so that a human runs two clicks instead of two hours, without giving up the review step that a commercial report needs.

## My Role

Designed the architecture around the policy constraint, built all four components, tested them against a live week, and wrote the handover package.

## Data and Logic

The permitted path turned out to be: **local Python generator → shared workbook on the corporate document store → local mail client draft.** Everything stays inside sanctioned systems; nothing writes to the governed cloud sheet.

Four components:

| Component | Responsibility |
|---|---|
| Generator | Runs the queries, builds the multi-sheet workbook, writes a pointer file recording what it produced |
| Workbook push | Opens the shared workbook via Office automation, appends the new week, never overwrites history |
| Mail draft | Composes the summary email as a **draft**, with the correct signature, and stops |
| Launcher | Two buttons, so a non-technical colleague can run it |

Three deliberate design rules:

- **Append-only.** The push adds a week; it never rewrites earlier weeks. A reporting tool that can silently rewrite history is a liability
- **Mandatory backup.** The workbook is copied before it is touched. No backup, no run
- **Draft, not send.** The email is created and displayed for a human to read and send. Automating the analysis is safe; automating the assertion to management is not

The push also had a non-obvious requirement: downstream formulas in the workbook aggregate over a fixed column range, so cleared cells have to be cleared *by content* rather than by deleting rows, or the formulas break silently while still returning a number.

## Approach

1. Reconstructed every metric definition from the manual process and wrote them down, because half of them existed only in one person's head
2. Built the generator first and ran it in parallel with the manual report for several weeks, comparing outputs
3. Added the workbook push with backup-first and append-only semantics
4. Added the mail draft, including handling the correct grammatical forms for the sender
5. Built the launcher, then had someone else run it without me in the room — the real test
6. Packaged sanitized copies of the scripts, an acceptance-criteria ticket and a README for handover

## Sanitized SQL / Logic Example

```sql
-- One of the report sheets: weekly consumption by customer and product,
-- with the previous week alongside so drift is visible on the sheet itself.
WITH weekly AS (
    SELECT
        DATE_TRUNC('week', event_ts)::date AS week_start,
        customer_id,
        product_key,
        COUNT(*)                           AS request_count,
        SUM(billable_units)                AS billable_units
    FROM usage.event
    WHERE event_ts >= :week_start
      AND event_ts <  :week_start + INTERVAL '7 days'
    GROUP BY 1, 2, 3
),

previous AS (
    SELECT
        customer_id,
        product_key,
        SUM(billable_units) AS billable_units_prev
    FROM usage.event
    WHERE event_ts >= :week_start - INTERVAL '7 days'
      AND event_ts <  :week_start
    GROUP BY 1, 2
)

SELECT
    w.week_start,
    w.customer_id,
    w.product_key,
    w.request_count,
    w.billable_units,
    p.billable_units_prev,
    ROUND(100.0 * (w.billable_units - COALESCE(p.billable_units_prev, 0))
          / NULLIF(p.billable_units_prev, 0), 1) AS pct_change
FROM weekly w
LEFT JOIN previous p
       ON p.customer_id = w.customer_id
      AND p.product_key = w.product_key
ORDER BY w.billable_units DESC;
```

## QA and Validation

- Ran generated and manual reports side by side for several weeks and reconciled every discrepancy before switching over
- Verified the append never touched an existing row, by diffing the workbook before and after
- Confirmed the backup exists and is readable before the push proceeds, with the run aborting if not
- Tested the mail draft path for signature and formatting correctness, since the draft goes to management
- Had a colleague run the launcher unaided as the acceptance test

## Outcome

- Weekly effort dropped from hours of manual assembly to two clicks plus a human read-through
- Metric definitions became written and versioned instead of tacit
- The report stopped drifting, because the definitions now live in code rather than in a copy-paste habit
- The whole thing was packaged for handover — sanitized scripts with no credentials, paths or names, plus tickets with explicit acceptance numbers — so it is not dependent on me

## What This Demonstrates

- Re-architecting around a governance constraint instead of arguing with it or working around it
- Building destructive-operation safety in by default: backup-first, append-only, draft-not-send
- Knowing where to stop automating — the analysis, not the assertion to management
- Parallel-running a new system against the old one before cutover
- Writing the handover package as part of the work, not as an afterthought
