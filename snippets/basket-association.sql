/******************************************************************************
  basket-association.sql
  ---------------------------------------------------------------------------
  Product co-occurrence with support, confidence and lift, plus exact-basket
  frequencies.

  SEMANTICS FIRST
    "Customers who bought A also bought B" has two incompatible readings:

      EXACT BASKET : holdings are PRECISELY {A, B}
      SUPPORT      : holdings INCLUDE A and B, among possibly others

    They give different numbers and support different decisions. Mixing them
    is the standard way basket analysis goes wrong. Compute both, and label
    every output with which one it is.

    Use EXACT BASKET to describe the portfolio.
    Use SUPPORT rules to target cross-sell.

  OTHER TRAPS HANDLED HERE
    - Case-inconsistent product names split one product into two.
    - Lift on a cell of three customers is noise with a decimal point.
    - Holdings counts are NOT revenue and must not be read as such.
 ******************************************************************************/

-- +-------------------------------------------------------------------------+
-- | 1. HOLDINGS: active only, product names normalised
-- +-------------------------------------------------------------------------+
WITH holdings AS (
    SELECT DISTINCT
        s.customer_id,
        UPPER(TRIM(p.product_name)) AS product_key   -- collapse case duplicates
    FROM crm.active_subscription s
    JOIN crm.catalogue_item      p ON p.item_id = s.item_id
    WHERE s.valid_from <= CURRENT_DATE
      AND (s.valid_to IS NULL OR s.valid_to > CURRENT_DATE)
      AND p.product_layer = 'core'    -- add-ons and service contracts excluded;
                                      -- they behave differently, see notes below
),

total AS (
    SELECT COUNT(DISTINCT customer_id) AS n_customers FROM holdings
),

single AS (
    SELECT product_key, COUNT(DISTINCT customer_id) AS n_holding
    FROM holdings
    GROUP BY product_key
),

-- +-------------------------------------------------------------------------+
-- | 2. SUPPORT SEMANTICS: pairwise co-occurrence
-- +-------------------------------------------------------------------------+
pairs AS (
    SELECT
        a.product_key                 AS product_a,
        b.product_key                 AS product_b,
        COUNT(DISTINCT a.customer_id) AS n_both
    FROM holdings a
    JOIN holdings b
      ON a.customer_id = b.customer_id
     AND a.product_key < b.product_key     -- each unordered pair exactly once
    GROUP BY 1, 2
)

SELECT
    'SUPPORT' AS semantics,
    p.product_a,
    p.product_b,
    p.n_both,
    ROUND(100.0 * p.n_both / t.n_customers, 2)   AS support_pct,
    ROUND(100.0 * p.n_both / sa.n_holding, 2)    AS confidence_a_to_b_pct,
    ROUND(100.0 * p.n_both / sb.n_holding, 2)    AS confidence_b_to_a_pct,
    ROUND((p.n_both::numeric / t.n_customers)
          / NULLIF((sa.n_holding::numeric / t.n_customers)
                 * (sb.n_holding::numeric / t.n_customers), 0), 2) AS lift
FROM pairs p
CROSS JOIN total t
JOIN single sa ON sa.product_key = p.product_a
JOIN single sb ON sb.product_key = p.product_b
WHERE p.n_both >= :min_basket_size     -- suppress small-cell noise
ORDER BY lift DESC;


-- +-------------------------------------------------------------------------+
-- | 3. EXACT-BASKET SEMANTICS: what portfolios do customers actually hold?
-- |    This is the view that shows how few customers hold more than one
-- |    product - usually the finding that resizes the cross-sell question.
-- +-------------------------------------------------------------------------+
WITH holdings AS (
    SELECT DISTINCT
        s.customer_id,
        UPPER(TRIM(p.product_name)) AS product_key
    FROM crm.active_subscription s
    JOIN crm.catalogue_item      p ON p.item_id = s.item_id
    WHERE s.valid_from <= CURRENT_DATE
      AND (s.valid_to IS NULL OR s.valid_to > CURRENT_DATE)
      AND p.product_layer = 'core'
),

basket AS (
    SELECT
        customer_id,
        COUNT(*)                                                AS basket_size,
        STRING_AGG(product_key, ' + ' ORDER BY product_key)     AS exact_basket
    FROM holdings
    GROUP BY customer_id
)

SELECT
    'EXACT_BASKET' AS semantics,
    basket_size,
    exact_basket,
    COUNT(*)                                                    AS n_customers,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)          AS pct_of_customers
FROM basket
GROUP BY basket_size, exact_basket
ORDER BY n_customers DESC;


/******************************************************************************
  NOTES ON CATALOGUE LAYERS - why product_layer = 'core' is filtered above

    core             has a renewal cycle; enters the retention lifecycle
    add_on           has its own contract and can be bought separately, but
                     has NO renewal cycle of its own, so it never appears in
                     retention analysis unless deliberately included
    service_contract a payment model rather than a product; carries recurring
                     revenue and behaves as a customer attribute

  Mixing these layers into one basket analysis produces confident nonsense.
  Run each layer separately, or join them deliberately and say so.
 ******************************************************************************/
