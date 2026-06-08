-- Katya's intro addition
-- Introduction
-- Reading the dataset from mmai_db.public
SELECT *
FROM assignment01.bakery_sales;

-- Assumption 1 : We accept the irregular article name “.”
-- There is one called ".", which is irregular.
SELECT DISTINCT article
FROM assignment01.bakery_sales;
-- Seeing as there are only 5 occurrences, we make assumption 1.
SELECT COUNT(article)
FROM assignment01.bakery_sales
WHERE article = '.';

-- Assumption 2 : We accept negative quantities in the dataset
-- There are no 0 quantity, but 1,295 records with negative quantities, cf. attached report for rationale to make assumption 2.
SELECT *
FROM assignment01.bakery_sales
WHERE quantity < 0
ORDER BY ticket_number;


-- Joe's code with one CTE named rank_table
-- Feranmi updated the GROUP BY clause on line 46 to 'YYYY-MM' date string format to match the aggregation in the PARTITION BY clause 
-- Q1: Top 3 Most Sold Items by Year-Month (2 points)
-- Write a query that reports the top 3 items with the highest total quantity sold for each year-month in the dataset.
-- Your output should include:
-- Year and month
-- Item name
-- Total quantity sold
-- Total revenue for each item
-- Number of unique tickets containing the item
-- ✅ Hint: Use window functions to rank items by quantity within each month.

