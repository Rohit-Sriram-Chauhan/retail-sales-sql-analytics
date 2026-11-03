# Data Dictionary

## `dim_customers` — 18,484 rows

One row per customer.

| Column | Description |
|---|---|
| `customer_key` | Warehouse customer key used to join to `fact_sales` |
| `customer_id` | Customer identifier from the source system |
| `customer_number` | Customer business/reference number |
| `first_name`, `last_name` | Customer name fields |
| `country` | Customer country |
| `marital_status` | Marital status attribute |
| `gender` | Gender attribute |
| `birthdate` | Customer birth date; missing values remain unknown |
| `create_date` | Source customer record creation date; not assumed to be signup date |

## `dim_products` — 295 rows

One row per product.

| Column | Description |
|---|---|
| `product_key` | Warehouse product key used to join to `fact_sales` |
| `product_id` | Product identifier from the source system |
| `product_number` | Product business/reference number |
| `product_name` | Product name |
| `category_id` | Source category identifier |
| `category`, `subcategory` | Product classification attributes |
| `maintenance` | Product maintenance attribute |
| `cost` | Product-master cost; historical applicability is not verified |
| `product_line` | Product line |
| `start_date` | Product start date |

## `fact_sales` — 60,398 rows

One row per product line within a sales order. An order can appear on multiple rows.

| Column | Description |
|---|---|
| `order_number` | Sales order identifier |
| `product_key` | Product key; joins to `dim_products.product_key` |
| `customer_key` | Customer key; joins to `dim_customers.customer_key` |
| `order_date` | Order date; 19 rows are missing this value |
| `shipping_date` | Shipment date |
| `due_date` | Due date |
| `sales_amount` | Sales amount for this sales line |
| `quantity` | Units in this sales line |
| `price` | Unit selling price; supplied data validates `sales_amount = price * quantity` |
