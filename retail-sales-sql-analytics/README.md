# Retail Sales Data Warehouse & Analytics (MySQL)

An end-to-end SQL portfolio project using a retail sales data warehouse. The project explores the data, audits data quality, creates cleaned staging copies, analyses sales and customer behaviour, and builds reusable reporting views for business intelligence.

> **Project status:** SQL analysis and reporting views are included. A Power BI dashboard can be added as a follow-up deliverable.

## 1. Project objectives

The goal is to answer practical retail/business questions using MySQL, including:

- What are the core sales, order, quantity, customer, and product KPIs?
- How do sales and order volumes change over time?
- Which products and categories contribute the most revenue?
- Which customers generate the most revenue, and how often do customers purchase again?
- Which products have never sold?
- How long does it take orders to ship, and what share ships by the due date?
- Which products/categories have the highest estimated gross profit and margin?
- How do customer first-purchase cohorts behave over subsequent months?

## 2. Tools and SQL concepts

- **Database:** MySQL 8.0+
- **SQL environment:** MySQL Workbench or another MySQL 8.0+ client
- **Core SQL:** `SELECT`, `WHERE`, `GROUP BY`, `HAVING`, `ORDER BY`, `CASE`
- **Joins:** `INNER JOIN`, `LEFT JOIN`
- **Aggregations:** `SUM`, `AVG`, `COUNT`, `MIN`, `MAX`
- **Advanced SQL:** CTEs, window functions (`SUM() OVER`, `AVG() OVER`, `LAG`, `RANK`), conditional aggregation
- **Data preparation:** staging tables, NULL handling, text standardisation, data-quality checks
- **Date analysis:** year/month analysis, date differences, calendar month spine, rolling windows
- **Reporting:** customer and product views

## 3. Dataset overview

The repository contains three CSV extracts. They are named after the source tables and are imported into MySQL as `dim_customers`, `dim_products`, and `fact_sales`.

| File / table | Rows | Purpose |
|---|---:|---|
| `dim_customers` | 18,484 | Customer attributes such as name, country, gender, birthdate, and create date |
| `dim_products` | 295 | Product attributes such as product name, category, subcategory, cost, and product line |
| `fact_sales` | 60,398 | Sales transaction lines containing order, customer, product, date, sales amount, quantity, and price |

### Table grain and relationships

`fact_sales` is at **sales-line grain**: one row represents a product line within an order, not necessarily one complete order. An order can therefore appear in multiple rows.

```text
 dim_customers                 dim_products
 (one row per customer)       (one row per product)
          |                           |
          | 1                         | 1
          |                           |
          +-------- fact_sales -------+
                   (many sales lines)
```

The tables are joined using:

- `dim_customers.customer_key = fact_sales.customer_key`
- `dim_products.product_key = fact_sales.product_key`

**Important counting rule:** use `COUNT(DISTINCT order_number)` to count orders. `COUNT(*)` on `fact_sales` counts sales lines.

### Date coverage

- Earliest non-NULL `order_date`: **2010-12-29**
- Latest non-NULL `order_date`: **2014-01-28**
- Rows with missing `order_date`: **19**

2010 and 2014 are partial calendar years. Do not compare their totals directly with complete years without restricting the comparison to equivalent periods.

## 4. Data-quality observations and assumptions

The supplied CSVs contain some incomplete attributes. The SQL script audits these and creates `stg_` staging copies for standardisation. The original imported source tables are not modified.

Observed issues in the supplied CSV extracts:

- 19 sales lines have a missing `order_date`.
- 337 customers have a missing country, 15 have a missing gender, and 17 have a missing birthdate.
- 7 products have missing category, subcategory, and maintenance values; 17 products have a missing product line.
- 2 products have a recorded cost of zero.
- 165 products in the product catalogue have no matching sales rows.

Validation checks in the script found:

- No `sales_amount` mismatches against `price * quantity` in the supplied data.
- No duplicate `(order_number, product_key)` sales-line combinations.
- No unmatched customer or product keys in `fact_sales`.

### Important analytical assumptions

1. **Missing order dates are not reconstructed.** The 19 affected rows remain in the data. They are excluded only from analyses that require a valid order date; their sales and quantity remain available to non-date-based analyses.
2. **Missing descriptive attributes are standardised in staging.** Blank, `n/a`, and NULL customer attributes are labelled `Unknown`; missing product categories/subcategories are labelled `Unassigned`.
3. **`create_date` is not treated as customer signup date.** In the supplied data, `create_date` falls in 2025–2026 while the sales period is 2010–2014. The project therefore uses each customer's first recorded purchase for cohort analysis. This is a first-purchase cohort, not a signup cohort.
4. **Product profitability is estimated.** `dim_products.cost` is a product-master cost, not verified historical unit cost for each transaction. Products with zero cost are excluded from the estimated-margin calculation and flagged for review. Do not present estimated gross profit as audited accounting profit.
5. **Currency is not specified in the supplied CSVs.** Revenue and cost values are shown in the dataset's stored units. Confirm the source currency before adding a currency symbol to reports or dashboards.
6. **Shipping analysis measures order-to-shipping lead time and shipping against due date.** The data does not contain a final delivered timestamp, so this project does not claim to measure actual delivery time to the customer.

