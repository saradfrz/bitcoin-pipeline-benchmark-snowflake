CREATE OR REPLACE PROCEDURE BTC_TRADING.ORCHESTRATION.DQ_AFTER_SUMMARY(payload VARCHAR)
RETURNS VARCHAR LANGUAGE SQL EXECUTE AS CALLER AS
$$
DECLARE
    lo DATE;
    hi DATE;
    distinct_days INTEGER;
    summary_rows INTEGER;
    invalid_scope EXCEPTION (-20104, 'Missing or reversed Silver summary scope.');
    bad_summary EXCEPTION (-20105, 'Expected exactly one BTCUSDT Silver summary row per requested day.');
BEGIN
    SELECT PARSE_JSON(:payload):lo::DATE, PARSE_JSON(:payload):summary_hi::DATE
    INTO :lo, :hi;
    IF (lo IS NULL OR hi IS NULL OR lo > hi) THEN RAISE invalid_scope; END IF;
    SELECT COUNT(DISTINCT data), COUNT(*) INTO :distinct_days, :summary_rows
    FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
    WHERE symbol = 'BTCUSDT' AND data BETWEEN :lo AND :hi;
    IF (distinct_days <> DATEDIFF(day, lo, hi) + 1 OR summary_rows <> distinct_days) THEN
        RAISE bad_summary;
    END IF;
    RETURN 'PASS';
END;
$$;
