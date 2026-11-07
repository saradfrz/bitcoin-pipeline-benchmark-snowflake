# Binance BTCUSDT trades on Snowflake

This directory contains the Snowflake side of the Binance D−1 trade pipeline. Its input is the set of daily BTCUSDT Parquet files already present in `@BTC_TRADING.BINANCE_BRONZE.LANDING_ZONE`. The pipeline reads those files into Bronze, types the trades in Silver, and rebuilds Gold indicators from Silver.

## Set up the database

Extract the setup bundle at the root of `di-pipe-eng`. The paths below are relative to `snowflake/`. Open the SQL files in the Snowflake workspace and run them in order. Choose a role with access to `SNOWFLAKE_LEARNING_WH`, read access to the existing stage, and permission to create any missing database, schemas and tables. The upstream process supplies the stage and its files before the first load.

| Order | File | Expected result |
|---|---|---|
| 1 | [Create namespaces](setup/01_create_namespaces.sql) | Selects the project warehouse and creates any missing namespaces in `BTC_TRADING`. Data lives in `BINANCE_BRONZE`, `BINANCE_SILVER` and `BINANCE_GOLD`. Pipeline definitions belong in `ORCHESTRATION`. |
| 2 | [Create trade tables](setup/02_create_trade_tables.sql) | Creates the raw Bronze trades table and typed Silver trades table if absent. Both carry `source_file` and `ingested_at`. |
| 3 | [Verify setup](setup/03_verify_setup.sql) | Lists matching Parquet files, describes both tables and lists the schemas. Confirm the expected source dates and compare existing column types with step 2 before loading. |

An empty file listing means there is no visible input matching the loader pattern. Resolve the upstream handoff or stage access before starting a full run. These setup scripts can be rerun. Existing table definitions require a separate migration if they differ from step 2.

## First Bronze load

Run `historical_data/load_btcusdt_trades_bronze.sql` once after setup. It uses the project warehouse and copies matching Parquet files. Source fields `qty`, `quote_qty` and `time` map to `quantity`, `quote_quantity` and `trade_time_us`. The loader records the staged filename and scan start time on each row. Compare per-file counts with the expected input, then run `sql/02_test_bronze_.sql`.

```sql
SELECT source_file, COUNT(*) AS trade_rows
FROM BTC_TRADING.BINANCE_BRONZE.BTCUSDT_TRADES_BRONZE
GROUP BY source_file
ORDER BY source_file;
```

## Pipeline behavior to version

Both entry points are manual. Run only one mode at a time. Each step depends on successful completion of its predecessor.

| Step | BINANCE_BITCOIN_DELTA | BINANCE_BITCOIN_FULL |
|---|---|---|
| Reset | Keep existing tables populated. | First truncate `BINANCE_BRONZE.BTCUSDT_TRADES_BRONZE`, then truncate the pipeline-owned Silver and Gold tables. |
| Bronze | Copy eligible, previously unloaded Parquet files. | Reload every matching staged Parquet file into the empty Bronze table. Reconcile the file list before proceeding. |
| Silver | Load Bronze files whose `source_file` is absent from Silver, then refresh dependent Silver results. | Rebuild all Silver results from the reloaded Bronze data. |
| Gold | Rebuild all Gold models and run the indicator tests. | Rebuild all Gold models and run the same tests. |

Bronze truncation clears the target table’s file-load metadata and allows the same files to be copied again. The stage is read-only throughout both modes. Silver’s incremental rule assumes a stable, non-null filename and a complete file per Bronze load. A correction uploaded under a previously processed name requires a deliberate replay. [Snowflake TRUNCATE TABLE](https://docs.snowflake.com/en/sql-reference/sql/truncate-table)

## Existing checks and next implementation

- **Silver** — `sql/03_test_silver__btcusdt_trades.sql` and `sql/04_test_silver__btcusdt_daily_trade_summary.sql` correspond to the trades and daily summary. Run each after its target is populated. The trades contract is in `data_contracts/binance_silver__btcusdt_trades.dbquery.ipynb`.
- **Gold** — `sql/testes_gold/` lists ten numbered checks covering 50-day SMA, 200-day SMA, cumulative volume delta and VWAP. Use `../docs/gold_formula_indicadores.md` as the formula reference. Confirm the checks contain executable assertions before using them to gate publication.
- **Versioned ETL** — the supplied Git tree shows an empty `etl/`. Reconcile the workspace copies of `bronze.sql` and `truncate_bronze.sql` with the historical loader, then version the Silver and Gold processing steps. Keep one canonical implementation of each transformation.
- **dbt** — planned under `dbt/`. Declare Bronze trades as a source, preserve filename-based incremental loading in Silver, and materialize Gold as fully rebuilt tables. Port the existing checks to dbt tests and keep credentials outside Git.
- **Orchestration** — planned under `orchestration/`. Version both manual pipeline definitions and the deployment steps. Once dbt owns a transformation, the pipeline invokes the corresponding dbt build. The setup bundle provisions namespaces and base tables only.

The existing `sql/01_criar_stage_e_camada_bronze.sql` and files under `sql/snowflake_limitations/` remain repository references. This setup starts from the populated stage, so neither stage provisioning nor outbound HTTPS configuration is a prerequisite to rerun here.
