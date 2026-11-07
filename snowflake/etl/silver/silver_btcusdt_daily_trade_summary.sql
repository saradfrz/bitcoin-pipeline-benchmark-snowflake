{{ config(alias='btcusdt_daily_trade_summary', materialized='incremental',
          incremental_strategy='merge', unique_key=['symbol', 'data']) }}

with trades as (
    select *, trade_timestamp_utc::date as data
    from {{ ref('silver_btcusdt_trades') }}
    where symbol = 'BTCUSDT' and trade_timestamp_utc is not null
),
changed_days as (
    select t.symbol, t.data
    from trades t
    {% if is_incremental() %}
    left join {{ this }} s on s.symbol = t.symbol and s.data = t.data
    {% endif %}
    group by t.symbol, t.data
    {% if is_incremental() %}
    having count(*) <> coalesce(max(s.quantidade_trades), 0)
    {% endif %}
),
ordered as (
    select t.*,
        row_number() over (partition by symbol, data order by trade_time_us, trade_id) as opening_rank,
        row_number() over (partition by symbol, data order by trade_time_us desc, trade_id desc) as closing_rank
    from trades t join changed_days using (symbol, data)
)
select symbol, data, min(trade_timestamp_utc) as primeiro_timestamp,
    max(trade_timestamp_utc) as ultimo_timestamp,
    max(iff(opening_rank=1, trade_id, null)) as primeiro_trade_id,
    max(iff(closing_rank=1, trade_id, null)) as ultimo_trade_id,
    max(iff(opening_rank=1, price, null)) as preco_abertura,
    max(price) as preco_maximo, min(price) as preco_minimo,
    max(iff(closing_rank=1, price, null)) as preco_fechamento, avg(price) as preco_medio_simples,
    sum(quantity) as volume_total_btc, sum(quote_quantity) as volume_total_usdt,
    sum(iff(is_buyer_maker=false, quantity, 0)) as volume_comprador_btc,
    sum(iff(is_buyer_maker=true, quantity, 0)) as volume_vendedor_btc,
    volume_comprador_btc - volume_vendedor_btc as delta_btc,
    sum(iff(is_buyer_maker=false, quote_quantity, 0)) as volume_comprador_usdt,
    sum(iff(is_buyer_maker=true, quote_quantity, 0)) as volume_vendedor_usdt,
    volume_comprador_usdt - volume_vendedor_usdt as delta_usdt,
    volume_total_usdt / nullif(volume_total_btc, 0) as vwap_diario,
    count(*) as quantidade_trades,
    sum(iff(is_buyer_maker=false, 1, 0)) as trades_compradores,
    sum(iff(is_buyer_maker=true, 1, 0)) as trades_vendedores,
    100 * delta_btc / nullif(volume_total_btc, 0) as desequilibrio_percentual
from ordered group by symbol, data
