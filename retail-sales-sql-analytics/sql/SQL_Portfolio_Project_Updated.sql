/*
================================================================================
RETAIL SALES DATA ANALYSIS
================================================================================

Database       : DataWarehouseAnalytics
SQL Version    : MySQL 8.0+
Source Tables  : dim_customers, dim_products, fact_sales
Staging Tables : stg_dim_customers, stg_dim_products, stg_fact_sales
Views          : report_customers, report_products

PROJECT OVERVIEW
This project explores retail sales data using SQL. It includes data quality
checks, data cleaning, sales analysis, customer and product analysis, and
reporting views.

NOTES
1. The original source tables are kept unchanged. All cleaning is done on
   separate staging tables.

2. Missing order dates are kept as NULL. These records are excluded from
   date-based analysis but can still be used for other calculations.

3. The create_date column in dim_customers is not used for cohort analysis
   because its dates fall outside the historical sales period.

4. Each row in fact_sales represents an order line (a product within an order).
   Use COUNT(DISTINCT order_number) when counting orders.

5. Product profit is an estimate based on the current product cost. Historical
   costs are not available, so the results should be treated accordingly.
   Products with zero cost need further checking.

HOW TO RUN
- Import the three source tables into DataWarehouseAnalytics.
- Run this script using MySQL 8.0 or later.
- The script recreates its own staging tables and reporting views.
- The original source tables are not modified or deleted.

================================================================================
*/
USE DataWarehouseAnalytics;
SELECT DATABASE();


-- ============================================================================
-- 01. DATABASE EXPLORATION
-- ============================================================================

SHOW TABLES;

DESCRIBE dim_customers;
DESCRIBE dim_products;
DESCRIBE fact_sales;

SELECT 'dim_customers' AS table_name, COUNT(*) AS row_count FROM dim_customers
UNION ALL
SELECT 'dim_products', COUNT(*) FROM dim_products
UNION ALL
SELECT 'fact_sales', COUNT(*) FROM fact_sales;


-- ============================================================================
-- 02. RAW DATA QUALITY AUDIT
-- Keep the imported source tables unchanged. These queries inspect them.
-- ============================================================================

-- 2.1 Missing order dates and the sales value attached to those rows
SELECT
    COUNT(*) AS total_sales_lines,
    SUM(order_date IS NULL OR TRIM(order_date) = '') AS rows_missing_order_date,
    SUM(CASE WHEN order_date IS NULL OR TRIM(order_date) = ''
             THEN sales_amount ELSE 0 END)
        AS sales_amount_without_order_date,
    SUM(CASE WHEN order_date IS NULL OR TRIM(order_date) = ''
             THEN quantity ELSE 0 END)
        AS quantity_without_order_date
FROM fact_sales;

-- 2.2 Missing/blank customer attributes
SELECT
    SUM(country IS NULL OR LOWER(TRIM(country)) IN ('', 'n/a', 'na')) AS missing_country,
    SUM(gender IS NULL OR LOWER(TRIM(gender)) IN ('', 'n/a', 'na')) AS missing_gender,
    SUM(marital_status IS NULL OR LOWER(TRIM(marital_status)) IN ('', 'n/a', 'na')) AS missing_marital_status,
    SUM(birthdate IS NULL OR TRIM(birthdate) = '') AS missing_birthdate
FROM dim_customers;

-- 2.3 Missing/blank product attributes and zero-cost products
SELECT
    SUM(category IS NULL OR LOWER(TRIM(category)) IN ('', 'n/a', 'na')) AS missing_category,
    SUM(subcategory IS NULL OR LOWER(TRIM(subcategory)) IN ('', 'n/a', 'na')) AS missing_subcategory,
    SUM(maintenance IS NULL OR LOWER(TRIM(maintenance)) IN ('', 'n/a', 'na')) AS missing_maintenance,
    SUM(product_line IS NULL OR LOWER(TRIM(product_line)) IN ('', 'n/a', 'na')) AS missing_product_line,
    SUM(cost = 0) AS zero_cost_products
FROM dim_products;

-- Inspect the products with zero recorded cost before using cost for margin analysis
SELECT product_key, product_id, product_name, category, cost
FROM dim_products
WHERE cost = 0
ORDER BY product_key;

-- 2.4 Validate sales_amount = price * quantity
-- Expected result for the supplied dataset: zero mismatched rows.
SELECT COUNT(*) AS sales_amount_mismatches
FROM fact_sales
WHERE sales_amount <> price * quantity;

-- 2.5 Check duplicate order/product lines
-- Expected result: no rows for the supplied dataset.
SELECT
    order_number,
    product_key,
    COUNT(*) AS line_count
FROM fact_sales
GROUP BY order_number, product_key
HAVING COUNT(*) > 1;

-- 2.6 Check unmatched customer keys
-- Expected result: zero rows for the supplied dataset.
SELECT COUNT(*) AS unmatched_customer_rows
FROM fact_sales f
LEFT JOIN dim_customers c
    ON f.customer_key = c.customer_key
WHERE c.customer_key IS NULL;

-- 2.7 Check unmatched product keys
-- Expected result: zero rows for the supplied dataset.
SELECT COUNT(*) AS unmatched_product_rows
FROM fact_sales f
LEFT JOIN dim_products p
    ON f.product_key = p.product_key
WHERE p.product_key IS NULL;

-- 2.8 Inspect the date ranges independently.
SELECT
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date,
    MIN(shipping_date) AS first_shipping_date,
    MAX(shipping_date) AS last_shipping_date
FROM fact_sales
WHERE order_date IS NOT NULL AND TRIM(order_date) <> '';

-- create_date is inspected, but is NOT treated as signup_date without metadata.
SELECT
    MIN(create_date) AS earliest_customer_create_date,
    MAX(create_date) AS latest_customer_create_date
