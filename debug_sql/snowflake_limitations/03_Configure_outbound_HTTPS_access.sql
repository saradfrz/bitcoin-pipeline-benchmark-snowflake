CREATE NETWORK RULE IF NOT EXISTS BTC_TRADING.BINANCE_BRONZE.BINANCE_HTTPS_RULE
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = ('data.binance.vision:443');

CREATE EXTERNAL ACCESS INTEGRATION IF NOT EXISTS BINANCE_ARCHIVE_ACCESS
    ALLOWED_NETWORK_RULES = (BTC_TRADING.BINANCE_BRONZE.BINANCE_HTTPS_RULE)
    ENABLED = TRUE;

-- SQL compilation error: External access is not supported for trial accounts.
-- Portanto a carga sera realizada de forma manual. Como há limitação de 250mb por arquivo, estes serão convertidos para parquet