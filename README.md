# Binance BTCUSDT trades on Snowflake

This directory contains the Snowflake side of the Binance D−1 trade pipeline. Its input is the set of daily BTCUSDT Parquet files already present in `@BTC_TRADING.BINANCE_BRONZE.LANDING_ZONE`. The pipeline reads those files into Bronze, types the trades in Silver, and rebuilds Gold indicators from Silver.

## Set up the project

### Setup the Workspace
1. Create Workspace > Git Workspace
x. (add commands to fork the original project and add into snowflake)

### Setup the Catalog
x. Execute `setup_init/01_create_namespaces.sql`
x. Execute `setup_init/02_create_bronze_layer.sql`
x. Execute `setup_init/03_create_silver_layer.sql`
x. Execute `setup_init/04_create_gold_layer.sql`
x. Edit `setup_init/05_create_bronze_layer.sql`. Put your repo in ORIGIN (L.8). Execute it.

### Get the data
x. Clone the project in your machine.
x. Edit local\download_files_locally.py. Choose the date interval (start_date="01/01/2026" and end_date="xx/xx/xxxx") and the ouput folder (L.7). Run.
x. Go to Catalog > BTC_TRADING > BINANCE_BRONZE > LANDING_ZONE > Upload Files > Browse > output_folder. Wait until everything is loaded