WITH rank_table AS (
    SELECT TO_CHAR(sale_date, 'YYYY-MM') AS year_month, -- Year and month
        article AS item_name, -- Item name
        SUM(quantity) AS total_quantity_sold, -- Total quantity sold
        SUM(quantity * unit_price) AS total_revenue, -- Total revenue for each item
        COUNT (DISTINCT ticket_number) AS num_unique_tickets, -- Number of unique tickets containing the item
        -- RANK() OVER ( -- Use this alternative to get strictly 3 values per month
        DENSE_RANK() OVER (
            PARTITION BY TO_CHAR(sale_date, 'YYYY-MM')
            ORDER BY SUM(quantity) DESC) AS rank
    FROM assignment01.bakery_sales
    GROUP BY TO_CHAR(sale_date, 'YYYY-MM'), article
)
SELECT year_month,
       item_name,
       total_quantity_sold,
       total_revenue,
       num_unique_tickets
FROM rank_table
WHERE rank <= 3
ORDER BY year_month DESC,
         total_quantity_sold DESC;

---- TO CHAR CAN BE USED INSTEAD OF DATE_TRUNC



-- Fuyao's code with better performance using DATE filtering 
-- Orginal method was to convert sale_date to 'YYYY-MM' date string format and filter on Str type
-- Q2: Tickets with 5 or More Unique Articles (1 point)
-- Identify all sales tickets in December 2021 that include 5 or more unique articles. Your output should include:
-- Ticket ID
-- Number of unique items (articles) in that ticket
-- ✅ Assumption: “Unique articles” refers to distinct item types in a ticket, not quantity.

SELECT -- Select each ticket and count how many distinct articles were purchased on it.
    ticket_number AS ticket_id,
    COUNT(DISTINCT article) AS number_of_unique_items
FROM assignment01.bakery_sales
-- Filter rows to only include sales from December 2021.
-- WHERE TO_CHAR(sale_date, 'YYYY-MM') = '2021-12'
WHERE sale_date >= DATE '2021-12-01'
  AND sale_date < DATE '2022-01-01'
-- Group rows by ticket so the count is calculated per ticket.
GROUP BY ticket_number
-- Keep only tickets with 5 or more unique items.
HAVING COUNT(DISTINCT article) >= 5
ORDER BY number_of_unique_items DESC;


-- Joe's code, with Fuyao's edits to highlight top 1 and attempt to break ties for the Bonus
-- Q3: Most Popular Hour for Traditional Baguette Sales (2 points)
-- Determine the hour of the day when the Traditional Baguette was most frequently purchased during July (across all years).
-- Your query should:
-- Filter for sales of “Traditional Baguette”
-- Group by hour (e.g., 14 for 2 PM)
-- Return the hour with the highest quantity sold
-- ✅ Bonus: You can break ties by selecting the earliest hour of the day in case of equal sales.

SELECT DATE_PART('hour', sale_time) AS hour,
       SUM(quantity) AS total_quantity_sold
FROM assignment01.bakery_sales
WHERE article = 'TRADITIONAL BAGUETTE'
  AND DATE_PART('month', sale_date) = 7
GROUP BY DATE_PART('hour', sale_time)
ORDER BY total_quantity_sold DESC, hour 
LIMIT 1;

-- Joe's code with updated inclusion of 20h+ records in the previous timeslot + Katya's data inspection step
-- Q4: Busiest Two-Hour Window for Sales (3 points)
-- Identify the two-hour window (e.g., 14:00–16:00) in which the highest total quantity of items were sold, across all dates in the dataset.
-- Your output should include:
-- The time range of the two-hour window
-- The total quantity sold and revenue captured during that window
-- ✅ Hints:
-- This question requires reasoning about time intervals that span across rows. You may need to group by hour and combine adjacent hours.
-- Remember that a two-hour window includes both the current hour and the next one.
-- Consider using a self-join, window function, or aggregation logic to combine adjacent hours.

-- Inspect the opening and closing times
SELECT sale_time
FROM assignment01.bakery_sales
ORDER BY sale_time DESC;
-- The store opens at 7AM (the first sale is at 07:01) and it closes at 8PM but the last sale is at 20:01.
-- 20:00 and 20:01 times' records will be included with the preceding timeslot.


SELECT DISTINCT sale_time AS shop_time,
                COUNT(sale_time) AS count
FROM assignment01.bakery_sales
GROUP BY sale_time
ORDER BY sale_time ASC;
-- After analyze transaction time and frequencies to estimate the bakery's shop hours (7-20)
WITH hourly_sales AS (
    SELECT (
        CASE
            WHEN DATE_PART('hour', sale_datetime) > 20 THEN 20 - 1 -- Adjusting last minute sales to previous time window
            ELSE DATE_PART('hour', sale_datetime)
        END
        ) AS sale_hour,
           SUM(quantity) AS total_quantity,
           SUM(quantity * unit_price) AS total_revenue
    FROM assignment01.bakery_sales
    GROUP BY (
        CASE
            WHEN DATE_PART('hour', sale_datetime) > 20 THEN 20 - 1
            ELSE DATE_PART('hour', sale_datetime)
        END
        )
)
SELECT t1.sale_hour AS time_window_start,
       t1.sale_hour + 2 AS time_window_end,
    SUM(t2.total_quantity) AS total_quantity_sold,
    SUM(t2.total_revenue) AS total_revenue
FROM hourly_sales t1
JOIN hourly_sales t2
    ON t2.sale_hour = t1.sale_hour
    OR t2.sale_hour = t1.sale_hour + 1
GROUP BY t1.sale_hour
ORDER BY total_quantity_sold DESC
LIMIT 1;


-- Fuyao's code with a commented addition by Katya in 2) to isolate number of COUPE duplicates
-- Q5: Data Quality Checks (2 points)
-- Write queries to assess the quality of the dataset. Consider checks for:
--
-- Missing values (e.g., NULLs in important columns)
-- Duplicate records
-- Outliers (e.g., negative quantities or unusually high values)
-- Summarize your findings using SQL queries and comments.
-- You may optionally include a few lines of written explanation in your .sql file or in a separate document.

-- 1) Missing values in important columns
SELECT
    COUNT(*) AS total_rows,
    COUNT(*) FILTER (WHERE ticket_number IS NULL) AS missing_ticket_number,
    COUNT(*) FILTER (WHERE sale_date IS NULL) AS missing_sale_date,
    COUNT(*) FILTER (WHERE sale_time IS NULL) AS missing_sale_time,
    COUNT(*) FILTER (WHERE article IS NULL) AS missing_article,
    COUNT(*) FILTER (WHERE quantity IS NULL) AS missing_quantity,
    COUNT(*) FILTER (WHERE unit_price IS NULL) AS missing_unit_price -- found 5 records with missing unit_price
FROM assignment01.bakery_sales;

-- 1) Continued
-- Found out that all of these missing prices were related to article '.', and there are 5 ticket numbers with article '.'
WITH ticket_null_price AS (
    SELECT DISTINCT ticket_number
    FROM assignment01.bakery_sales
    WHERE unit_price IS NULL
)
SELECT bs.*
FROM assignment01.bakery_sales bs
JOIN ticket_null_price t
  ON bs.ticket_number = t.ticket_number
ORDER BY bs.ticket_number; -- After reviewing these records, it doesn't seem like the article '.' were bought standalone.
-- leading me to think they might be cashier mistake?


-- 2) Duplicate records across the full row. Found out there are 1,155 records with at least one duplicate, some even have 5.
SELECT
    ticket_number,
    sale_date,
    sale_time,
    article,
    quantity,
    unit_price,
    COUNT(*) AS duplicate_count
FROM assignment01.bakery_sales
-- WHERE article = 'COUPE'
GROUP BY
    ticket_number,
    sale_date,
    sale_time,
    article,
    quantity,
    unit_price
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC;

-- 2) continued
-- looked into one ticket to figure out why the article's quantity was not aggregated. could not figure out.
SELECT
    *
FROM assignment01.bakery_sales
WHERE ticket_number = '242118'
ORDER BY article;