## 5. Project structure

```text
retail-sales-sql-analytics/
├── README.md
├── sql/
│   └── SQL_Portfolio_Project_Updated.sql
├── data/
│   ├── README.md
│   └── source/
│       ├── dim_customers.csv
│       ├── dim_products.csv
│       └── fact_sales.csv
└── docs/
    └── data_dictionary.md
```

## 6. How to run the project

### Prerequisites

- MySQL Server 8.0 or later
- MySQL Workbench (recommended for beginners)
- The three CSV files in `data/source/`

### Step 1 — Create the database

Run this in MySQL Workbench:

```sql
CREATE DATABASE IF NOT EXISTS DataWarehouseAnalytics;
USE DataWarehouseAnalytics;
```

### Step 2 — Import the three CSV files

In MySQL Workbench:

1. In the **Schemas** panel, refresh and expand `DataWarehouseAnalytics`.
2. Right-click the schema and choose **Table Data Import Wizard**.
3. Select `data/source/dim_customers.csv` and import it as a new table named `dim_customers`.
4. Repeat for `dim_products.csv` (table name `dim_products`) and `fact_sales.csv` (table name `fact_sales`).
5. Confirm that the column names match the CSV headers and that date and numeric columns have appropriate MySQL data types.

Suggested data types:

| Table | Columns | Suggested type |
|---|---|---|
| `dim_customers` | `customer_key`, `customer_id` | `INT` |
| `dim_customers` | `customer_number`, `first_name`, `last_name`, `country`, `marital_status`, `gender` | `VARCHAR` |
| `dim_customers` | `birthdate`, `create_date` | `DATE` |
| `dim_products` | `product_key`, `product_id` | `INT` |
| `dim_products` | `product_number`, `product_name`, `category_id`, `category`, `subcategory`, `maintenance`, `product_line` | `VARCHAR` |
| `dim_products` | `cost` | `DECIMAL(12,2)` |
| `dim_products` | `start_date` | `DATE` |
| `fact_sales` | `order_number` | `VARCHAR` |
| `fact_sales` | `product_key`, `customer_key`, `quantity` | `INT` |
| `fact_sales` | `order_date`, `shipping_date`, `due_date` | `DATE` |
| `fact_sales` | `sales_amount`, `price` | `DECIMAL(12,2)` |

Do not import the CSV files into tables named `gold.dim_customers` etc. The SQL script expects the three unqualified table names above inside the `DataWarehouseAnalytics` schema.

### Step 3 — Verify the imported tables

```sql
USE DataWarehouseAnalytics;
SHOW TABLES;

SELECT COUNT(*) FROM dim_customers;
SELECT COUNT(*) FROM dim_products;
SELECT COUNT(*) FROM fact_sales;
```

Expected row counts: 18,484 customers; 295 products; 60,398 sales lines.

### Step 4 — Run the SQL project

1. Open `sql/SQL_Portfolio_Project_Updated.sql` in MySQL Workbench.
2. Confirm the active schema is `DataWarehouseAnalytics`.
3. Execute the script from top to bottom, in section order.
4. Review the outputs from each analysis section and the final validation section.

The script drops and recreates only its own `stg_` staging tables and `report_customers` / `report_products` views when rerun. It does **not** update or drop the three imported source tables.

### Step 5 — Query the reporting views

```sql
SELECT * FROM report_customers LIMIT 10;
SELECT * FROM report_products LIMIT 10;
```

## 7. Analysis included

The SQL script is organised into 20 sections:

1. Database exploration
2. Raw data quality audit
3. Create clean staging copies
4. Dimensions exploration
5. Date exploration
6. Measures exploration and business KPIs
7. Magnitude analysis
8. Ranking analysis
9. Changes over time analysis
10. Cumulative and rolling analysis
11. Product performance analysis
12. Part-to-whole analysis
13. Data segmentation
14. Customer report view
15. Product report view
16. Customer repeat-purchase analysis
17. Shipping performance analysis
18. Estimated profitability analysis
19. First-purchase cohort / retention analysis
20. Final report validation

## 8. Potential next steps

- Build a Power BI dashboard using `report_customers`, `report_products`, and additional analytical queries.
- Add dashboard screenshots to a `dashboard/screenshots/` directory.
- Document the most important findings and business recommendations in `docs/business_findings.md`.
- Add the original dataset source URL and its licence/redistribution terms once verified.

## 9. Dataset attribution and sharing note

The supplied CSV files do not include source URL or licence metadata. Before making this repository public, verify the original dataset's source and redistribution terms, then add the attribution here. The customer file contains names and dates of birth; confirm that the records are synthetic or otherwise authorised for public release. If you cannot verify that public sharing is permitted, keep the repository private or omit the CSVs and provide the authorised source link instead.

---

**Author:** [Your Name]  
**Project type:** Data Analytics / SQL Portfolio  
**Database:** MySQL 8.0+
