# Retail Sales Analysis using MySQL

**Author:** Rohit Chauhan

## About the project

This project uses a retail sales dataset to explore business performance with MySQL. I worked with customer, product and sales data to check data quality, calculate key metrics, analyse trends and customer behaviour, and prepare reporting views that can be used in a BI dashboard.

## Tools used

- MySQL 8.0+
- MySQL Workbench
- SQL: joins, aggregations, CTEs, subqueries, window functions, CASE statements and views

## Dataset

The project uses three CSV files:

| File / table | Rows | Description |
|---|---:|---|
| `dim_customers` | 18,484 | Customer details such as name, country, gender and birthdate |
| `dim_products` | 295 | Product details such as name, category, subcategory and cost |
| `fact_sales` | 60,398 | Sales transaction lines with order, customer, product, date, quantity and sales amount |

`fact_sales` contains one row per product line in an order. An order can have more than one row, so `COUNT(DISTINCT order_number)` is used when counting orders.

The available order dates range from **29 December 2010 to 28 January 2014**. There are 19 rows with a missing order date.

## What I analysed

- Explored the tables, columns, date ranges and key business metrics.
- Checked missing values, duplicate order/product lines, sales calculations and table relationships.
- Created cleaned staging tables while keeping the imported source tables unchanged.
- Analysed sales by month, year, country and product category.
- Ranked products and customers by sales.
- Calculated running totals, rolling measures and year-over-year comparisons.
- Segmented customers and products.
- Analysed repeat purchases, shipping performance and first-purchase cohorts.
- Estimated product profitability using the available product cost.
- Created customer and product reporting views for BI use.

## Repository structure

```text
retail-sales-sql-analytics/
|
|-- README.md
|-- .gitignore
|
|-- sql/
|   `-- SQL_Portfolio_Project_Updated.sql
|
|-- data/
|   |-- README.md
|   `-- source/
|       |-- dim_customers.csv
|       |-- dim_products.csv
|       `-- fact_sales.csv
|
`-- docs/
    `-- data_dictionary.md
```

## How to run the project

### 1. Requirements

- MySQL Server 8.0 or later
- MySQL Workbench (or another MySQL client)

### 2. Create the database

```sql
CREATE DATABASE IF NOT EXISTS DataWarehouseAnalytics;
USE DataWarehouseAnalytics;
```

### 3. Import the CSV files

Use **Table Data Import Wizard** in MySQL Workbench to import the three files from `data/source/` as:

- `dim_customers`
- `dim_products`
- `fact_sales`

Keep the table and column names consistent with the SQL script. The script expects these tables in the `DataWarehouseAnalytics` database.

### 4. Run the SQL script

Open `sql/SQL_Portfolio_Project_Updated.sql` in MySQL Workbench and execute it in section order. The script creates staging tables prefixed with `stg_` and the reporting views `report_customers` and `report_products`.

### 5. Check the reporting views

```sql
SELECT * FROM report_customers LIMIT 10;
SELECT * FROM report_products LIMIT 10;
```

## Notes and assumptions

- The original imported tables are not modified. Data cleaning is performed on staging copies.
- Missing `order_date` values are not guessed or filled in. They are excluded from analyses that require a valid date, but their sales and quantities can still be included in non-date-based analysis.
- `create_date` is not treated as the customer's signup date. Cohort analysis uses each customer's first recorded purchase date instead.
- Product profitability is an estimate because the dataset provides product-master cost, not verified historical cost for each sale. Products with zero cost need review.
- The dataset does not specify its currency, so the project does not assign a currency symbol to the figures.

## Data Sharing

The dataset used in this project is included in the `data/source/` folder.

It contains three CSV files:
- `dim_customers.csv`
- `dim_products.csv`
- `fact_sales.csv`

The datasets are shared for educational and portfolio purposes. The original CSV files are kept unchanged, while data cleaning and transformations are performed using SQL staging tables.

**Dataset Source:** 
* [Microsoft AdventureWorks Sample Databases Documentation](https://learn.microsoft.com/en-us/sql/samples/adventureworks-install-configure)

---

**Rohit Chauhan**  
SQL Portfolio Project | Retail Sales Analytics | MySQL