FROM dim_customers;


-- ============================================================================
-- 03. CREATE CLEAN STAGING COPIES (RAW TABLES REMAIN UNCHANGED)
-- ============================================================================

-- Re-running this section replaces only the staging copies and report views
-- created by this script. Drop dependent views first so they can be recreated
-- against the refreshed staging tables below.
DROP VIEW IF EXISTS report_customers;
DROP VIEW IF EXISTS report_products;

DROP TABLE IF EXISTS stg_fact_sales;
DROP TABLE IF EXISTS stg_dim_products;
DROP TABLE IF EXISTS stg_dim_customers;

CREATE TABLE stg_dim_customers LIKE dim_customers;
CREATE TABLE stg_dim_products LIKE dim_products;
CREATE TABLE stg_fact_sales LIKE fact_sales;

INSERT INTO stg_dim_customers (
    customer_key, customer_id, customer_number, first_name, last_name,
    country, marital_status, gender, birthdate, create_date
)
SELECT
    customer_key, customer_id, customer_number, first_name, last_name,
    country, marital_status, gender, birthdate, create_date
FROM dim_customers;

INSERT INTO stg_dim_products (
    product_key, product_id, product_number, product_name, category_id,
    category, subcategory, maintenance, cost, product_line, start_date
)
SELECT
    product_key, product_id, product_number, product_name, category_id,
    category, subcategory, maintenance, cost, product_line, start_date
FROM dim_products;

INSERT INTO stg_fact_sales (
    order_number, product_key, customer_key, order_date, shipping_date,
    due_date, sales_amount, quantity, price
)
SELECT
    order_number, product_key, customer_key, order_date, shipping_date,
    due_date, sales_amount, quantity, price
FROM fact_sales;

-- Standardize text attributes in staging only.
-- Empty date strings are normalized to NULL; missing dates are never fabricated.
SET SQL_SAFE_UPDATES = 0;

UPDATE stg_dim_customers
SET
    country = CASE
        WHEN country IS NULL OR LOWER(TRIM(country)) IN ('', 'n/a', 'na')
            THEN 'Unknown'
        ELSE TRIM(country)
    END,
    gender = CASE
        WHEN gender IS NULL OR LOWER(TRIM(gender)) IN ('', 'n/a', 'na')
            THEN 'Unknown'
        ELSE TRIM(gender)
    END,
    marital_status = CASE
        WHEN marital_status IS NULL
             OR LOWER(TRIM(marital_status)) IN ('', 'n/a', 'na')
            THEN 'Unknown'
        ELSE TRIM(marital_status)
    END;

UPDATE stg_dim_products
SET
    category = CASE
        WHEN category IS NULL OR LOWER(TRIM(category)) IN ('', 'n/a', 'na')
            THEN 'Unassigned'
        ELSE TRIM(category)
    END,
    subcategory = CASE
        WHEN subcategory IS NULL OR LOWER(TRIM(subcategory)) IN ('', 'n/a', 'na')
            THEN 'Unassigned'
        ELSE TRIM(subcategory)
    END,
    maintenance = CASE
        WHEN maintenance IS NULL
             OR LOWER(TRIM(maintenance)) IN ('', 'n/a', 'na')
            THEN 'Unknown'
        ELSE TRIM(maintenance)
    END,
    product_line = CASE
        WHEN product_line IS NULL
             OR LOWER(TRIM(product_line)) IN ('', 'n/a', 'na')
            THEN 'Unknown'
        ELSE TRIM(product_line)
    END;

-- Normalize empty date strings to NULL if the CSV importer stored them as text.
-- Existing valid dates are unchanged.
UPDATE stg_dim_customers
SET birthdate = NULL
WHERE birthdate IS NOT NULL AND TRIM(birthdate) = '';

UPDATE stg_fact_sales
SET order_date = NULL
WHERE order_date IS NOT NULL AND TRIM(order_date) = '';

SET SQL_SAFE_UPDATES = 1;

-- Verify staging row counts match the source row counts.
SELECT 'dim_customers' AS table_name,
       (SELECT COUNT(*) FROM dim_customers) AS raw_rows,
       (SELECT COUNT(*) FROM stg_dim_customers) AS staging_rows
UNION ALL
SELECT 'dim_products',
       (SELECT COUNT(*) FROM dim_products),
       (SELECT COUNT(*) FROM stg_dim_products)
UNION ALL
SELECT 'fact_sales',
       (SELECT COUNT(*) FROM fact_sales),
       (SELECT COUNT(*) FROM stg_fact_sales);

-- Confirm missing order dates were preserved, not fabricated.
SELECT COUNT(*) AS staging_rows_missing_order_date
FROM stg_fact_sales
WHERE order_date IS NULL;


-- ============================================================================
-- 04. DIMENSIONS EXPLORATION
-- ============================================================================

-- Explore all countries customers come from.
SELECT DISTINCT country
FROM stg_dim_customers
ORDER BY country;

-- Explore product hierarchy: category -> subcategory -> product.
SELECT DISTINCT category, subcategory, product_name
FROM stg_dim_products
ORDER BY category, subcategory, product_name;

-- Count values at each level of the product hierarchy.
SELECT
    COUNT(DISTINCT category) AS category_count,
    COUNT(DISTINCT subcategory) AS subcategory_count,
    COUNT(DISTINCT product_key) AS product_count
FROM stg_dim_products;


-- ============================================================================
-- 05. DATE EXPLORATION
-- ============================================================================