-- 3) Negative or zero quantities. Found out there are no 0 quantity, but 1,295 records with negative quantities
SELECT *
FROM assignment01.bakery_sales
WHERE quantity < 0
ORDER BY ticket_number;

-- 3) continued. investigate into this 200 qty sales
SELECT *
FROM assignment01.bakery_sales
WHERE ticket_number BETWEEN '179925' AND '179935'
ORDER BY ticket_number;

-- 4) Negative or zero prices. Found out 27 records with 0 prices
SELECT *
FROM assignment01.bakery_sales
WHERE unit_price <= 0
ORDER BY unit_price, ticket_number;

--
SELECT *
FROM assignment01.bakery_sales
WHERE article = '150079'
ORDER BY ticket_number;


-- 5) Outliers in Quantity
-- looked at the stats and saw that the SD & IQR is small (1.3 and 1 respectively)
SELECT
    COUNT(quantity) AS non_null_rows,
    COUNT(*) AS total_rows,
    MIN(quantity) AS min_quantity,
    MAX(quantity) AS max_quantity,
    AVG(quantity) AS avg_quantity,
    SUM(quantity) AS total_quantity,
    STDDEV(quantity) AS stddev_quantity,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY quantity) AS q1_quantity,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY quantity) AS median_quantity,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY quantity) AS q3_quantity,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY quantity)
      - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY quantity) AS iqr_quantity
FROM assignment01.bakery_sales;

-- 5) continued
-- looked at the bins for histogram and assume that quantity above 20 and quantity below 1 could be considered outliers
WITH stats AS (
    SELECT
        MIN(quantity) AS min_q,
        MAX(quantity) AS max_q
    FROM assignment01.bakery_sales
    WHERE quantity IS NOT NULL
)
SELECT
    width_bucket(b.quantity, s.min_q, s.max_q, 20) AS bucket,
    MIN(b.quantity) AS bucket_min,
    MAX(b.quantity) AS bucket_max,
    COUNT(*) AS row_count
FROM assignment01.bakery_sales b
CROSS JOIN stats s
WHERE b.quantity IS NOT NULL
GROUP BY bucket
ORDER BY bucket;


-- 6) Unusually high unit prices
SELECT
    unit_price,
    COUNT(*) AS record_count
FROM assignment01.bakery_sales
GROUP BY 1
ORDER BY 1 DESC ;

-- summary stats of unit_price
SELECT
    COUNT(unit_price) AS non_null_rows,
    COUNT(*) AS total_rows,
    MIN(unit_price) AS min_unit_price,
    MAX(unit_price) AS max_unit_price,
    AVG(unit_price) AS avg_unit_price,
    SUM(unit_price) AS total_unit_price,
    STDDEV(unit_price) AS stddev_unit_price,
    PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY unit_price) AS q1_unit_price,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY unit_price) AS median_unit_price,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY unit_price) AS q3_unit_price,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY unit_price)
      - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY unit_price) AS iqr_unit_price
FROM assignment01.bakery_sales;

-- Histogram of unit_price
WITH stats AS (
    SELECT
        MIN(unit_price) AS min_price,
        MAX(unit_price) AS max_price
    FROM assignment01.bakery_sales
    WHERE unit_price IS NOT NULL
)
SELECT
    width_bucket(b.unit_price, s.min_price, s.max_price, 20) AS bucket,
    MIN(b.unit_price) AS bucket_min,
    MAX(b.unit_price) AS bucket_max,
    COUNT(*) AS record_count
FROM assignment01.bakery_sales b
CROSS JOIN stats s
WHERE b.unit_price IS NOT NULL
GROUP BY bucket
ORDER BY bucket;

-- Investigated into $35 price bucket to check validity
SELECT *
FROM assignment01.bakery_sales
WHERE unit_price >= 35
ORDER BY ticket_number;

-- 7) Check for Invalid date & time
SELECT
    COUNT(*) AS not_aligned
FROM assignment01.bakery_sales
WHERE (sale_date::TIMESTAMP + sale_time::TIME) <> sale_datetime;
-- the sale_date and sale_time columns seem to be aligned with the sale_datetime
-- During the exercises, I did not notice other issues or outliers with the date and time



---------------------------------------------------------------------------------------------------------------------------
-- EXPLORATION OUT OF SELF INTEREST
-- 1) Total revenue by year-month
-- Very seasonal business, with Jul-Aug to be busiest months
SELECT
    DATE_TRUNC('month', sale_date) AS year_month,
    TO_CHAR(DATE_TRUNC('month', sale_date), 'YYYY-MM') AS year_month_char,
    SUM(quantity * unit_price) AS total_revenue,
    TO_CHAR(SUM(quantity * unit_price), 'FM$999,999,999,990.00') AS total_revenue_char
