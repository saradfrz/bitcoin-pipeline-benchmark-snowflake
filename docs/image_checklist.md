# Image inventory

All eight supplied PNGs are included in the page using their original filenames under the repository-root `img/` directory. No image is pending for this delivery.

| Filename | What it shows |
|---|---|
| `dbt-project.png` | Project BTC_TRADING.ORCHESTRATION.BINANCE uses dbt 1.9.4, the main Git branch and the Snowflake target. |
| `snowflake-data-lineage.png` | The dbt DAG connects the Bronze source to Silver trades, the daily summary and four Gold models. |
| `snowflake-full-pipeline.png` | The supplied task history shows all ten FULL tasks succeeded, including reset, Bronze, Silver, summary DQ and the four Gold branches. |
| `snowflake-delta-pipeline.png` | All ten DELTA tasks succeeded in the supplied run, ending with DELTA_PRUNE_366_DAYS. |
| `snowflake-quality-failure.png` | A direct call to DQ_AFTER_SUMMARY raises BAD_SUMMARY after the controlled removal of a summary row. This is a procedure test, not a failed Task graph. |
| `snowflake-backfill-recovered.png` | The worksheet shows ROLLBACK followed by the restored BTCUSDT row for 2026-11-08 with 1,132,641 trades. This capture demonstrates restoration after rollback; DELTA backfill is a separate workflow. |
| `demo-gold.png` | Query results show closing price, SMA50, SMA200, CVD and VWAP for ten dates through 2026-11-08. Values are rounded for display. |
| `snowflake-count-rows.png` | Bronze and Silver trades each contain 1,107,431,071 rows. The daily summary and each of the four Gold marts contain 312 rows. Counts do not establish value-by-value equality. |

The older requested names `snowflake-gold-preview.png` and `snowflake-data-coverage.png` correspond here to the supplied `demo-gold.png` and `snowflake-count-rows.png`. The latter shows row counts, not a complete date-coverage check. No separate cost/credit screenshot was supplied.
