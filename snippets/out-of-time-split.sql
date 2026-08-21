/******************************************************************************
  out-of-time-split.sql
  ---------------------------------------------------------------------------
  Constructs a strict time-based train/holdout split for validating a
  propensity model, checks the holdout has enough power to be meaningful,
  and measures calibration separately from discrimination.

  In-sample AUC and cross-validated AUC both fail to detect the failure mode
  that matters commercially: the market changing under the model. Only an
  out-of-time holdout detects that.

  USAGE
    :freeze_date  -- the model sees nothing at or after this date
    :eval_end     -- end of the evaluation window

  THE MAIN TRAP
    Leakage usually enters through the LABEL DATE, not through the features.
    If conversions are dated from one order channel only, events land on the
    wrong side of the freeze line and the future leaks into training.
 ******************************************************************************/

-- +-------------------------------------------------------------------------+
-- | 1. CONVERSION DATE = earliest evidence across ALL order channels
-- +-------------------------------------------------------------------------+
WITH conversion_evidence AS (
    SELECT entity_id, first_order_date    AS event_date FROM crm.channel_renewals
    UNION ALL
    SELECT entity_id, contract_start_date AS event_date FROM crm.channel_contracts
    UNION ALL
    SELECT entity_id, order_date          AS event_date FROM crm.channel_selfservice
    UNION ALL
    SELECT entity_id, activation_date     AS event_date FROM crm.channel_partner
),

conversion AS (
    SELECT
        entity_id,
        MIN(event_date) AS converted_on
    FROM conversion_evidence
    WHERE event_date IS NOT NULL
    GROUP BY entity_id
),

-- +-------------------------------------------------------------------------+
-- | 2. SPLIT: features are always as-of the freeze date, on BOTH sides
-- +-------------------------------------------------------------------------+
labelled AS (
    SELECT
        f.entity_id,
        c.converted_on,
        CASE
            WHEN c.converted_on IS NOT NULL
             AND c.converted_on <  :freeze_date THEN 1 ELSE 0
        END AS y_train,
        CASE
            WHEN c.converted_on >= :freeze_date
             AND c.converted_on <  :eval_end    THEN 1 ELSE 0
        END AS y_holdout,
        CASE
            WHEN c.converted_on IS NOT NULL
             AND c.converted_on <  :freeze_date THEN 'exclude_already_customer'
            ELSE                                     'scoreable'
        END AS holdout_eligibility
    FROM model.features f
    LEFT JOIN conversion c ON c.entity_id = f.entity_id
    WHERE f.freeze_date = :freeze_date
)

-- +-------------------------------------------------------------------------+
-- | 3. POWER CHECK: run this BEFORE trusting any out-of-time AUC.
-- |    A holdout with too few positive events produces a number that looks
-- |    like a metric and carries no information.
-- +-------------------------------------------------------------------------+
SELECT
    COUNT(*)                                                 AS n_rows,
    SUM(y_train)                                             AS train_positives,
    SUM(CASE WHEN holdout_eligibility = 'scoreable'
             THEN y_holdout ELSE 0 END)                      AS holdout_positives,
    ROUND(100.0 * SUM(y_train) / NULLIF(COUNT(*), 0), 3)     AS train_base_rate_pct,
    CASE
        WHEN SUM(CASE WHEN holdout_eligibility = 'scoreable'
                      THEN y_holdout ELSE 0 END) < 50
        THEN 'TOO FEW HOLDOUT EVENTS - AUC WILL NOT BE MEANINGFUL'
        ELSE 'OK'
    END                                                      AS power_verdict
FROM labelled;


/******************************************************************************
  4. CALIBRATION vs DISCRIMINATION

  A model can rank well (good AUC) and still be badly calibrated. If the
  observed rate is far below the predicted probability, the score is a valid
  RANKING instrument and an invalid FORECAST - it must not be multiplied by
  contract values and put into a revenue plan.

  Run this every time a scored list is handed to a business user, and publish
  the over-prediction factor alongside the AUC.
 ******************************************************************************/
WITH scored AS (
    SELECT
        s.entity_id,
        s.predicted_probability,
        l.y_holdout,
        NTILE(10) OVER (ORDER BY s.predicted_probability DESC) AS score_decile
    FROM model.holdout_score s
    JOIN model.split_labels  l ON l.entity_id = s.entity_id
    WHERE l.holdout_eligibility = 'scoreable'
)
SELECT
    score_decile,
    COUNT(*)                                                   AS n,
    ROUND(AVG(predicted_probability)::numeric, 4)              AS mean_predicted,
    ROUND(AVG(y_holdout::numeric), 4)                          AS observed_rate,
    ROUND((AVG(predicted_probability)
           / NULLIF(AVG(y_holdout::numeric), 0))::numeric, 2)  AS over_prediction_factor
FROM scored
GROUP BY score_decile
ORDER BY score_decile;
