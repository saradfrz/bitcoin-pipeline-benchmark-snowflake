COPY INTO BTC_TRADING.BINANCE_BRONZE.BTCUSDT_TRADES_BRONZE (
    trade_id, price, quantity, quote_quantity, trade_time_us,
    is_buyer_maker, is_best_match, symbol, source_file, ingested_at
)
FROM (
    SELECT
        $1:trade_id::VARCHAR,
        $1:price::VARCHAR,
        $1:qty::VARCHAR,
        $1:quote_qty::VARCHAR,
        $1:time::VARCHAR,
        $1:is_buyer_maker::VARCHAR,
        $1:is_best_match::VARCHAR,
        'BTCUSDT',
        METADATA$FILENAME,
        METADATA$START_SCAN_TIME
    FROM @BTC_TRADING.BINANCE_BRONZE.LANDING_ZONE
)
FILE_FORMAT = (TYPE = PARQUET)
PATTERN = '(.*/)?BTCUSDT-trades-[^/]*[.]parquet'
ON_ERROR = ABORT_STATEMENT
FORCE = {{ force_reload }};
