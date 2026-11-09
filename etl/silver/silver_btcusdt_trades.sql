{{ config(alias='btcusdt_trades', materialized='incremental', incremental_strategy='append') }}

with typed as (
    select
        try_cast(trim(trade_id) as bigint) as trade_id,
        try_cast(trim(price) as decimal(38,8)) as price,
        try_cast(trim(quantity) as decimal(38,8)) as quantity,
        try_cast(trim(quote_quantity) as decimal(38,8)) as quote_quantity,
        try_cast(trim(trade_time_us) as bigint) as trade_time_us,
        case lower(trim(is_buyer_maker)) when 'true' then true when 'false' then false end as is_buyer_maker,
        case lower(trim(is_best_match)) when 'true' then true when 'false' then false end as is_best_match,
        trim(symbol) as symbol, source_file, ingested_at::timestamp_ltz(6) as ingested_at
    from {{ source('bronze', 'btcusdt_trades_bronze') }} b
    {% if is_incremental() %}
    where not exists (select 1 from {{ this }} s where s.source_file = b.source_file)
    {% endif %}
)
select trade_id, price, quantity, quote_quantity, trade_time_us,
    case when trade_time_us between -62135596800000000 and 253402300799999999
         then to_timestamp_ntz(trade_time_us, 6) end::timestamp_ntz(6) as trade_timestamp_utc,
    is_buyer_maker, is_best_match, symbol, source_file, ingested_at
from typed
