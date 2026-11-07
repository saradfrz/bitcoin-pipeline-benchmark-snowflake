{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['symbol', 'data'],
    schema='BINANCE_GOLD',
    alias='mart_btcusdt_cvd'
) }}

-- Continuous BTC CVD. Silver supplies one signed BTC delta per UTC trading day.
with daily as (
    select symbol, data, cast(delta_btc as number(38, 8)) as delta_btc
    from {{ ref('silver_btcusdt_daily_trade_summary') }}
    where symbol = 'BTCUSDT'
),
{% if is_incremental() %}
first_change as (
    select s.symbol, min(s.data) as first_date
    from daily s
    left join {{ this }} g on g.symbol = s.symbol and g.data = s.data
    where g.data is null or s.delta_btc is distinct from g.delta_btc
    group by s.symbol
),
seed as (
    select c.symbol, c.first_date, g.cvd_btc as opening_cvd
    from first_change c
    left join {{ this }} g on g.symbol = c.symbol and g.data < c.first_date
    qualify row_number() over (partition by c.symbol order by g.data desc) = 1
),
{% endif %}
affected as (
    select d.symbol, d.data, d.delta_btc,
    {% if is_incremental() %}
           coalesce(s.opening_cvd, 0) as opening_cvd
    from daily d
    join seed s on d.symbol = s.symbol and d.data >= s.first_date
    {% else %}
           0 as opening_cvd
    from daily d
    {% endif %}
),
computed as (
    select symbol, data, delta_btc,
           cast(opening_cvd + sum(delta_btc) over (
               partition by symbol order by data
               rows between unbounded preceding and current row
           ) as number(38, 8)) as cvd_btc
    from affected
)
select c.symbol, c.data, c.delta_btc, c.cvd_btc
from computed c
{% if is_incremental() %}
left join {{ this }} g on g.symbol = c.symbol and g.data = c.data
where g.data is null or c.delta_btc is distinct from g.delta_btc
   or c.cvd_btc is distinct from g.cvd_btc
{% endif %}
