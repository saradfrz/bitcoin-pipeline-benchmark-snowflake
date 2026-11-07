-- Suggested location: snowflake/maintenance/demo_delta_backfill.sql
-- Run numbered sections separately, in order, in the SAME worksheet/session.
-- Requires the uploaded project's definitions to be deployed in Snowflake.
-- Run when FULL/DELTA are idle; do not start concurrent writers during the demo.
-- This demo deletes ONE summary row. Silver trades remain the recovery source.
-- The ordinary delta graph also loads new files, builds Gold and prunes >366 days.
-- Do not use Run All: EXECUTE TASK returns before the graph has finished.

-- 1. Configuration and baseline. Change only the chosen date as needed.
USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE DATABASE BTC_TRADING;
USE SCHEMA ORCHESTRATION;
SET demo_day = '2026-10-28';
SET demo_payload = (SELECT TO_JSON(OBJECT_CONSTRUCT(
    'lo', $demo_day, 'summary_hi', $demo_day)));

-- Check task deployment: the root can remain suspended; children must be started.
SHOW TASKS IN SCHEMA BTC_TRADING.ORCHESTRATION;

EXECUTE IMMEDIATE $$
DECLARE
    d DATE DEFAULT TO_DATE($demo_day);
    scope OBJECT;
    lo DATE;
    hi DATE DEFAULT DATEADD(day, -1, CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP())::DATE);
    payload VARCHAR;
    rows_found INTEGER;
    actual_trades NUMBER;
    expected_trades NUMBER;
    invalid_demo EXCEPTION (-20001, 'Choose one existing summary day within landing coverage and retention, with matching Silver trades.');
BEGIN
    CALL BTC_TRADING.ORCHESTRATION.DQ_LANDING_SCOPE() INTO :scope;
    lo := GET(scope, 'lo')::DATE;
    IF (d < lo OR d > hi OR d > GET(scope, 'hi')::DATE
        OR d < DATEADD(day, -366, CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP())::DATE)) THEN
        RAISE invalid_demo;
    END IF;
    -- Establish that the real delta DQ scope passes BEFORE introducing a gap.
    payload := TO_JSON(OBJECT_CONSTRUCT('lo', TO_CHAR(lo, 'YYYY-MM-DD'),
                                      'summary_hi', TO_CHAR(hi, 'YYYY-MM-DD')));
    CALL BTC_TRADING.ORCHESTRATION.DQ_AFTER_SUMMARY(:payload);
    SELECT COUNT(*), MAX(quantidade_trades) INTO :rows_found, :expected_trades
    FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
    WHERE symbol = 'BTCUSDT' AND data = :d;
    SELECT COUNT(*) INTO :actual_trades
    FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_TRADES
    WHERE symbol = 'BTCUSDT'
      AND trade_timestamp_utc >= :d::TIMESTAMP_NTZ
      AND trade_timestamp_utc < DATEADD(day, 1, :d)::TIMESTAMP_NTZ;
    IF (rows_found <> 1 OR actual_trades = 0 OR actual_trades <> expected_trades) THEN
        RAISE invalid_demo;
    END IF;
    RETURN 'READY: baseline DQ passes and Silver trades can rebuild the chosen day.';
END;
$$;
-- STOP if preflight fails. Resolve coverage/deployment before continuing.

-- 2. Save the row, then introduce the missing-day error.
-- Deliberately no OR REPLACE: rerunning this section cannot overwrite the backup.
CREATE TEMPORARY TABLE DEMO_DELTA_SUMMARY_BACKUP AS
SELECT * FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
WHERE symbol = 'BTCUSDT' AND data = TO_DATE($demo_day);
SELECT * FROM DEMO_DELTA_SUMMARY_BACKUP;

EXECUTE IMMEDIATE $$
DECLARE
    n INTEGER;
    invalid_backup EXCEPTION (-20002, 'Expected exactly one backup row matching demo_day.');
