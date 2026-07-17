-- Validating assumptions about the granularity of the data of the orders_dataset before the official query

-- ASSUMPTION 1: EVERY ORDER ONLY HAS 1 PRODUCT
-- If this returns no rows, each order maps to exactly one product
SELECT order_number,
       COUNT(DISTINCT fk_product) AS unique_products_count
FROM fact_tables.orders
GROUP BY order_number
HAVING COUNT(DISTINCT fk_product) > 1;

-- ASSUMPTION 2: EVERY ORDER_ID ONLY HAS 1 order_number
-- If this returns no rows, each order_id maps to exactly one order_number
SELECT order_id,
       COUNT(DISTINCT order_number) AS unique_order_number_count
FROM fact_tables.orders
GROUP BY order_id,order_number
HAVING COUNT(DISTINCT order_number) > 1;


-- ASSUMPTION 3: EVERY CONVERSION ONLY HAS 1 ORDER NUMBER
-- If this returns no rows, each conversion maps to exactly one order
SELECT conversion_id,
       COUNT(DISTINCT order_number) AS unique_orders
FROM fact_tables.conversions
GROUP BY conversion_id
HAVING COUNT(DISTINCT order_number) > 1;


-- ASSUMPTION 4: EVERY ORDER NUMBER IN CONVERSIONS EXISTS IN THE ORDERS TABLE
-- If this returns no rows, there are no orphaned order references in conversions
SELECT c.conversion_id,
       c.order_number
FROM fact_tables.conversions AS c
LEFT JOIN fact_tables.orders AS o
    ON c.order_number = o.order_number
WHERE o.order_number IS NULL;


-- ASSUMPTION 5: FIRST ORDER WEEK = FIRST CONVERSION WEEK FOR EACH CUSTOMER
-- If this returns no rows, every customer's first order happened in the same week as their first conversion
WITH first_conversions AS (
    SELECT cs.fk_customer,
           MIN(dd.year_week) AS first_conversion_week
    FROM fact_tables.conversions AS cs
    LEFT JOIN dimensions.date_dimension AS dd
        ON cs.fk_conversion_date = dd.sk_date
    GROUP BY cs.fk_customer
),
first_orders AS (
    SELECT cs.fk_customer,
           MIN(dd.year_week) AS first_order_week
    FROM fact_tables.conversions AS cs
    LEFT JOIN fact_tables.orders AS o
        ON cs.order_number = o.order_number
    LEFT JOIN dimensions.date_dimension AS dd
        ON o.fk_order_date = dd.sk_date
    GROUP BY cs.fk_customer
)
SELECT fc.fk_customer,
       fc.first_conversion_week,
       fo.first_order_week
FROM first_conversions AS fc
LEFT JOIN first_orders AS fo
    ON fc.fk_customer = fo.fk_customer
WHERE fc.first_conversion_week != fo.first_order_week
   OR fo.first_order_week IS NULL;
-- Observation: this assumption is false, because there is a customer 9999
-- (which could be an error entry) that has a conversion without an order.
-- We will code defensively to make this distinction.



----------------------------------------------------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS customer360;

-- 1. Start over with a clean slate and drop a previous table if it exists
DROP TABLE IF EXISTS customer360.full_360_view;

-- 2. Create the structured table under the schema
CREATE TABLE IF NOT EXISTS customer360.full_360_view (
    customer_id INT,
    first_name VARCHAR(255),
    last_name VARCHAR(255),
    conversion_id INT,
    conversion_number INT,
    conversion_type VARCHAR(255),
    conversion_date DATE,
    conversion_week VARCHAR(255),
    next_conversion_week VARCHAR(255),
    conversion_channel VARCHAR(255),
    first_order_week VARCHAR(255),
    first_order_total_paid DECIMAL(18,2),
    week_counter INT,
    order_week VARCHAR(255),
    orders_placed INT,
    total_before_discounts DECIMAL(18,2),
    total_discounts DECIMAL(18,2),
    total_paid_in_week DECIMAL(18,2),
    conversion_cumulative_revenue DECIMAL(18,2),
    lifetime_cumulative_revenue DECIMAL(18,2)
);


-- 3. Insert customer360 query results into the output table