-- 5.1 Date boundaries and calendar coverage.
-- years_with_sales counts distinct calendar years, unlike elapsed whole years.
SELECT
    MIN(order_date) AS first_order_date,
    MAX(order_date) AS last_order_date,
    COUNT(DISTINCT YEAR(order_date)) AS years_with_sales,
    TIMESTAMPDIFF(MONTH, MIN(order_date), MAX(order_date)) AS elapsed_months,
    TIMESTAMPDIFF(MONTH, MIN(order_date), MAX(order_date)) + 1
        AS inclusive_calendar_months
FROM stg_fact_sales
WHERE order_date IS NOT NULL AND TRIM(order_date) <> '';

-- 5.2 Youngest and oldest customers with known birthdates.
SELECT
    MIN(birthdate) AS oldest_birthdate,
    TIMESTAMPDIFF(YEAR, MIN(birthdate), CURDATE()) AS oldest_age,
    MAX(birthdate) AS youngest_birthdate,
    TIMESTAMPDIFF(YEAR, MAX(birthdate), CURDATE()) AS youngest_age
FROM stg_dim_customers
WHERE birthdate IS NOT NULL;


-- ============================================================================
-- 06. MEASURES EXPLORATION (BUSINESS KPI / BIG NUMBERS)
-- ============================================================================

-- Total sales. Includes rows whose order_date is NULL because sales_amount exists.
SELECT SUM(sales_amount) AS total_sales
FROM stg_fact_sales;

-- Total units sold.
SELECT SUM(quantity) AS total_quantity
FROM stg_fact_sales;

-- Quantity-weighted average selling price per unit.
SELECT
    ROUND(SUM(sales_amount) / NULLIF(SUM(quantity), 0), 2)
        AS weighted_average_selling_price
FROM stg_fact_sales;

-- Total distinct orders (not sales-line count).
SELECT COUNT(DISTINCT order_number) AS total_orders
FROM stg_fact_sales;

-- Total products in the catalogue.
SELECT COUNT(*) AS total_products
FROM stg_dim_products;

-- Total customers in the customer dimension.
SELECT COUNT(*) AS total_customers
FROM stg_dim_customers;

-- Distinct customers who have at least one recorded sales line.
SELECT COUNT(DISTINCT customer_key) AS customers_with_orders
FROM stg_fact_sales;

-- Consolidated KPI output. Each row is one business metric.
SELECT 'Total Sales' AS metric_name, SUM(sales_amount) AS metric_value
FROM stg_fact_sales
UNION ALL
SELECT 'Total Quantity', SUM(quantity)
FROM stg_fact_sales
UNION ALL
SELECT 'Weighted Average Selling Price',
       SUM(sales_amount) / NULLIF(SUM(quantity), 0)
FROM stg_fact_sales
UNION ALL
SELECT 'Total Orders', COUNT(DISTINCT order_number)
FROM stg_fact_sales
UNION ALL
SELECT 'Total Products', COUNT(*)
FROM stg_dim_products
UNION ALL
SELECT 'Total Customers', COUNT(*)
FROM stg_dim_customers
UNION ALL
SELECT 'Customers With Orders', COUNT(DISTINCT customer_key)
FROM stg_fact_sales;


-- ============================================================================
-- 07. MAGNITUDE ANALYSIS
-- Compare measures across business dimensions.
-- ============================================================================

-- Customer distribution by country.
SELECT country, COUNT(*) AS total_customers
FROM stg_dim_customers
GROUP BY country
ORDER BY total_customers DESC;

-- Customer distribution by gender.
SELECT gender, COUNT(*) AS total_customers
FROM stg_dim_customers
GROUP BY gender
ORDER BY total_customers DESC;

-- Product count by category.
SELECT category, COUNT(*) AS total_products
FROM stg_dim_products
GROUP BY category
ORDER BY total_products DESC;

-- Average listed product cost by category. Zero costs are retained and shown
-- separately in the data-quality audit; do not assume zero means missing.
SELECT category, ROUND(AVG(cost), 2) AS average_listed_cost
FROM stg_dim_products
GROUP BY category
ORDER BY average_listed_cost DESC;

-- Revenue by category, including categories/products with no sales.
SELECT
    p.category,
    COALESCE(SUM(s.sales_amount), 0) AS total_revenue
FROM stg_dim_products p
LEFT JOIN stg_fact_sales s
    ON p.product_key = s.product_key
GROUP BY p.category
ORDER BY total_revenue DESC;

-- Revenue by customer, including customers with no recorded sales.
SELECT
    c.customer_key,
    c.first_name,
    c.last_name,
    COALESCE(SUM(s.sales_amount), 0) AS total_revenue
FROM stg_dim_customers c
LEFT JOIN stg_fact_sales s
    ON c.customer_key = s.customer_key
GROUP BY c.customer_key, c.first_name, c.last_name
ORDER BY total_revenue DESC;

-- Quantity sold by customer country.
SELECT
    c.country,
    SUM(s.quantity) AS total_units_sold
FROM stg_fact_sales s
JOIN stg_dim_customers c
    ON s.customer_key = c.customer_key
GROUP BY c.country
ORDER BY total_units_sold DESC;


-- ============================================================================
-- 08. RANKING ANALYSIS
-- ============================================================================

-- Top 5 products by revenue (exactly five rows; ties may be cut off).
SELECT
    p.product_key,
    p.product_name,
    SUM(s.sales_amount) AS total_revenue
FROM stg_dim_products p
JOIN stg_fact_sales s
    ON p.product_key = s.product_key
GROUP BY p.product_key, p.product_name
ORDER BY total_revenue DESC, p.product_key
LIMIT 5;

