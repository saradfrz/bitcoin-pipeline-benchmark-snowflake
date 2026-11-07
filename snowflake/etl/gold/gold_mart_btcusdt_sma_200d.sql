{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['symbol', 'data'],
    schema='BINANCE_GOLD',
    alias='mart_btcusdt_sma_200d'
) }}

with daily as (
    select symbol, data, preco_fechamento
    from {{ ref('silver_btcusdt_daily_trade_summary') }}
    where symbol = 'BTCUSDT'
),
{% if is_incremental() %}
changed as (
    select s.symbol, s.data
    from daily s
    left join {{ this }} g on g.symbol = s.symbol and g.data = s.data
    where g.data is null or s.preco_fechamento is distinct from g.preco_fechamento
),
{% endif %}
affected as (
    select d.*
    from daily d
    {% if is_incremental() %}
    where exists (
        select 1
        from changed c
        where c.symbol = d.symbol
          and d.data between c.data and dateadd(day, 199, c.data)
    )
    {% endif %}
)
select
    a.symbol,
    a.data,
    a.preco_fechamento,
    case when count(h.preco_fechamento) = 200
         then avg(h.preco_fechamento)
    end::number(38, 10) as sma_200d
from affected a
join daily h
  on h.symbol = a.symbol
 and h.data between dateadd(day, -199, a.data) and a.data
group by a.symbol, a.data, a.preco_fechamento