FROM assignment01.bakery_sales
GROUP BY 1, 2
ORDER BY 1;

-- 2) Top 10 ticket_number by revenue, showing all items on those tickets
WITH ticket_revenue AS ( --  creates a temporary result set with total revenue for each ticket.
    SELECT
        ticket_number,
        SUM(quantity * unit_price) AS ticket_total_revenue_num
    FROM assignment01.bakery_sales
    GROUP BY 1
),

-- creates another temporary result set containing only the top 10 tickets.
top_tickets AS (
    SELECT
        ticket_number,
        ticket_total_revenue_num
    FROM ticket_revenue
    ORDER BY ticket_total_revenue_num DESC, ticket_number
    LIMIT 10
)

-- returns the final columns for the detailed ticket output.
SELECT
    TO_CHAR(DATE_TRUNC('month', bs.sale_datetime), 'YYYY-MM') AS year_month, -- shows the month for each item row in YYYY-MM format.
    bs.ticket_number,
    bs.article AS item_name,
    bs.quantity,
    TO_CHAR(bs.unit_price, 'FM$999,999,999,990.00') AS unit_price,
    TO_CHAR(bs.quantity * bs.unit_price, 'FM$999,999,999,990.00') AS line_revenue,
    TO_CHAR(tt.ticket_total_revenue_num, 'FM$999,999,999,990.00') AS ticket_total_revenue
FROM assignment01.bakery_sales bs --  reads from the table and gives it the alias bs.
JOIN top_tickets tt --keeps only rows that belong to the top 10 tickets.
    ON bs.ticket_number = tt.ticket_number
ORDER BY --sorts by highest ticket revenue first, then ticket, then item details.
    tt.ticket_total_revenue_num DESC,
    bs.ticket_number,
    bs.sale_datetime,
    bs.article;


-- SO WEIRD... the LOD for some transaction
SELECT
    *
FROM assignment01.bakery_sales
WHERE ticket_number = '187952';


-- price table by article, indicating the year-month of price change
CREATE TEMP TABLE price_table AS
WITH monthly_price AS (
    SELECT
        article,
        DATE_TRUNC('month', sale_datetime)::date AS month_start,
        MAX(unit_price) AS month_price
    FROM assignment01.bakery_sales
    GROUP BY article, DATE_TRUNC('month', sale_datetime)
),
price_changes AS (
    SELECT
        article,
        TO_CHAR(month_start, 'YYYY-MM') AS year_month,
        month_price,
        LAG(month_price) OVER (
            PARTITION BY article
            ORDER BY month_start
        ) AS previous_price
    FROM monthly_price
)
SELECT
    article,
    year_month,
    month_price,
    previous_price
FROM price_changes
WHERE previous_price IS DISTINCT FROM month_price;

-- Price Table
SELECT *
FROM price_table;

-- All top 20 popular items with Price

CREATE TEMP TABLE top20_table AS
    WITH article_revenue AS (
        SELECT
            article AS item_name,
            SUM(quantity) AS total_quantity_sold,
            SUM(quantity * unit_price) AS total_revenue
        FROM assignment01.bakery_sales
        WHERE article != '.'
        GROUP BY article
    ),
    ranked_articles AS (
        SELECT
            item_name,
            total_quantity_sold,
            total_revenue,
            ROW_NUMBER() OVER (
                ORDER BY total_revenue DESC, item_name
            ) AS revenue_rank
        FROM article_revenue
    ),
    ranked as (SELECT revenue_rank                    AS ranking,
                      item_name,
                      total_quantity_sold,
                      TO_CHAR(total_revenue, 'FM$999,999,999,990.00') AS total_revenue
               FROM ranked_articles
               WHERE revenue_rank <= 20
               ORDER BY revenue_rank
    )
    SELECT
        bs.article,
        ranked.ranking,
        bs.unit_price,
        SUM(bs.quantity * bs.unit_price) AS ticket_total_revenue_num
    FROM assignment01.bakery_sales bs
    JOIN ranked
        ON bs.article = ranked.item_name
    GROUP BY 1, 2, 3
    ORDER BY ticket_total_revenue_num DESC, 1;

-- have had 3 price changes on avg. 2021-01, 2022-02, 2022-06
SELECT
    t.*,
    p.year_month
FROM top20_table t
LEFT JOIN price_table p
    ON t.article = p.article
   AND t.unit_price = p.month_price
ORDER BY ranking, year_month
;

-- TRAITEUR is a weird item from a price-point perspective
SELECT
     sale_datetime, ticket_number, article, quantity, unit_price
FROM assignment01.bakery_sales
WHERE article = 'TRAITEUR'
ORDER BY sale_datetime ;
