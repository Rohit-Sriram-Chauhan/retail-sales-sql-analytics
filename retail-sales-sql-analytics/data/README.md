# Dataset files

The `source/` folder contains the three CSV extracts used by this project:

- `dim_customers.csv`
- `dim_products.csv`
- `fact_sales.csv`

Import them into the `DataWarehouseAnalytics` MySQL schema using the table names above. The SQL script creates separate `stg_` copies and does not modify the imported source tables.

**Before publishing these CSVs publicly:** verify the original dataset source, redistribution licence, and whether customer names and birthdates are synthetic or authorised for public release. The supplied files do not include licence metadata.
