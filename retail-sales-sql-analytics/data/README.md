# Dataset Files

This folder contains the three CSV files used in the Retail Sales Data Analysis project.

### Files

- `dim_customers.csv` – Customer information
- `dim_products.csv` – Product details
- `fact_sales.csv` – Sales transaction records

### How to Use

1. Import the CSV files into your MySQL database.
2. Create a database named `DataWarehouseAnalytics`.
3. Import the files using the table names listed above.
4. Run the SQL script located in the `sql/` folder.

The SQL script creates separate staging tables for data cleaning and analysis. The original imported tables remain unchanged.

### Dataset Source

The original dataset is included in this repository and shared for educational and portfolio purposes.
