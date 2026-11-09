USE WAREHOUSE SNOWFLAKE_LEARNING_WH;
USE DATABASE BTC_TRADING;
USE SCHEMA ORCHESTRATION;

-- 1. Create the repository and the stage for the Bronze loader.
CREATE GIT REPOSITORY IF NOT EXISTS BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO
    API_INTEGRATION = "Snowflake"
    ORIGIN = 'https://github.com/saradfrz/di-pipe-eng';

CREATE STAGE IF NOT EXISTS BTC_TRADING.ORCHESTRATION.ETL_SCRIPTS;

-- 2. Suspend existing roots when this deployment is rerun.
-- Suspending does not cancel an execution already in progress.
ALTER TASK IF EXISTS BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_DELTA SUSPEND;
ALTER TASK IF EXISTS BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_FULL SUSPEND;

-- 3. Fetch the latest committed files.
ALTER GIT REPOSITORY BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO FETCH;

-- 4. Create dbt on first deployment, then deploy the current files.
-- ALTER DEPLOY assumes a dbt project using the mutable live version.
CREATE DBT PROJECT IF NOT EXISTS BTC_TRADING.ORCHESTRATION.BINANCE
    FROM '@BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/snowflake';

ALTER DBT PROJECT BTC_TRADING.ORCHESTRATION.BINANCE DEPLOY FROM '@BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/snowflake';

-- 5. Stage the shared Bronze loader.
COPY FILES
    INTO @BTC_TRADING.ORCHESTRATION.ETL_SCRIPTS/
    FROM @BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/snowflake/etl/
    FILES = ('bronze_btcusdt_trades_raw.sql')
    DETAILED_OUTPUT = TRUE;

-- 6. Deploy the current quality procedures before their callers.
EXECUTE IMMEDIATE FROM @BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/snowflake/quality/dq_landing_scope.sql;
EXECUTE IMMEDIATE FROM @BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/snowflake/quality/dq_after_summary.sql;


-- 7. Deploy FULL and DELTA orchestration.
EXECUTE IMMEDIATE FROM @BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/snowflake/orchestration/delta.sql;
EXECUTE IMMEDIATE FROM @BTC_TRADING.ORCHESTRATION.DI_PIPE_ENG_REPO/branches/main/snowflake/orchestration/full.sql;


-- 10. Keep all entry points suspended for manual execution.
-- Child-task RESUME statements belong in each orchestration file.
ALTER TASK BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_DELTA SUSPEND;
ALTER TASK BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_FULL SUSPEND;

-- 11. Inspect deployment.
SHOW DBT PROJECTS IN SCHEMA BTC_TRADING.ORCHESTRATION;
SHOW PROCEDURES LIKE 'DQ_%' IN SCHEMA BTC_TRADING.ORCHESTRATION;
SHOW TASKS IN SCHEMA BTC_TRADING.ORCHESTRATION;
