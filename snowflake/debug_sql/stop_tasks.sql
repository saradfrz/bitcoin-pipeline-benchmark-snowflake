ALTER TASK BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_FULL SUSPEND;

EXECUTE IMMEDIATE $$
DECLARE
    running_tasks RESULTSET DEFAULT (
        SELECT DISTINCT database_name, schema_name, name
        FROM TABLE(
            BTC_TRADING.INFORMATION_SCHEMA.TASK_HISTORY(
                RESULT_LIMIT => 10000
            )
        )
        WHERE database_name = 'BTC_TRADING'
          AND schema_name = 'ORCHESTRATION'
          AND state = 'EXECUTING'
          AND (
              name = 'BINANCE_BITCOIN_FULL'
              OR STARTSWITH(name, 'FULL_')
          )
    );
    task_name VARCHAR;
    cancel_result VARCHAR;
BEGIN
    FOR task_row IN running_tasks DO
        task_name := task_row.database_name || '.'
                  || task_row.schema_name || '.'
                  || task_row.name;

        SELECT SYSTEM$USER_TASK_CANCEL_ONGOING_EXECUTIONS(:task_name)
        INTO :cancel_result;
    END FOR;
END;
$$;