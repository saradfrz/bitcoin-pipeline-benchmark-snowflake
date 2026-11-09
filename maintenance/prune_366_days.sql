-- BTCUSDT retention, run only after a successful delta load and Gold build.
-- UTC calendar cutoff: keep cutoff day; remove strictly earlier dates.
-- Stage removal is not transactional. Remove oldest dates first so a retry
-- does not create a gap inside the remaining landing interval checked by DQ.
EXECUTE IMMEDIATE $$
DECLARE
    cutoff DATE DEFAULT DATEADD(day, -366, CONVERT_TIMEZONE('UTC', CURRENT_TIMESTAMP())::DATE);
    cutoff_us NUMBER(38, 0);
    listing VARCHAR;
    expired RESULTSET;
    command VARCHAR;
    removed_days INTEGER DEFAULT 0;
    payload VARCHAR;
BEGIN
    cutoff_us := DATEDIFF(microsecond, '1970-01-01'::TIMESTAMP_NTZ, cutoff::TIMESTAMP_NTZ);
    LIST @BTC_TRADING.BINANCE_BRONZE.LANDING_ZONE
        PATTERN = '^(.*/)?BTCUSDT-trades-[0-9]{4}-[0-9]{2}-[0-9]{2}[.]parquet$';
    listing := SQLID;
    expired := (
        SELECT DISTINCT TRY_TO_DATE(
            SUBSTR(SPLIT_PART("name", '/', -1), LENGTH('BTCUSDT-trades-') + 1, 10),
            'YYYY-MM-DD') AS archive_day
        FROM TABLE(RESULT_SCAN(:listing))
        WHERE archive_day < :cutoff
        ORDER BY archive_day
    );
    FOR archive IN expired DO
        -- The dynamic fragment is a formatted DATE, never a raw stage path.
        command := 'REMOVE @BTC_TRADING.BINANCE_BRONZE.LANDING_ZONE PATTERN = '
            || CHR(39) || '^(.*/)?BTCUSDT-trades-'
            || TO_CHAR(archive.archive_day, 'YYYY-MM-DD') || '[.]parquet$' || CHR(39);
        EXECUTE IMMEDIATE :command;
        removed_days := removed_days + 1;
    END FOR;

    -- All seven table deletes commit together. No auxiliary tables are needed.
    BEGIN
        BEGIN TRANSACTION;
        DELETE FROM BTC_TRADING.BINANCE_BRONZE.BTCUSDT_TRADES_BRONZE
        WHERE symbol = 'BTCUSDT' AND TRY_TO_NUMBER(TRIM(trade_time_us)) < :cutoff_us;
        DELETE FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_TRADES
        WHERE symbol = 'BTCUSDT' AND trade_timestamp_utc < :cutoff::TIMESTAMP_NTZ;
        DELETE FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
        WHERE symbol = 'BTCUSDT' AND data < :cutoff;
        DELETE FROM BTC_TRADING.BINANCE_GOLD.MART_BTCUSDT_SMA_50D
        WHERE symbol = 'BTCUSDT' AND data < :cutoff;
        DELETE FROM BTC_TRADING.BINANCE_GOLD.MART_BTCUSDT_SMA_200D
        WHERE symbol = 'BTCUSDT' AND data < :cutoff;
        DELETE FROM BTC_TRADING.BINANCE_GOLD.MART_BTCUSDT_CVD
        WHERE symbol = 'BTCUSDT' AND data < :cutoff;
        DELETE FROM BTC_TRADING.BINANCE_GOLD.MART_BTCUSDT_VWAP
        WHERE symbol = 'BTCUSDT' AND data < :cutoff;
        COMMIT;
    EXCEPTION
        WHEN OTHER THEN
            ROLLBACK;
            RAISE;
    END;
    payload := TO_JSON(OBJECT_CONSTRUCT('cutoff_utc', TO_CHAR(cutoff, 'YYYY-MM-DD'),
        'archive_days_processed', removed_days, 'status', 'PRUNED'));
    CALL SYSTEM$SET_RETURN_VALUE(:payload);
END;
$$;
