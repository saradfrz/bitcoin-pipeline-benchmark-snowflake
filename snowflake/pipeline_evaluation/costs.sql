USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE DATABASE BTC_TRADING;

-- ============================================================
-- 00. Observation window: execution dates, not trading dates
--     Start inclusive / end exclusive.
--     Use whole hours for warehouse metering.
-- ============================================================
SET cost_start = '2026-11-06 17:00:00 -03:00'::TIMESTAMP_TZ;
SET cost_end   = '2026-11-07 00:00:00 -03:00'::TIMESTAMP_TZ;

-- Current configuration: size, auto-suspend, auto-resume, etc.
SHOW WAREHOUSES LIKE 'SNOWFLAKE_LEARNING_WH';

SELECT
    CURRENT_ACCOUNT() AS account_name,
    CURRENT_REGION()  AS region,
    CURRENT_TIMESTAMP() AS collected_at;


-- ============================================================
-- 01. Current table inventory
--     Metadata counts avoid scanning and sorting raw trades.
--     Includes auxiliary tables in the orchestration schema.
-- ============================================================
SELECT
    table_schema,
    table_name,
    row_count AS total_rows,
    bytes AS table_bytes,
    ROUND(bytes / POWER(1024, 3), 6) AS table_gib,
    retention_time AS time_travel_days,
    is_transient
FROM BTC_TRADING.INFORMATION_SCHEMA.TABLES
WHERE table_type = 'BASE TABLE'
  AND table_schema IN (
      'BINANCE_BRONZE',
      'BINANCE_SILVER',
      'BINANCE_GOLD',
      'ORCHESTRATION'
  )
ORDER BY table_schema, table_name;


-- ============================================================
-- 02. Billable table storage snapshot
--     Keep dropped/recreated tables: retained data can cost money.
--     These values describe current storage, not historical
--     average storage during the observation window.
-- ============================================================
SELECT
    id AS table_id,
    table_schema,
    table_name,
    deleted AS is_dropped,
    active_bytes,
    time_travel_bytes,
    failsafe_bytes,
    retained_for_clone_bytes,
    ROUND(
        (
            COALESCE(active_bytes, 0)
          + COALESCE(time_travel_bytes, 0)
          + COALESCE(failsafe_bytes, 0)
          + COALESCE(retained_for_clone_bytes, 0)
        ) / POWER(1024, 4),
        9
    ) AS total_storage_tib
FROM SNOWFLAKE.ACCOUNT_USAGE.TABLE_STORAGE_METRICS
WHERE table_catalog = 'BTC_TRADING'
  AND table_schema IN (
      'BINANCE_BRONZE',
      'BINANCE_SILVER',
      'BINANCE_GOLD',
      'ORCHESTRATION'
  )
ORDER BY table_schema, table_name, table_id;


-- ============================================================
-- 03. Landing-zone file count and stored size
--     Execute these two statements consecutively.
-- ============================================================
LIST @BTC_TRADING.BINANCE_BRONZE.LANDING_ZONE;

SELECT
    COUNT(*) AS landing_file_count,
    COALESCE(SUM("size"), 0) AS landing_bytes,
    ROUND(
        COALESCE(SUM("size"), 0) / POWER(1024, 4),
        9
    ) AS landing_tib
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));


-- ============================================================
-- 04. Data coverage: small Silver summary table only
-- ============================================================
SELECT
    symbol,
    MIN(data) AS first_trading_date,
    MAX(data) AS last_trading_date,
    COUNT(*) AS summary_rows,
    COUNT(DISTINCT data) AS trading_days
FROM BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
GROUP BY symbol;


-- ============================================================
-- 05. Task runs and attributed compute
--     Includes nested SQL through ROOT_QUERY_ID.
--     Includes failed/cancelled tasks because they can cost money.
--     All tasks in BTC_TRADING.ORCHESTRATION are included.
-- ============================================================
WITH task_runs AS (
    SELECT
        name AS task_name,
        graph_run_group_id,
        attempt_number,
        query_id,
        state,
        scheduled_time,
        query_start_time,
        completed_time
    FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
    WHERE database_name = 'BTC_TRADING'
      AND schema_name = 'ORCHESTRATION'
      AND scheduled_time >= $cost_start
      AND scheduled_time <  $cost_end
),
attributed AS (
    SELECT
        COALESCE(root_query_id, query_id) AS task_query_id,
        COUNT(*) AS attributed_query_count,
        SUM(credits_attributed_compute) AS compute_credits,
        SUM(COALESCE(credits_used_query_acceleration, 0))
            AS acceleration_credits
    FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_ATTRIBUTION_HISTORY
    WHERE start_time >= $cost_start
      AND start_time <  $cost_end
    GROUP BY 1
)
SELECT
    t.graph_run_group_id,
    t.attempt_number,
    t.task_name,
    t.state,
    t.query_id,
    t.scheduled_time,
    t.query_start_time,
    t.completed_time,
    ROUND(
        DATEDIFF('millisecond', t.query_start_time, t.completed_time)
        / 1000.0,
        3
    ) AS elapsed_seconds,
    a.attributed_query_count,
    a.compute_credits,
    a.acceleration_credits,
    a.compute_credits + a.acceleration_credits
        AS attributed_execution_credits
FROM task_runs t
LEFT JOIN attributed a
    ON a.task_query_id = t.query_id
ORDER BY t.scheduled_time, t.task_name;


-- ============================================================
-- 06. Warehouse consumption by day
--     Includes ALL workloads on this warehouse and idle time.
--     Do not add this to section 05: compute overlaps.
-- ============================================================
SELECT
    TO_DATE(start_time) AS usage_date,
    warehouse_name,
    SUM(credits_used_compute) AS warehouse_compute_credits,
    SUM(credits_attributed_compute_queries) AS query_compute_credits,
    SUM(credits_used_compute)
        - SUM(credits_attributed_compute_queries) AS idle_compute_credits,
    SUM(credits_used_cloud_services) AS cloud_services_credits_unadjusted
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE warehouse_name = 'SNOWFLAKE_LEARNING_WH'
  AND start_time >= $cost_start
  AND start_time <  $cost_end
GROUP BY 1, 2
ORDER BY 1, 2;