--CTE 1: Static Customer/Conversion Data as base for the spine generation
WITH conversion_base AS (
    SELECT cd.customer_id,
           cd.first_name,
           cd.last_name,
           cs.conversion_id,
           -- We use window functions to sequence the orders of each conversion
           ROW_NUMBER() OVER (PARTITION BY cd.customer_id ORDER BY cs.conversion_date ASC) AS conversion_number,
           cs.conversion_type,
           cs.conversion_date,
           dd.year_week AS conversion_week,
           -- We use window functions to find the next conversion week
           LEAD(dd.year_week,1,NULL) OVER (PARTITION BY cd.customer_id ORDER BY cs.conversion_date) AS next_conversion_week,
           cs.conversion_channel,
           cs.order_number
    FROM fact_tables.conversions AS cs
    RIGHT JOIN dimensions.customer_dimension AS cd -- this is to ensure we keep all customers even if they have no conversions
        ON cs.fk_customer = cd.sk_customer
    LEFT JOIN dimensions.date_dimension AS dd
        ON cs.fk_conversion_date = dd.sk_date
    ),

-- CTE 2: First ever order placed per conversion
    -- !! This does not return first_orders but just all orders per conversion
    -- And nowhere do we actually return the first_order!
first_orders AS (
    SELECT cb.conversion_id,
           -- Confirmed no need to aggregate by conversion_id i.e. 1 conversion to 1 order to 1 product
           cb.order_number,
           dd.year_week AS first_order_week,
           o.price_paid AS first_order_total_paid
    FROM conversion_base AS cb
          INNER JOIN fact_tables.orders AS o
                     ON cb.order_number = o.order_number
          INNER JOIN dimensions.date_dimension AS dd
                     ON o.fk_order_date = dd.sk_date
    ),

-- CTE 3:Pre-aggregate weekly order history to avoid fan-out when joining
aggregated_weekly_order AS (
    SELECT o.fk_customer,
           cd.customer_id,
           dd.year_week          AS order_week,
           COUNT(o.order_number) AS orders_count,
           SUM(o.unit_price)     AS total_before_discounts,
           SUM(o.discount_value) AS total_discounts,
           SUM(o.price_paid)     AS total_paid_in_week
    FROM fact_tables.orders AS o
             LEFT JOIN dimensions.date_dimension AS dd
                       ON o.fk_order_date = dd.sk_date
             LEFT JOIN dimensions.customer_dimension AS cd
                       ON O.fk_customer = cd.sk_customer
    GROUP BY o.fk_customer, cd.customer_id, DD.year_week
    ),

-- CTE 4: Spine generation (create a row for each week between conversion and next_conversion)
weekly_spine AS (
    SELECT cb.*,
            dd.year_week                                                         AS order_week,
            -- Generate a sequence counter starting from 1 for each conversion period
            ROW_NUMBER() OVER (PARTITION BY conversion_id ORDER BY dd.year_week) AS week_counter,
            ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY dd.year_week)   AS lifetime_week_counter -- not used in final output but was used to validate the spine generation    
     FROM conversion_base AS cb
              LEFT JOIN (SELECT DISTINCT year_week FROM dimensions.date_dimension) AS dd
                        ON dd.year_week >= cb.conversion_week
     WHERE (dd.year_week < cb.next_conversion_week OR cb.next_conversion_week IS NULL)
     ),

-- Final CTE 5: Combine everything and compute running totals
final_table AS (
    SELECT
        ws.customer_id,
        ws.first_name,
        ws.last_name,
        ws.conversion_id,
        ws.conversion_number,
        ws.conversion_type,
        ws.conversion_date,
        ws.conversion_week,
        next_conversion_week,
        ws.conversion_channel,
        fo.first_order_week,
        fo.first_order_total_paid,
        ws.week_counter,
        ws.order_week,
        CASE WHEN awo.orders_count > 0 THEN 1 ELSE 0 END AS orders_placed,
        CASE WHEN awo.total_before_discounts IS NULL THEN 0 ELSE awo.total_before_discounts END AS total_before_discounts,
        CASE WHEN awo.total_discounts IS NULL THEN 0 ELSE awo.total_discounts END AS total_discounts,
        CASE WHEN awo.total_paid_in_week IS NULL THEN 0 ELSE awo.total_paid_in_week END AS total_paid_in_week,

    -- Cumulative fields calculated using window functions over the generated spine
        SUM(awo.total_paid_in_week) OVER(PARTITION BY ws.conversion_id ORDER BY ws.order_week) AS conversion_cumulative_revenue,
        SUM(awo.total_paid_in_week) OVER (PARTITION BY ws.customer_id ORDER BY WS.order_week) AS lifetime_cumulative_revenue

    FROM weekly_spine AS ws
    LEFT JOIN first_orders AS fo
        ON ws.conversion_id = fo.conversion_id
    LEFT JOIN aggregated_weekly_order AS awo
        ON ws.customer_id = awo.customer_id AND ws.order_week = awo.order_week
        -- WHERE ws.customer_id = 333
    ORDER BY ws.customer_id, ws.conversion_id, ws.week_counter
    )
INSERT INTO customer360.full_360_view
SELECT * FROM final_table;



