-- Validate a single LIST snapshot. Return its bounds to the calling task.
CREATE OR REPLACE PROCEDURE BTC_TRADING.ORCHESTRATION.DQ_LANDING_SCOPE()
RETURNS OBJECT LANGUAGE SQL EXECUTE AS CALLER AS
$$
DECLARE
    listing VARCHAR;
    lo DATE;
    hi DATE;
    files INTEGER;
    dated INTEGER;
    days INTEGER;
    empty_stage EXCEPTION (-20100, 'No BTCUSDT Parquet archives found.');
    bad_name EXCEPTION (-20101, 'Invalid BTCUSDT archive name or calendar date.');
    duplicate_day EXCEPTION (-20102, 'Multiple BTCUSDT archives for one day.');
    missing_day EXCEPTION (-20103, 'Missing daily archive between first and last landing dates.');
BEGIN
    LIST @BTC_TRADING.BINANCE_BRONZE.LANDING_ZONE
        PATTERN = '(.*/)?BTCUSDT-trades-[^/]*[.]parquet';
    listing := SQLID;
    WITH names AS (
        SELECT SPLIT_PART("name", '/', -1) AS filename
        FROM TABLE(RESULT_SCAN(:listing))
    ), dates AS (
        SELECT IFF(REGEXP_LIKE(filename, 'BTCUSDT-trades-[0-9]{4}-[0-9]{2}-[0-9]{2}[.]parquet'),
                   TRY_TO_DATE(SUBSTR(filename, LENGTH('BTCUSDT-trades-') + 1, 10), 'YYYY-MM-DD'), NULL) AS day
        FROM names
    )
    SELECT MIN(day), MAX(day), COUNT(*), COUNT(day), COUNT(DISTINCT day)
    INTO :lo, :hi, :files, :dated, :days FROM dates;
    IF (files = 0) THEN RAISE empty_stage; END IF;
    IF (files <> dated) THEN RAISE bad_name; END IF;
    IF (dated <> days) THEN RAISE duplicate_day; END IF;
    IF (days <> DATEDIFF(day, lo, hi) + 1) THEN RAISE missing_day; END IF;
    RETURN OBJECT_CONSTRUCT('lo', TO_CHAR(lo,'YYYY-MM-DD'), 'hi', TO_CHAR(hi,'YYYY-MM-DD'));
END;
$$;
