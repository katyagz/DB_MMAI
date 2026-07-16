-- Access for Customer 360 DB
-- See MMAI510 PostgreDB > dimensions & fact_tables schemas
-- Objective: create a Customer360 view for an online retailer.
-- Integrate data from multiple tables to create a unified view containing specified attributes using SQL.

-- Confirming we can query fact_tables schema
SELECT *
FROM fact_tables.conversions AS cs -- use aliases always now when querying many tables
LIMIT 5;

SELECT *
FROM fact_tables.orders AS os
LIMIT 5;

-- Confirming we can query dimensions schema
SELECT *
FROM dimensions.customer_dimension AS cd
LIMIT 5; -- Only 5 - solution should be robust to the table evolving over time

SELECT *
FROM dimensions.date_dimension AS dd
LIMIT 5;

SELECT *
FROM dimensions.product_dimension AS pd
LIMIT 5;


--- CREATE SCHEMA customer360

DROP SCHEMA IF EXISTS customer360 CASCADE;

CREATE SCHEMA IF NOT EXISTS customer360;


-- Customer360 full view

WITH static_cs AS (
    SELECT cd.sk_customer,
       cd.customer_id,
       cd.first_name,
       cd.last_name,
       cs.conversion_id,
       cs.conversion_type,
       cs.conversion_date,
       ROW_NUMBER() OVER (PARTITION BY cd.customer_id ORDER BY cs.conversion_date ASC) AS conversion_number,
       dd.year_week  as conversion_week,
       LEAD(dd.year_week) OVER (PARTITION BY cd.customer_id ORDER BY cs.conversion_date ASC) AS next_conversion_week,
       cs.conversion_channel
FROM dimensions.customer_dimension AS cd
RIGHT JOIN fact_tables.conversions AS cs
    ON cd.sk_customer = cs.fk_customer
LEFT JOIN dimensions.date_dimension AS dd
    ON cs.fk_conversion_date = dd.sk_date
),
    ranked_orders AS (
    SELECT -- sc.sk_customer, -- redundant if conversion_id is unique
           sc.conversion_id,
           sc.conversion_week,
           TO_CHAR(od.order_date, 'IYYY-"W"IW') AS order_week,
           od.price_paid AS order_total_paid,
           ROW_NUMBER() OVER (PARTITION BY sc.sk_customer, sc.conversion_id ORDER BY od.order_date ASC) AS order_rank
FROM static_cs AS sc
LEFT JOIN fact_tables.orders AS od
    ON sc.sk_customer = od.fk_customer
    AND TO_CHAR(od.order_date, 'IYYY-"W"IW') >= sc.conversion_week
    AND TO_CHAR(od.order_date, 'IYYY-"W"IW') < COALESCE(sc.next_conversion_week, TO_CHAR(CURRENT_DATE + INTERVAL '7 days', 'IYYY-"W"IW'))
    ),
    order_history AS (
    SELECT sc.*,
           ro.order_week AS first_order_week,
           ro.order_total_paid AS first_order_total_paid,
           ro.order_rank,
           od.order_date,
           TO_CHAR(od.order_date, 'IYYY-"W"IW') AS order_week,
           od.fk_order_date,
           od.unit_price,
           od.discount_value,
           od.price_paid
    FROM static_cs AS sc
    LEFT JOIN ranked_orders AS ro
        ON sc.conversion_id = ro.conversion_id
        AND ro.order_rank = 1
    LEFT JOIN fact_tables.orders AS od
        ON sc.sk_customer = od.fk_customer
        AND TO_CHAR(od.order_date, 'IYYY-"W"IW') >= sc.conversion_week
        AND TO_CHAR(od.order_date, 'IYYY-"W"IW') < COALESCE(sc.next_conversion_week, TO_CHAR(CURRENT_DATE + INTERVAL '7 days', 'IYYY-"W"IW'))
),
    aggregated_history AS (
    SELECT oh.customer_id,
           oh.first_name,
           oh.last_name,
           oh.first_order_week,
           oh.first_order_total_paid,
           oh.order_rank,
           oh.order_week,
           oh.conversion_id,
           oh.conversion_type,
           oh.conversion_number,
           oh.conversion_week,
           oh.next_conversion_week,
           oh.conversion_channel,
           ddi.year_week,
           CASE WHEN COUNT(oh.order_date) >0 THEN 1 ELSE 0 END AS orders_placed,
           SUM(oh.unit_price) AS total_before_discounts,
           SUM(oh.discount_value) AS total_discounts,
           SUM(oh.price_paid) total_paid_in_week
    FROM dimensions.date_dimension AS ddi
    LEFT JOIN order_history AS oh
        ON ddi.sk_date = oh.fk_order_date
        AND ddi.year_week >= oh.conversion_week
        AND ddi.year_week < COALESCE(oh.next_conversion_week, TO_CHAR(CURRENT_DATE + INTERVAL '7 days', 'IYYY-"W"IW'))
    GROUP BY oh.customer_id, oh.first_name, oh.last_name,
             oh.first_order_week, oh.first_order_total_paid, oh.order_rank,
             oh.order_week, oh.conversion_id, oh.conversion_type,
             oh.conversion_number, oh.conversion_week, oh.next_conversion_week,
             oh.conversion_channel, ddi.year_week
    )
SELECT ah.*,
       ROW_NUMBER() OVER (PARTITION BY customer_id, conversion_id ORDER BY ah.year_week ASC) AS week_counter,
       SUM(ah.total_paid_in_week) OVER (PARTITION BY ah.conversion_id ORDER BY ah.year_week ASC) AS conversion_cumulative_revenue,
       SUM(ah.total_paid_in_week) OVER (PARTITION BY ah.customer_id ORDER BY ah.year_week ASC) AS lifetime_cumulative_revenue
FROM aggregated_history AS ah;