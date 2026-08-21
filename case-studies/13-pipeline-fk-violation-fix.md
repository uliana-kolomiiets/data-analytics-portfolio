# Pipeline Fix — Orphaned Foreign Keys

## Context

A nightly warehouse pipeline started failing. The job transfers records between schemas as part of the daily load chain, and it aborted on a foreign-key violation — it was trying to insert rows referencing a parent record that no longer existed.

The cause was ordinary: a user account had been deleted in the source system, but rows referencing that account remained in the tables being transferred. Ordinary, but it stopped the chain, and everything scheduled after it did not run.

## Goal

Get the pipeline running again without deleting data, without disabling the constraint, and without a fix that would need repeating the next time an account is deleted.

## My Role

Diagnosed the failure, wrote the fix, and put it through the team's review process.

## Data and Logic

Four possible fixes, and the choice between them is the whole point:

| Option | Why not |
|---|---|
| Drop the foreign-key constraint | Removes the check that caught the problem. The constraint is doing its job |
| Recreate the deleted parent record | Fabricates data in the warehouse that does not exist in the source |
| Delete the orphaned child rows | Destructive, and the rows are legitimate history of something that happened |
| **Guard the transfer** | Skip rows whose parent does not exist, and make the skip visible |

The guard is the right answer because it is honest about what the data says: these rows reference something that is gone, so they cannot be loaded into a table that requires the reference — but they should not be destroyed either, and the constraint should stay.

The important detail is that the guard must not be silent. A `WHERE EXISTS` that quietly drops rows is a data-loss mechanism with a friendly face. The skipped count is logged so that a growing number is visible.

## Approach

1. Reproduced the failure and identified the exact violating rows rather than inferring the cause from the error message
2. Confirmed the parent record was genuinely absent in the source, not just absent from the current load window
3. Considered and rejected the three destructive or check-weakening options, with reasons written down
4. Implemented the guard with an explicit skip count
5. Branched from the development branch, opened a merge request, and waited for review — the pipeline repository is review-gated and a failing nightly job is not a reason to bypass that

## Sanitized SQL / Logic Example

```sql
-- Before: fails the moment any referenced parent has been deleted upstream.
INSERT INTO target.fact_activity (activity_id, account_id, activity_ts, payload)
SELECT activity_id, account_id, activity_ts, payload
FROM source.activity
WHERE activity_ts >= :load_from;

-- After: skip rows whose parent no longer exists, and COUNT the skips.
-- A silent WHERE EXISTS is data loss with better manners.
WITH candidate AS (
    SELECT activity_id, account_id, activity_ts, payload
    FROM source.activity
    WHERE activity_ts >= :load_from
),

loadable AS (
    SELECT c.*
    FROM candidate c
    WHERE EXISTS (SELECT 1 FROM target.dim_account a
                  WHERE a.account_id = c.account_id)
),

skipped AS (
    SELECT c.account_id, COUNT(*) AS skipped_rows
    FROM candidate c
    WHERE NOT EXISTS (SELECT 1 FROM target.dim_account a
                      WHERE a.account_id = c.account_id)
    GROUP BY c.account_id
)

INSERT INTO target.fact_activity (activity_id, account_id, activity_ts, payload)
SELECT activity_id, account_id, activity_ts, payload
FROM loadable;

-- Emitted to the task log every run; a rising number means investigate upstream.
SELECT account_id, skipped_rows FROM skipped ORDER BY skipped_rows DESC;
```

## QA and Validation

- Verified the guard changes the outcome only for orphaned rows, by comparing loaded row counts before and after on a clean window
- Confirmed the foreign-key constraint remains in place and still fires on any other violation
- Checked that the skip count is zero on normal days, so a non-zero value is a genuine signal
- Confirmed the fix is idempotent across reruns of the same load window

## Outcome

- The pipeline runs, the constraint stays, no data was deleted or invented
- Future account deletions no longer break the chain, and each one is now visible as a logged skip count rather than as a 3 a.m. failure
- The change went through the normal merge-request review rather than being pushed directly, despite the pressure of a failing nightly job

## What This Demonstrates

- Diagnosing a pipeline failure to the exact rows rather than to the error class
- Choosing the least destructive fix, and writing down why the other options were rejected
- Refusing to weaken a constraint that is correctly doing its job
- Making a skip observable, because silent row-dropping is a worse bug than the one being fixed
- Following review process under time pressure instead of treating urgency as an exemption