-- Top 5 revenue ranks, including ties.
WITH product_revenue AS (
    SELECT
        p.product_key,
        p.product_name,
        SUM(s.sales_amount) AS total_revenue
    FROM stg_dim_products p
    JOIN stg_fact_sales s
        ON p.product_key = s.product_key
    GROUP BY p.product_key, p.product_name
), ranked_products AS (
    SELECT
        *,
        RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank
    FROM product_revenue
)
SELECT product_key, product_name, total_revenue, revenue_rank
FROM ranked_products
WHERE revenue_rank <= 5
ORDER BY revenue_rank, product_key;

-- Five lowest-revenue products among products that have at least one sale.
SELECT
    p.product_key,
    p.product_name,
    SUM(s.sales_amount) AS total_revenue
FROM stg_dim_products p
JOIN stg_fact_sales s
    ON p.product_key = s.product_key
GROUP BY p.product_key, p.product_name
ORDER BY total_revenue ASC, p.product_key
LIMIT 5;

-- Top 10 customers by revenue.
SELECT
    c.customer_key,
    c.first_name,
    c.last_name,
    SUM(s.sales_amount) AS total_revenue
FROM stg_dim_customers c
JOIN stg_fact_sales s
    ON c.customer_key = s.customer_key
GROUP BY c.customer_key, c.first_name, c.last_name
ORDER BY total_revenue DESC, c.customer_key
LIMIT 10;

-- Three customers with the fewest distinct orders. Includes zero-order customers.
SELECT
    c.customer_key,
    c.first_name,
    c.last_name,
    COUNT(DISTINCT s.order_number) AS total_orders
FROM stg_dim_customers c
LEFT JOIN stg_fact_sales s
    ON c.customer_key = s.customer_key
GROUP BY c.customer_key, c.first_name, c.last_name
ORDER BY total_orders ASC, c.customer_key
LIMIT 3;

-- Products in the catalogue that have never sold.
SELECT p.product_key, p.product_name, p.category
FROM stg_dim_products p
LEFT JOIN stg_fact_sales s
    ON p.product_key = s.product_key
WHERE s.product_key IS NULL
ORDER BY p.product_key;


-- ============================================================================
-- 09. CHANGES OVER TIME ANALYSIS
-- ============================================================================

-- Monthly sales, distinct orders, customers, and units.
-- 2010 and 2014 are partial years in this dataset; avoid comparing them as
-- complete years against 2011-2013 without restricting to comparable periods.
SELECT
    YEAR(order_date) AS order_year,
    MONTH(order_date) AS order_month,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT order_number) AS total_orders,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity) AS total_quantity
FROM stg_fact_sales
WHERE order_date IS NOT NULL AND TRIM(order_date) <> ''
GROUP BY YEAR(order_date), MONTH(order_date)
ORDER BY order_year, order_month;

-- Annual sales summary. Treat the first and last years as partial years.
SELECT
    YEAR(order_date) AS order_year,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT order_number) AS total_orders,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity) AS total_quantity
FROM stg_fact_sales
WHERE order_date IS NOT NULL AND TRIM(order_date) <> ''
GROUP BY YEAR(order_date)
ORDER BY order_year;


-- ============================================================================
-- 10. CUMULATIVE & ROLLING ANALYSIS
-- Generate a complete month calendar so ROWS windows represent calendar months,
-- even if one or more months have zero sales.
-- ============================================================================

