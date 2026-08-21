/******************************************************************************
  propensity-feature-build.sql
  ---------------------------------------------------------------------------
  Builds the entity-level feature table for a customer propensity model.

  One row per legal entity in the public business register, every feature
  evaluated AS OF a freeze date, plus a conversion label built from order
  history rather than from a CRM status flag.

  Sanitized: table and column names are generic; no internal identifiers.

  USAGE
    :freeze_date     -- all features and the label are evaluated as of this date
    :product_family  -- which product the propensity is being modelled for

  NOTES
    - The label comes from orders, not from a customer flag. Status flags in
      operational CRMs go stale and produce a mislabelled training set.
    - Geography resolves through the municipal-district hierarchy to the true
      sales territory. The region column on the entity is a proxy that
      misassigns a whole border area.
    - Every feature must be knowable at :freeze_date. Anything that exists only
      BECAUSE the entity became a customer is leakage.
 ******************************************************************************/

-- +-------------------------------------------------------------------------+
-- | 1. BASE POPULATION: active entities in the public register
-- +-------------------------------------------------------------------------+
WITH register AS (
    SELECT
        e.entity_id,
        e.legal_form_code,
        e.industry_code,
        e.employee_band,
        e.founded_year,
        e.municipality_id
    FROM public_register.entity e
    WHERE e.status_code = 'active'
      AND e.registered_on <= :freeze_date
      AND e.entity_id NOT IN (SELECT entity_id FROM internal.excluded_entity)
),

-- +-------------------------------------------------------------------------+
-- | 2. TERRITORY: resolve through the district hierarchy, not the region col
-- +-------------------------------------------------------------------------+
territory AS (
    SELECT
        m.municipality_id,
        d.sales_branch_id AS territory_id
    FROM public_register.municipality m
    JOIN internal.municipal_district d
      ON d.district_id = m.district_id
),

-- +-------------------------------------------------------------------------+
-- | 3. SECTOR FLAGS: grouped, with sub-types split only where volume allows
-- +-------------------------------------------------------------------------+
sector AS (
    SELECT
        r.entity_id,
        CASE WHEN r.legal_form_code IN (:public_forms) THEN 1 ELSE 0 END AS is_public_sector,
        CASE WHEN r.legal_form_code  = :municipal_form THEN 1 ELSE 0 END AS is_municipal,
        CASE WHEN r.legal_form_code  = :education_form THEN 1 ELSE 0 END AS is_education,
        SUBSTRING(r.industry_code FROM 1 FOR 2)                          AS industry_group
    FROM register r
),

-- +-------------------------------------------------------------------------+
-- | 4. RELATIONSHIP HISTORY: strictly before the freeze date
-- +-------------------------------------------------------------------------+
relationship AS (
    SELECT
        a.entity_id,
        MIN(a.activity_date)                                          AS first_contact_date,
        COUNT(*)                                                      AS contact_count,
        MAX(CASE WHEN a.outcome_code = 'refused' THEN 1 ELSE 0 END)   AS ever_refused,
        COUNT(DISTINCT a.owning_user_id)                              AS distinct_owners
    FROM crm.activity a
    WHERE a.activity_date < :freeze_date
    GROUP BY a.entity_id
),

-- +-------------------------------------------------------------------------+
-- | 5. PRIOR PRODUCT OWNERSHIP (other product families only)
-- +-------------------------------------------------------------------------+
prior_products AS (
    SELECT
        ol.entity_id,
        COUNT(DISTINCT ol.product_family) AS other_products_owned
    FROM crm.order_line ol
    WHERE ol.order_date     <  :freeze_date
      AND ol.order_status    = 'confirmed'
      AND ol.product_family <> :product_family
    GROUP BY ol.entity_id
),

-- +-------------------------------------------------------------------------+
-- | 6. LABEL: built from confirmed orders, never from a CRM status flag
-- +-------------------------------------------------------------------------+
converted AS (
    SELECT DISTINCT ol.entity_id
    FROM crm.order_line ol
    WHERE ol.product_family = :product_family
      AND ol.order_status   = 'confirmed'
      AND ol.order_date     < :freeze_date
)

-- +-------------------------------------------------------------------------+
-- | 7. FINAL FEATURE TABLE
-- +-------------------------------------------------------------------------+
SELECT
    r.entity_id,
    :freeze_date                                               AS freeze_date,

    -- firmographics
    r.legal_form_code,
    s.industry_group,
    r.employee_band,
    DATE_PART('year', :freeze_date::date) - r.founded_year     AS entity_age_years,

    -- sector
    s.is_public_sector,
    s.is_municipal,
    s.is_education,

    -- geography (true territory)
    t.territory_id,

    -- relationship history
    COALESCE(rel.contact_count, 0)                             AS contact_count,
    COALESCE(rel.ever_refused, 0)                              AS ever_refused,
    COALESCE(rel.distinct_owners, 0)                           AS distinct_owners,
    CASE WHEN rel.first_contact_date IS NULL THEN 1 ELSE 0 END AS never_contacted,
    (:freeze_date::date - rel.first_contact_date)              AS days_since_first_contact,

    -- portfolio
    COALESCE(pp.other_products_owned, 0)                       AS other_products_owned,

    -- label
    CASE WHEN c.entity_id IS NOT NULL THEN 1 ELSE 0 END        AS is_converted

FROM register r
JOIN      territory      t   ON t.municipality_id = r.municipality_id
JOIN      sector         s   ON s.entity_id       = r.entity_id
LEFT JOIN relationship   rel ON rel.entity_id     = r.entity_id
LEFT JOIN prior_products pp  ON pp.entity_id      = r.entity_id
LEFT JOIN converted      c   ON c.entity_id       = r.entity_id;
