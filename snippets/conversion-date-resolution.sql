/******************************************************************************
  conversion-date-resolution.sql
  ---------------------------------------------------------------------------
  Resolves WHEN a prospect actually became a customer, across several order
  channels that each record the event differently.

  This is the single most common source of silent error in a commercial
  propensity model. Every downstream artefact - the training label, the
  out-of-time split, the lifecycle phase, the conversion-rate report -
  depends on this date being right.

  WHY IT IS HARD
    - Different channels record different date semantics: order date,
      contract start, activation, first invoice.
    - The same conversion frequently appears in more than one channel.
    - Some channels leave the date NULL and only carry a period.
    - Cancelled and re-placed orders create later dates for earlier events.

  RULE
    A conversion is dated by the EARLIEST credible evidence across all
    channels. Using one convenient channel systematically dates conversions
    too late, which pushes events across a freeze line and leaks the future
    into a training set.
 ******************************************************************************/

-- +-------------------------------------------------------------------------+
-- | 1. GATHER EVIDENCE FROM EVERY CHANNEL
-- |    Each branch is narrowed to confirmed, non-cancelled records only.
-- +-------------------------------------------------------------------------+
WITH evidence AS (

    -- renewal / subscription channel
    SELECT
        entity_id,
        first_order_date          AS event_date,
        'renewals'                AS source_channel
    FROM crm.channel_renewals
    WHERE order_status = 'confirmed'
      AND first_order_date IS NOT NULL

    UNION ALL

    -- contract channel: the contract start, not the signature date
    SELECT
        entity_id,
        contract_start_date       AS event_date,
        'contracts'               AS source_channel
    FROM crm.channel_contracts
    WHERE contract_status <> 'cancelled'
      AND contract_start_date IS NOT NULL

    UNION ALL

    -- self-service channel
    SELECT
        entity_id,
        order_date                AS event_date,
        'selfservice'             AS source_channel
    FROM crm.channel_selfservice
    WHERE payment_status = 'paid'
      AND order_date IS NOT NULL

    UNION ALL

    -- partner channel: activation is the first date the customer exists to us
    SELECT
        entity_id,
        activation_date           AS event_date,
        'partner'                 AS source_channel
    FROM crm.channel_partner
    WHERE activation_date IS NOT NULL
),

-- +-------------------------------------------------------------------------+
-- | 2. SANITY FILTER
-- |    Drop dates that cannot be real before taking a MIN, because a single
-- |    bad early date silently becomes the conversion date for that entity.
-- +-------------------------------------------------------------------------+
credible AS (
    SELECT *
    FROM evidence
    WHERE event_date >= DATE '1995-01-01'      -- predates the business
      AND event_date <= CURRENT_DATE           -- future-dated records exist
),

-- +-------------------------------------------------------------------------+
-- | 3. RESOLVE
-- +-------------------------------------------------------------------------+
resolved AS (
    SELECT
        entity_id,
        MIN(event_date)                                     AS converted_on,
        COUNT(DISTINCT source_channel)                      AS channels_agreeing,
        MAX(event_date) - MIN(event_date)                   AS evidence_spread_days,
        STRING_AGG(DISTINCT source_channel, ',' ORDER BY source_channel)
                                                            AS channels
    FROM credible
    GROUP BY entity_id
)

SELECT
    entity_id,
    converted_on,
    channels,
    channels_agreeing,
    evidence_spread_days,
    -- A wide spread means the channels disagree about when this customer
    -- started. Worth inspecting rather than silently trusting the MIN.
    CASE
        WHEN channels_agreeing = 1                 THEN 'single_source'
        WHEN evidence_spread_days > 365            THEN 'REVIEW_wide_spread'
        ELSE                                            'consistent'
    END AS evidence_quality
FROM resolved
ORDER BY evidence_spread_days DESC;


-- +-------------------------------------------------------------------------+
-- | 4. QA: how much would a single-channel shortcut have cost?
-- |    Run this once to demonstrate why the UNION is not optional.
-- +-------------------------------------------------------------------------+
-- SELECT
--     COUNT(*) AS entities,
--     SUM(CASE WHEN r.converted_on < s.order_date THEN 1 ELSE 0 END)
--         AS would_have_been_dated_too_late
-- FROM resolved r
-- JOIN crm.channel_selfservice s USING (entity_id);