BEGIN
    SELECT COUNT(*) INTO :n FROM DEMO_DELTA_SUMMARY_BACKUP
    WHERE symbol = 'BTCUSDT' AND data = TO_DATE($demo_day);
    IF (n <> 1) THEN RAISE invalid_backup; END IF;
    DELETE FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
    WHERE symbol = 'BTCUSDT' AND data = TO_DATE($demo_day);
    RETURN 'One summary date removed; Silver trades preserved.';
END;
$$;
SELECT COUNT(*) AS summary_rows_expected_0
FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
WHERE symbol = 'BTCUSDT' AND data = TO_DATE($demo_day);

-- 3. Show that DQ detects the missing day BEFORE recovery.
-- Catch ONLY the known BAD_SUMMARY code so the intended failure is readable.
EXECUTE IMMEDIATE $$
DECLARE
    payload VARCHAR DEFAULT $demo_payload;
    unexpected_pass EXCEPTION (-20003, 'Demo failed: DQ unexpectedly passed.');
BEGIN
    CALL BTC_TRADING.ORCHESTRATION.DQ_AFTER_SUMMARY(:payload);
    RAISE unexpected_pass;
EXCEPTION
    WHEN OTHER THEN
        IF (SQLCODE = -20105) THEN
            RETURN 'EXPECTED FAILURE: BAD_SUMMARY detected the missing date.';
        ELSE
            RAISE;
        END IF;
END;
$$;

-- 4. Trigger the existing normal delta graph. Run ONCE.
SET demo_started_at = CURRENT_TIMESTAMP();
EXECUTE TASK BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_DELTA;

-- 5. Re-run this query until the graph completes.
-- Use GRAPH_RUN_GROUP_ID to distinguish runs; all TEN tasks must succeed,
-- including DELTA_PRUNE_366_DAYS. Root success alone is insufficient.
SELECT graph_run_group_id, name, state, scheduled_time, completed_time,
       error_code, error_message
FROM TABLE(BTC_TRADING.INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => $demo_started_at,
    RESULT_LIMIT => 10000))
WHERE database_name = 'BTC_TRADING' AND schema_name = 'ORCHESTRATION'
  AND (name = 'BINANCE_BITCOIN_DELTA' OR name LIKE 'DELTA_%')
ORDER BY scheduled_time, name;

-- 6. After successful completion, prove that backfill restored the row.
SELECT data, symbol, quantidade_trades, preco_fechamento, volume_total_btc,
       volume_total_usdt, delta_btc, vwap_diario
FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
WHERE symbol = 'BTCUSDT' AND data = TO_DATE($demo_day);
-- Expected: exactly one row.
CALL BTC_TRADING.ORCHESTRATION.DQ_AFTER_SUMMARY($demo_payload);
-- Expected: PASS.

-- Full-row comparison in both directions; both counts should be ZERO.
-- Floating-point aggregation, if column types differ from the project, may need
-- tolerance-based comparison. This project's Silver source uses DECIMAL values.
SELECT 'original_minus_restored' AS comparison, COUNT(*) AS differences
FROM (
    SELECT * FROM DEMO_DELTA_SUMMARY_BACKUP
    MINUS
    SELECT * FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
    WHERE symbol = 'BTCUSDT' AND data = TO_DATE($demo_day)
)
UNION ALL
SELECT 'restored_minus_original', COUNT(*)
FROM (
    SELECT * FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
    WHERE symbol = 'BTCUSDT' AND data = TO_DATE($demo_day)
    MINUS
    SELECT * FROM DEMO_DELTA_SUMMARY_BACKUP
);

-- Gold rows were not deleted. If restored inputs are identical, the Gold models
-- can correctly make no changes. This demonstrates SUMMARY backfill specifically.

-- 7. Optional fallback if delta fails: run ONLY after all writers have stopped.
-- This restores the original summary row without claiming pipeline recovery.
-- INSERT INTO BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
-- SELECT b.* FROM DEMO_DELTA_SUMMARY_BACKUP b
-- WHERE NOT EXISTS (
--     SELECT 1 FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY s
--     WHERE s.symbol = b.symbol AND s.data = b.data
-- );

-- 8. Cleanup only after successful validation (or verified fallback restoration).
-- DROP TABLE DEMO_DELTA_SUMMARY_BACKUP;
