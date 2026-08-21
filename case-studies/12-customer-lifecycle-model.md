# Customer Lifecycle Model From Operational Data

## Context

Sales, retention and marketing each had their own mental model of the customer lifecycle, and the models did not agree on the basic questions: when does a customer stop being a prospect, when should upsell stop, when does retention start, and when is a lapsed customer worth approaching again.

Because the phases were not defined, activity was mistimed — retention campaigns firing at customers who had already renewed, upsell offers landing during a renewal negotiation, win-back attempts on customers who had left years earlier.

## Goal

Derive the lifecycle from transaction history rather than from opinion, define the phase boundaries in terms a CRM can act on, and measure what actually happens at each transition.

## My Role

Built the model from the operational data, measured the transition rates, and produced the deliverables needed to make it operational: an interactive board for stakeholders, CRM interface mockups, and a development ticket.

## Data and Logic

The lifecycle came out as a **three-phase loop**, not a funnel — customers cycle rather than graduate:

| Phase | Definition |
|---|---|
| Acquisition | Prospect through first purchase |
| Active period | Ownership, with internal sub-periods |
| Post-contract | Lapse, dormancy, and possible return |

The middle phase is where the useful structure is, and it splits into three sub-periods defined **relative to the contract end date**, not by calendar:

- **Open period** — normal ownership; upsell and cross-sell are appropriate here
- **Quiet period** — starting a fixed number of months before contract end; upsell stops, because an upsell offer during this window competes with the renewal
- **Retention period** — starting closer to contract end; renewal activity only

Defining the boundaries as offsets from contract end rather than as fixed dates is what makes the model implementable: every customer has their own clock.

## Approach

1. Reconstructed each customer's contract timeline from order history across all order channels
2. Aligned every customer on a common relative axis — days to and from contract end — instead of calendar time
3. Measured activity outcomes at each relative offset to find where behaviour actually changes
4. Set the phase boundaries where the measured behaviour breaks, then rounded them to whole months for operational usability
5. Measured the transition rates: renewal, lapse, win-back
6. Built an interactive board so stakeholders could explore the phases, mocked up several variants of the CRM card that would surface the phase to a salesperson, and wrote the development ticket

## Sanitized SQL / Logic Example

```sql
-- Assign every customer to a lifecycle phase on a RELATIVE clock:
-- offsets from their own contract end date, not from the calendar.
WITH contract AS (
    SELECT
        customer_id,
        product_key,
        valid_from,
        valid_to,
        (valid_to - CURRENT_DATE) AS days_to_end
    FROM crm.contract
    WHERE contract_status = 'active'
      AND valid_to IS NOT NULL          -- open-ended contracts handled separately
),

phased AS (
    SELECT
        customer_id,
        product_key,
        days_to_end,
        CASE
            WHEN days_to_end <  0                        THEN 'post_contract'
            WHEN days_to_end <= :retention_window_days   THEN 'retention'
            WHEN days_to_end <= :quiet_window_days       THEN 'quiet'
            ELSE                                              'open'
        END AS lifecycle_phase
    FROM contract
)

SELECT
    lifecycle_phase,
    COUNT(*)                                  AS customers,
    ROUND(AVG(days_to_end)::numeric, 0)       AS avg_days_to_end,
    -- what a CRM card needs to know: is upsell allowed right now?
    CASE WHEN lifecycle_phase = 'open' THEN 'upsell_allowed'
         ELSE 'renewal_only' END              AS permitted_action
FROM phased
GROUP BY lifecycle_phase, permitted_action
ORDER BY avg_days_to_end DESC;
```

## QA and Validation

- Handled open-ended contracts as a separate case rather than letting a NULL end date default into a phase
- Verified the relative-clock alignment against individual customer timelines by hand
- Confirmed the measured behavioural break points were stable across product families before generalising them
- Checked that the phase definitions partition the population completely — every active customer lands in exactly one phase

## Outcome

Measured transition rates, replacing three sets of assumptions with one set of numbers:

| Transition | Measured |
|---|---|
| Renewal at contract end | around 65% |
| Win-back after lapse | around 20% |
| Additional purchase at renewal moment | around +11% |

The +11% figure was the one that changed behaviour: the renewal moment is itself a selling opportunity, which the previous "renewal is a defensive activity" framing had missed entirely.

Three deliverables went with it: an interactive lifecycle board for stakeholders, a set of CRM card mockups showing how the phase and its permitted action would appear to a salesperson, and a written development ticket specifying the implementation.

## What This Demonstrates

- Deriving phase boundaries from measured behavioural breaks instead of agreeing them in a meeting
- Aligning customers on a relative clock, which is what makes a lifecycle model implementable per customer
- Modelling the lifecycle as a loop rather than forcing it into a funnel because that is the familiar shape
- Turning analysis into something operational: board, interface mockups, and a specified ticket
- Producing a measured number that overturned a framing assumption
