-- Commit and push all changes to main before executing.
-- Run when no pipeline is executing.

USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE DATABASE BTC_TRADING;
USE SCHEMA ORCHESTRATION;

-- 1. Suspend the roots before updating their dependencies.
ALTER TASK IF EXISTS BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_DELTA SUSPEND;
ALTER TASK IF EXISTS BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_FULL SUSPEND;


-- 2. Fetch the latest committed code.
ALTER GIT REPOSITORY BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO FETCH;

-- 3. Deploy dbt definitions.
ALTER DBT PROJECT BTC_TRADING.ORCHESTRATION.BINANCE
    DEPLOY FROM '@BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main';

-- 4. Update the staged Bronze loader.
COPY FILES
    INTO @BTC_TRADING.ORCHESTRATION.ETL_SCRIPTS/
    FROM @BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/etl/
    FILES = ('bronze_btcusdt_trades_raw.sql')
    DETAILED_OUTPUT = TRUE;

-- 5. Deploy quality procedures before deploying task graphs.
-- Retained because recovery tasks may use its DATE-based procedures.
EXECUTE IMMEDIATE FROM @BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/quality/dq_landing_scope.sql;
EXECUTE IMMEDIATE FROM @BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/quality/dq_after_summary.sql;


-- dq_landing_delta.sql and dq_landing_full.sql are executed
-- by the pipeline root tasks, not by this deployment script.

-- 6. Redeploy the DELTA and FULL task graphs.
-- These files resume child tasks and leave roots suspended
-- for manual execution.
EXECUTE IMMEDIATE FROM @BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/orchestration/delta.sql;
EXECUTE IMMEDIATE FROM @BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/orchestration/full.sql;

-- 7. Add the backfill/recovery deployment file here once identified.

-- 8. Inspect deployed tasks.
SHOW TASKS IN SCHEMA BTC_TRADING.ORCHESTRATION;