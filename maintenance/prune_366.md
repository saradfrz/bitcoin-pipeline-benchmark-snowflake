# Retention: 366 days

`DELTA_PRUNE_366_DAYS` runs after all four Gold branches succeed in the Snowflake delta graph. The full graph and Databricks jobs are unchanged.

The cutoff is calculated once at task start: UTC today minus 366 days. Dates strictly before it are deleted; the cutoff day is retained. For a 2026-11-04 UTC run, the cutoff is 2025-11-03. With D-1 ingestion this retains 366 completed trading days.

Scope: daily `BTCUSDT-trades-YYYY-MM-DD.parquet` archives anywhere under `@BTC_TRADING.BINANCE_BRONZE.LANDING_ZONE`, Bronze trades (epoch microseconds), Silver trades (UTC timestamp), Silver daily summary and the four Gold marts (data). Rows are restricted to BTCUSDT. Unknown filenames and undatable rows are not guessed or deleted. No task history, code, checkpoint, other symbol, or auxiliary table is removed.

## Deploy

1. Commit `snowflake/orchestration/delta.sql` and `snowflake/maintenance/prune_366_days.sql` to main.
2. Wait for active full/delta runs to finish; do not overlap full, delta, or landing uploads during retention.
3. Run:

```sql
ALTER GIT REPOSITORY BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO FETCH;
EXECUTE IMMEDIATE FROM @BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/snowflake/orchestration/delta.sql;
EXECUTE TASK BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_DELTA;
```

The root remains manual; the new child is resumed with the other children. Existing init/redeploy scripts already execute delta.sql. The task owner needs DELETE on the seven tables and permission to LIST/REMOVE landing files (READ/WRITE for an internal stage).

## Failure and history behavior

Files are removed oldest first, before a transaction deletes the seven tables. Stage deletion cannot be rolled back. If file removal fails, no table deletes start. If table deletion fails, all table deletes roll back, but already removed files stay removed. Retry the task/run to finish cleanup. Keep all Gold children resumed; no finalizer is used, so a failed upstream build does not trigger pruning.

DQ runs before cleanup using the current landing scope. The next delta captures the remaining landing interval. Do not re-upload expired archives: cleanup does not prevent their ingestion before pruning.

Existing retained Gold values are left intact. Normal daily appends have enough retained history for SMA200, and incremental CVD uses its retained prior value. A full rebuild or corrections near the oldest retained day cannot recover deleted SMA lookback history; a full CVD rebuild starts from the surviving summary baseline. If exact historical rebuilds are required, archive the removed history separately first.

DELETE applies logical retention; Snowflake Time Travel/Fail-safe can retain deleted storage according to account/table settings. Stage removal is permanent. No live Snowflake execution was performed for this change.