WITH RECURSIVE date_bounds AS (
    SELECT
        CAST(DATE_FORMAT(MIN(order_date), '%Y-%m-01') AS DATE) AS first_month,
        CAST(DATE_FORMAT(MAX(order_date), '%Y-%m-01') AS DATE) AS last_month
    FROM stg_fact_sales
    WHERE order_date IS NOT NULL AND TRIM(order_date) <> ''
), months AS (
    SELECT first_month AS month_start
    FROM date_bounds
    WHERE first_month IS NOT NULL

    UNION ALL

    SELECT DATE_ADD(m.month_start, INTERVAL 1 MONTH)
    FROM months m
    CROSS JOIN date_bounds b
    WHERE m.month_start < b.last_month
), monthly_sales AS (
    SELECT
        CAST(DATE_FORMAT(order_date, '%Y-%m-01') AS DATE) AS month_start,
        SUM(sales_amount) AS total_sales,
        SUM(quantity) AS total_quantity
    FROM stg_fact_sales
    WHERE order_date IS NOT NULL AND TRIM(order_date) <> ''
    GROUP BY CAST(DATE_FORMAT(order_date, '%Y-%m-01') AS DATE)
), monthly_spine AS (
    SELECT
        m.month_start,
        COALESCE(ms.total_sales, 0) AS total_sales,
        COALESCE(ms.total_quantity, 0) AS total_quantity
    FROM months m
    LEFT JOIN monthly_sales ms
        ON m.month_start = ms.month_start
)
SELECT
    YEAR(month_start) AS sales_year,
    MONTH(month_start) AS sales_month,
    total_sales,
    total_quantity,
    SUM(total_sales) OVER (
        ORDER BY month_start
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_sales,
    SUM(total_sales) OVER (
        ORDER BY month_start
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3_month_sales,
    ROUND(
        AVG(total_sales) OVER (
            ORDER BY month_start
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ), 2
    ) AS rolling_3_month_average_sales
FROM monthly_spine
ORDER BY month_start;


-- ============================================================================
-- 11. PRODUCT PERFORMANCE ANALYSIS
-- Compare product sales with the product's average observed-year sales and its
-- immediately previous calendar year's sales where that prior year is present.
-- ============================================================================

WITH annual_product_sales AS (
    SELECT
        p.product_key,
        p.product_name,
        YEAR(s.order_date) AS sales_year,
        SUM(s.sales_amount) AS yearly_sales
    FROM stg_fact_sales s
    JOIN stg_dim_products p
        ON s.product_key = p.product_key
    WHERE s.order_date IS NOT NULL AND TRIM(s.order_date) <> ''
    GROUP BY p.product_key, p.product_name, YEAR(s.order_date)
), product_comparison AS (
    SELECT
        *,
        AVG(yearly_sales) OVER (
            PARTITION BY product_key
        ) AS average_observed_year_sales,
        LAG(sales_year) OVER (
            PARTITION BY product_key ORDER BY sales_year
        ) AS previous_observed_year,
        LAG(yearly_sales) OVER (
            PARTITION BY product_key ORDER BY sales_year
        ) AS previous_observed_year_sales
    FROM annual_product_sales
)
SELECT
    sales_year,
    product_key,
    product_name,
    yearly_sales,
    ROUND(average_observed_year_sales, 2) AS average_observed_year_sales,
    yearly_sales - average_observed_year_sales AS difference_from_average,
    CASE
        WHEN yearly_sales > average_observed_year_sales THEN 'Above Average'
        WHEN yearly_sales < average_observed_year_sales THEN 'Below Average'
        ELSE 'Average'
    END AS average_performance,
    previous_observed_year,
    previous_observed_year_sales,
    CASE
        WHEN previous_observed_year = sales_year - 1
            THEN yearly_sales - previous_observed_year_sales
        ELSE NULL
    END AS yoy_difference,
    CASE
        WHEN previous_observed_year = sales_year - 1
        THEN ROUND(
            (yearly_sales - previous_observed_year_sales)
            / NULLIF(previous_observed_year_sales, 0) * 100,
            2
        )
        ELSE NULL
    END AS yoy_growth_pct,
    CASE
        WHEN previous_observed_year IS NULL THEN 'No Prior Observation'
        WHEN previous_observed_year <> sales_year - 1 THEN 'Prior Calendar Year Missing'
        WHEN yearly_sales > previous_observed_year_sales THEN 'Increase'
        WHEN yearly_sales < previous_observed_year_sales THEN 'Decrease'
        ELSE 'No Change'
    END AS yoy_status
FROM product_comparison
ORDER BY product_key, sales_year;


-- ============================================================================
-- 12. PART-TO-WHOLE ANALYSIS
-- ============================================================================

-- Category contribution to overall revenue. Keep percentage numeric for BI use.
WITH category_sales AS (
    SELECT
        p.category,
        SUM(s.sales_amount) AS total_sales
    FROM stg_fact_sales s
    JOIN stg_dim_products p
        ON s.product_key = p.product_key
    GROUP BY p.category
)
SELECT
    category,
    total_sales,
    SUM(total_sales) OVER () AS overall_sales,
    ROUND(
        total_sales / NULLIF(SUM(total_sales) OVER (), 0) * 100,
        2
    ) AS percentage_of_total
FROM category_sales
ORDER BY total_sales DESC;


-- ============================================================================
-- 13. DATA SEGMENTATION
-- ============================================================================

-- Segment products by listed cost. Ranges are mutually exclusive.
-- Zero cost is kept in a separate review bucket rather than silently treated
-- as a normal low-cost product.
WITH product_segments AS (
    SELECT
        product_key,
        product_name,
        cost,
        CASE
            WHEN cost IS NULL THEN 'Unknown Cost'
            WHEN cost = 0 THEN 'Zero Cost - Review'
            WHEN cost < 100 THEN 'Below 100'
            WHEN cost < 500 THEN '100-499'
            WHEN cost < 1000 THEN '500-999'
            ELSE '1000 and Above'
        END AS cost_range
    FROM stg_dim_products
)
SELECT
    cost_range,
    COUNT(*) AS total_products
FROM product_segments
GROUP BY cost_range
ORDER BY MIN(cost);

-- Segment ALL customers by purchase history and spending.
-- Lifespan is elapsed months between first and last dated purchases.
WITH customer_metrics AS (
    SELECT
        c.customer_key,
        COUNT(DISTINCT s.order_number) AS total_orders,
        COALESCE(SUM(s.sales_amount), 0) AS total_spending,
        MIN(s.order_date) AS first_order_date,
        MAX(s.order_date) AS last_order_date,
        TIMESTAMPDIFF(MONTH, MIN(s.order_date), MAX(s.order_date)) AS lifespan_months
    FROM stg_dim_customers c
    LEFT JOIN stg_fact_sales s
        ON c.customer_key = s.customer_key
    GROUP BY c.customer_key
), classified_customers AS (
    SELECT
        *,
        CASE
            WHEN total_orders = 0 THEN 'No Purchase'
            WHEN first_order_date IS NULL THEN 'Purchase Date Unavailable'
            WHEN lifespan_months >= 12 AND total_spending > 5000 THEN 'VIP'
            WHEN lifespan_months >= 12 AND total_spending <= 5000 THEN 'Regular'
            ELSE 'New'
        END AS customer_segment
    FROM customer_metrics
)
SELECT
    customer_segment,
    COUNT(*) AS total_customers
FROM classified_customers
GROUP BY customer_segment
ORDER BY total_customers DESC;


-- ============================================================================
-- 14. BUILD CUSTOMER REPORT VIEW
-- One row per customer, including customers with no purchases.
-- Monthly averages use dated sales only; total_sales still includes undated rows.
-- Recency is measured against the latest order_date in this historical dataset,
-- NOT CURDATE(), so the historical report remains interpretable.
-- ============================================================================

CREATE OR REPLACE VIEW report_customers AS
WITH sales_by_customer AS (
    SELECT
        customer_key,
        COUNT(DISTINCT order_number) AS total_orders,
        SUM(sales_amount) AS total_sales,
        SUM(CASE WHEN order_date IS NOT NULL AND TRIM(order_date) <> ''
                 THEN sales_amount ELSE 0 END) AS sales_with_valid_date,
        SUM(quantity) AS total_quantity,
        COUNT(DISTINCT product_key) AS total_products,
        MIN(order_date) AS first_order_date,
        MAX(order_date) AS last_order_date
    FROM stg_fact_sales
    GROUP BY customer_key
), analysis_date AS (
    SELECT MAX(order_date) AS data_as_of_date
    FROM stg_fact_sales
), customer_base AS (
    SELECT
        c.customer_key,
        c.customer_id,
        c.customer_number,
        CONCAT_WS(' ', c.first_name, c.last_name) AS customer_name,
        c.country,
        c.gender,
        c.marital_status,
        c.birthdate,
        TIMESTAMPDIFF(YEAR, c.birthdate, CURDATE()) AS age,
        COALESCE(s.total_orders, 0) AS total_orders,
        COALESCE(s.total_sales, 0) AS total_sales,
        COALESCE(s.sales_with_valid_date, 0) AS sales_with_valid_date,
        COALESCE(s.total_quantity, 0) AS total_quantity,
        COALESCE(s.total_products, 0) AS total_products,
        s.first_order_date,
        s.last_order_date,
        CASE
            WHEN s.first_order_date IS NOT NULL AND s.last_order_date IS NOT NULL
            THEN TIMESTAMPDIFF(MONTH, s.first_order_date, s.last_order_date)
            ELSE NULL
        END AS active_span_months,
        CASE
            WHEN s.first_order_date IS NOT NULL AND s.last_order_date IS NOT NULL
            THEN TIMESTAMPDIFF(MONTH, s.first_order_date, s.last_order_date) + 1
            ELSE NULL
        END AS observed_calendar_months
    FROM stg_dim_customers c
    LEFT JOIN sales_by_customer s
        ON c.customer_key = s.customer_key
)
SELECT
    cb.customer_key,
    cb.customer_id,
    cb.customer_number,
    cb.customer_name,
    cb.country,
    cb.gender,
    cb.marital_status,
    cb.age,
    CASE
        WHEN cb.age IS NULL THEN 'Unknown'
        WHEN cb.age < 20 THEN 'Under 20'
        WHEN cb.age BETWEEN 20 AND 29 THEN '20-29'
        WHEN cb.age BETWEEN 30 AND 39 THEN '30-39'
        WHEN cb.age BETWEEN 40 AND 49 THEN '40-49'
        ELSE '50 and Above'
    END AS age_group,
    CASE
        WHEN cb.total_orders = 0 THEN 'No Purchase'
        WHEN cb.first_order_date IS NULL THEN 'Purchase Date Unavailable'
        WHEN cb.active_span_months >= 12 AND cb.total_sales > 5000 THEN 'VIP'
        WHEN cb.active_span_months >= 12 AND cb.total_sales <= 5000 THEN 'Regular'
        ELSE 'New'
    END AS customer_segment,
    ad.data_as_of_date,
    cb.first_order_date,
    cb.last_order_date,
    CASE
        WHEN cb.last_order_date IS NOT NULL
        THEN TIMESTAMPDIFF(MONTH, cb.last_order_date, ad.data_as_of_date)
        ELSE NULL
    END AS recency_months,
    cb.total_orders,
    cb.total_sales,
    cb.sales_with_valid_date,
    cb.total_quantity,
    cb.total_products,
    cb.active_span_months,
    cb.observed_calendar_months,
    ROUND(cb.total_sales / NULLIF(cb.total_orders, 0), 2) AS average_order_value,
    CASE
        WHEN cb.observed_calendar_months IS NOT NULL
        THEN ROUND(cb.sales_with_valid_date / NULLIF(cb.observed_calendar_months, 0), 2)
        ELSE NULL
    END AS average_monthly_spend
FROM customer_base cb
CROSS JOIN analysis_date ad;

-- Inspect the customer report.
SELECT *
FROM report_customers
ORDER BY total_sales DESC;


-- ============================================================================
-- 15. BUILD PRODUCT REPORT VIEW
-- One row per product, including the 0-sales products in the catalogue.
-- ============================================================================

CREATE OR REPLACE VIEW report_products AS
WITH product_sales AS (
    SELECT
        product_key,
        COUNT(DISTINCT order_number) AS total_orders,
        COUNT(DISTINCT customer_key) AS total_customers,
        SUM(sales_amount) AS total_sales,
        SUM(CASE WHEN order_date IS NOT NULL AND TRIM(order_date) <> ''
                 THEN sales_amount ELSE 0 END) AS sales_with_valid_date,
        SUM(quantity) AS total_quantity,
        MIN(order_date) AS first_sale_date,
        MAX(order_date) AS last_sale_date
    FROM stg_fact_sales
    GROUP BY product_key
), analysis_date AS (
    SELECT MAX(order_date) AS data_as_of_date
    FROM stg_fact_sales
), product_base AS (
    SELECT
        p.product_key,
        p.product_id,
        p.product_number,
        p.product_name,
        p.category,
        p.subcategory,
        p.cost,
        COALESCE(s.total_orders, 0) AS total_orders,
        COALESCE(s.total_customers, 0) AS total_customers,
        COALESCE(s.total_sales, 0) AS total_sales,
        COALESCE(s.sales_with_valid_date, 0) AS sales_with_valid_date,
        COALESCE(s.total_quantity, 0) AS total_quantity,
        s.first_sale_date,
        s.last_sale_date,
        CASE
            WHEN s.first_sale_date IS NOT NULL AND s.last_sale_date IS NOT NULL
            THEN TIMESTAMPDIFF(MONTH, s.first_sale_date, s.last_sale_date)
            ELSE NULL
        END AS active_span_months,
        CASE
            WHEN s.first_sale_date IS NOT NULL AND s.last_sale_date IS NOT NULL
            THEN TIMESTAMPDIFF(MONTH, s.first_sale_date, s.last_sale_date) + 1
            ELSE NULL
        END AS observed_calendar_months
    FROM stg_dim_products p
    LEFT JOIN product_sales s
        ON p.product_key = s.product_key
)
SELECT
    pb.product_key,
    pb.product_id,
    pb.product_number,
    pb.product_name,
    pb.category,
    pb.subcategory,
    pb.cost,
    ad.data_as_of_date,
    pb.first_sale_date,
    pb.last_sale_date,
    CASE
        WHEN pb.last_sale_date IS NOT NULL
        THEN TIMESTAMPDIFF(MONTH, pb.last_sale_date, ad.data_as_of_date)
        ELSE NULL
    END AS recency_months,
    CASE
        WHEN pb.total_orders = 0 THEN 'No Sales'
        WHEN pb.total_sales > 50000 THEN 'High Performer'
        WHEN pb.total_sales >= 10000 THEN 'Mid-Range'
        ELSE 'Low Performer'
    END AS product_segment,
    pb.active_span_months,
    pb.observed_calendar_months,
    pb.total_orders,
    pb.total_customers,
    pb.total_sales,
    pb.sales_with_valid_date,
    pb.total_quantity,
    ROUND(pb.total_sales / NULLIF(pb.total_quantity, 0), 2)
        AS weighted_average_selling_price,
    ROUND(pb.total_sales / NULLIF(pb.total_orders, 0), 2)
        AS average_revenue_per_order_containing_product,
    CASE
        WHEN pb.observed_calendar_months IS NOT NULL
        THEN ROUND(pb.sales_with_valid_date / NULLIF(pb.observed_calendar_months, 0), 2)
        ELSE NULL
    END AS average_monthly_revenue,
    -- Estimated gross profit is shown only for products with positive recorded cost.
    -- Verify that product master cost is applicable to the historical sale period.
    CASE
        WHEN pb.cost > 0
        THEN pb.total_sales - (pb.total_quantity * pb.cost)
        ELSE NULL
    END AS estimated_gross_profit,
    CASE
        WHEN pb.cost > 0 AND pb.total_sales <> 0
        THEN ROUND(
            (pb.total_sales - (pb.total_quantity * pb.cost))
            / pb.total_sales * 100,
            2
        )
        ELSE NULL
    END AS estimated_gross_margin_pct
FROM product_base pb
CROSS JOIN analysis_date ad;

-- Inspect the complete product report (including products with no sales).
SELECT *
FROM report_products
ORDER BY total_sales DESC;


-- ============================================================================
-- 16. CUSTOMER REPEAT-PURCHASE ANALYSIS
-- Order counts are DISTINCT order_number because fact_sales is order-line grain.
-- ============================================================================

WITH customer_order_counts AS (
    SELECT
        c.customer_key,
        COUNT(DISTINCT s.order_number) AS order_count
    FROM stg_dim_customers c
    LEFT JOIN stg_fact_sales s
        ON c.customer_key = s.customer_key
    GROUP BY c.customer_key
), customer_purchase_segments AS (
    SELECT
        customer_key,
        order_count,
        CASE
            WHEN order_count = 0 THEN 'No Purchase'
            WHEN order_count = 1 THEN 'One-Time Customer'
            ELSE 'Repeat Customer'
        END AS purchase_segment
    FROM customer_order_counts
)
SELECT
    purchase_segment,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER () * 100, 2) AS percentage_of_all_customers
FROM customer_purchase_segments
GROUP BY purchase_segment
ORDER BY customer_count DESC;

-- Repeat purchase rate among customers who placed at least one order.
WITH customer_order_counts AS (
    SELECT
        c.customer_key,
        COUNT(DISTINCT s.order_number) AS order_count
    FROM stg_dim_customers c
    LEFT JOIN stg_fact_sales s
        ON c.customer_key = s.customer_key
    GROUP BY c.customer_key
)
SELECT
    SUM(order_count > 1) AS repeat_customers,
    SUM(order_count > 0) AS purchasing_customers,
    ROUND(
        SUM(order_count > 1) / NULLIF(SUM(order_count > 0), 0) * 100,
        2
    ) AS repeat_purchase_rate_pct
FROM customer_order_counts;


-- ============================================================================
-- 17. SHIPPING PERFORMANCE ANALYSIS
-- fact_sales contains multiple product lines per order, so first aggregate to
-- one row per order. This measures shipping lead time, not final delivery time.
-- ============================================================================

WITH order_level AS (
    SELECT
        order_number,
        MIN(order_date) AS order_date,
        MIN(shipping_date) AS shipping_date,
        MIN(due_date) AS due_date,
        COUNT(DISTINCT order_date) AS order_date_versions,
        COUNT(DISTINCT shipping_date) AS shipping_date_versions,
        COUNT(DISTINCT due_date) AS due_date_versions
    FROM stg_fact_sales
    GROUP BY order_number
)
SELECT
    COUNT(*) AS total_orders,
    COUNT(CASE
        WHEN order_date IS NOT NULL AND shipping_date IS NOT NULL THEN 1
    END) AS orders_with_valid_shipping_dates,
    ROUND(AVG(
        CASE
            WHEN order_date IS NOT NULL AND shipping_date IS NOT NULL
            THEN DATEDIFF(shipping_date, order_date)
        END
    ), 2) AS average_days_to_ship,
    COUNT(CASE
        WHEN shipping_date IS NOT NULL AND due_date IS NOT NULL THEN 1
    END) AS shipments_with_due_date,
    SUM(CASE
        WHEN shipping_date IS NOT NULL AND due_date IS NOT NULL
             AND shipping_date <= due_date THEN 1
        ELSE 0
    END) AS on_time_shipments,
    ROUND(
        SUM(CASE
            WHEN shipping_date IS NOT NULL AND due_date IS NOT NULL
                 AND shipping_date <= due_date THEN 1
            ELSE 0
        END)
        / NULLIF(COUNT(CASE
            WHEN shipping_date IS NOT NULL AND due_date IS NOT NULL THEN 1
        END), 0) * 100,
        2
    ) AS on_time_shipment_pct
FROM order_level;

-- Check whether the date fields are consistent across lines of the same order.
-- Expected result: no rows if each order has one order/shipping/due date.
SELECT
    order_number,
    COUNT(DISTINCT order_date) AS order_date_versions,
    COUNT(DISTINCT shipping_date) AS shipping_date_versions,
    COUNT(DISTINCT due_date) AS due_date_versions
FROM stg_fact_sales
GROUP BY order_number
HAVING COUNT(DISTINCT order_date) > 1
    OR COUNT(DISTINCT shipping_date) > 1
    OR COUNT(DISTINCT due_date) > 1;


-- ============================================================================
-- 18. ESTIMATED PROFITABILITY ANALYSIS
-- Cost = 0 products are excluded until their cost meaning is verified.
-- The output is an estimate, not audited accounting gross profit.
-- ============================================================================

SELECT
    p.category,
    SUM(s.sales_amount) AS sales_for_products_with_positive_cost,
    SUM(s.quantity * p.cost) AS estimated_cost_of_goods_sold,
    SUM(s.sales_amount - (s.quantity * p.cost)) AS estimated_gross_profit,
    ROUND(
        SUM(s.sales_amount - (s.quantity * p.cost))
        / NULLIF(SUM(s.sales_amount), 0) * 100,
        2
    ) AS estimated_gross_margin_pct
FROM stg_fact_sales s
JOIN stg_dim_products p
    ON s.product_key = p.product_key
WHERE p.cost > 0
GROUP BY p.category
ORDER BY estimated_gross_profit DESC;

-- Show how many products are excluded from the positive-cost estimate.
SELECT
    COUNT(*) AS zero_cost_products,
    GROUP_CONCAT(product_name ORDER BY product_name SEPARATOR ', ')
        AS products_to_review
FROM stg_dim_products
WHERE cost = 0;


-- ============================================================================
-- 19. FIRST-PURCHASE COHORT / RETENTION ANALYSIS
-- IMPORTANT: cohort = month of first recorded purchase, not create_date.
-- create_date is not assumed to represent customer signup in this dataset.
-- Month 0 = first-purchase month; Month 1 = following calendar month, etc.
-- Customers with no dated purchase cannot be assigned to a dated cohort.
-- ============================================================================

WITH first_purchase AS (
    SELECT
        customer_key,
        CAST(DATE_FORMAT(MIN(order_date), '%Y-%m-01') AS DATE) AS cohort_month
    FROM stg_fact_sales
    WHERE order_date IS NOT NULL AND TRIM(order_date) <> ''
    GROUP BY customer_key
), activity_by_customer_month AS (
    SELECT
        customer_key,
        CAST(DATE_FORMAT(order_date, '%Y-%m-01') AS DATE) AS activity_month,
        COUNT(DISTINCT order_number) AS orders_in_month
    FROM stg_fact_sales
    WHERE order_date IS NOT NULL AND TRIM(order_date) <> ''
    GROUP BY customer_key, CAST(DATE_FORMAT(order_date, '%Y-%m-01') AS DATE)
), cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(*) AS cohort_customers
    FROM first_purchase
    GROUP BY cohort_month
), cohort_activity AS (
    SELECT
        fp.cohort_month,
        a.activity_month,
        TIMESTAMPDIFF(MONTH, fp.cohort_month, a.activity_month) AS month_number,
        COUNT(DISTINCT a.customer_key) AS active_customers,
        SUM(a.orders_in_month) AS total_orders
    FROM first_purchase fp
    JOIN activity_by_customer_month a
        ON fp.customer_key = a.customer_key
    GROUP BY
        fp.cohort_month,
        a.activity_month,
        TIMESTAMPDIFF(MONTH, fp.cohort_month, a.activity_month)
)
SELECT
    ca.cohort_month,
    ca.activity_month,
    ca.month_number,
    cs.cohort_customers,
    ca.active_customers,
    ca.total_orders,
    ROUND(ca.active_customers / NULLIF(cs.cohort_customers, 0) * 100, 2)
        AS retention_pct
FROM cohort_activity ca
JOIN cohort_sizes cs
    ON ca.cohort_month = cs.cohort_month
ORDER BY ca.cohort_month, ca.month_number;


-- ============================================================================
-- 20. FINAL REPORT VALIDATION
-- Confirm one row per customer and one row per product in the reporting views.
-- ============================================================================

SELECT
    (SELECT COUNT(*) FROM stg_dim_customers) AS staging_customer_count,
    (SELECT COUNT(*) FROM report_customers) AS customer_report_count,
    (SELECT COUNT(*) FROM stg_dim_products) AS staging_product_count,
    (SELECT COUNT(*) FROM report_products) AS product_report_count;

-- Duplicate-grain check: expected result is no rows.
SELECT customer_key, COUNT(*) AS row_count
FROM report_customers
GROUP BY customer_key
HAVING COUNT(*) > 1;

SELECT product_key, COUNT(*) AS row_count
FROM report_products
GROUP BY product_key
HAVING COUNT(*) > 1;

/*
================================================================================
END OF PROJECT
================================================================================

This script covers data exploration, data quality checks, sales analysis,
customer analysis, product analysis, and reporting views.

The original source tables remain unchanged. All data cleaning and
transformations are performed on staging tables.

================================================================================
*/
