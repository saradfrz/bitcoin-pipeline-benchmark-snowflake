{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['symbol', 'data'],
    schema='BINANCE_GOLD',
    alias='mart_btcusdt_vwap'
) }}

-- One row per UTC trading day. Both totals describe the same session.
with affected_days as (
    select s.symbol, s.data, s.volume_total_btc, s.volume_total_usdt
    from {{ ref('silver_btcusdt_daily_trade_summary') }} s
    {% if is_incremental() %}
    left join {{ this }} g on s.symbol = g.symbol and s.data = g.data
    {% endif %}
    where s.symbol = 'BTCUSDT'
    {% if is_incremental() %}
      and (g.data is null
           or s.volume_total_btc is distinct from g.volume_total_btc
           or s.volume_total_usdt is distinct from g.volume_total_usdt)
    {% endif %}
)
select symbol, data, volume_total_btc, volume_total_usdt,
       cast(volume_total_usdt / nullif(volume_total_btc, 0) as number(38, 8)) as vwap_diario
from affected_days
