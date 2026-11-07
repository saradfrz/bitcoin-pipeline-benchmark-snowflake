# BTCUSDT na Binance — das negociações aos indicadores diários

O projeto transforma as negociações de bitcoin por Tether (BTCUSDT) no mercado à vista da Binance em quatro indicadores diários. As médias móveis de 50 e 200 dias acompanham o preço de fechamento. O CVD acompanha o saldo acumulado entre compras e vendas agressoras. O VWAP mostra o preço médio pago por BTC, dando mais peso às negociações de maior volume.

## Como os dados percorrem as camadas

| Etapa | O que acontece | O que cada registro representa |
|---|---|---|
| Entrada | O arquivo diário da Binance chega à área de entrada em CSV no Databricks e em Parquet no Snowflake. | Um arquivo por dia do par BTCUSDT. |
| Bronze · `binance_bronze.btcusdt_trades_bronze` | A carga preserva os valores recebidos e registra o arquivo de origem e o horário de ingestão. | Uma negociação. |
| Silver · `binance_silver.btcusdt_trades` | A transformação converte preços e quantidades em números, o horário da negociação em timestamp e os indicadores lógicos em booleanos. | A mesma negociação, com tipos adequados para cálculo. |
| Silver · `binance_silver.btcusdt_daily_trade_summary` | As negociações são agrupadas por par e pela data em que ocorreram, em UTC. | Um resumo por par e dia. |
| Gold · `binance_gold` | Quatro tabelas analíticas calculam os indicadores a partir do resumo Silver. | Um resultado por par e dia em cada tabela. |

### O que entra no resumo Silver

A abertura é o preço da primeira negociação do dia e o fechamento é o da última, usando o identificador da negociação para desempatar horários iguais. A máxima e a mínima são o maior e o menor preço negociados. Para as médias móveis, a Gold usa apenas o **fechamento** de cada dia.

| Medida diária | Cálculo sobre as negociações do dia |
|---|---|
| Quantidade de negociações | Contagem das linhas de BTCUSDT. |
| Volume total em BTC | Soma de `quantity`, a quantidade de bitcoin de cada negociação. |
| Volume total em USDT | Soma de `quote_quantity`, o valor financeiro de cada negociação (preço × quantidade). |
| Volume de compra agressora em BTC | Soma de `quantity` quando `is_buyer_maker = false`. O comprador aceitou uma oferta de venda que já estava no livro. |
| Volume de venda agressora em BTC | Soma de `quantity` quando `is_buyer_maker = true`. O vendedor aceitou uma oferta de compra que já estava no livro. |
| Saldo diário em BTC (`delta_btc`) | Volume de compra agressora − volume de venda agressora. |

## Como a Gold calcula os indicadores

Nas fórmulas, **D** é a data do indicador. As janelas das médias móveis incluem o próprio dia D.

| Indicador e tabela em `binance_gold` | Fórmula | Como ler o resultado |
|---|---|---|
| MM50 · `mart_btcusdt_sma_50d` | Soma dos fechamentos de D−49 até D ÷ 50 | Preço médio de fechamento dos últimos 50 dias, em USDT por BTC. |
| MM200 · `mart_btcusdt_sma_200d` | Soma dos fechamentos de D−199 até D ÷ 200 | Referência de preço de prazo mais longo. Cada novo fechamento tem menos peso do que na MM50. |
| CVD · `mart_btcusdt_cvd` | CVD do dia anterior + `delta_btc` do dia D | Saldo acumulado em BTC desde o início do histórico, com saldo inicial zero. Se o CVD sobe, o volume de compra agressora superou o de venda agressora naquele dia. |
| VWAP diário · `mart_btcusdt_vwap` | `volume_total_usdt ÷ volume_total_btc` no dia D | Preço médio negociado em USDT por BTC, ponderado pela quantidade. O cálculo recomeça a cada dia. |

A MM50 e a MM200 ficam nulas até haver, respectivamente, 50 e 200 fechamentos na janela. O VWAP fica nulo se o volume total em BTC for zero.

**Exemplo com duas negociações no mesmo dia.** Uma compra agressora de 2 BTC a 80.000 USDT por BTC e uma venda agressora de 1 BTC a 83.000 movimentam 3 BTC e 243.000 USDT. O **VWAP é 81.000 USDT por BTC** (243.000 ÷ 3). Já o **saldo do dia é +1 BTC** (2 − 1). Se o CVD anterior era 10 BTC, o novo acumulado é 11 BTC.

## Carga completa, incremental e qualidade

A carga **completa** reconstrói o histórico a partir dos arquivos do período. A carga **incremental** incorpora os arquivos novos. Quando uma correção chega ao resumo Silver, o alcance do recálculo na Gold depende da fórmula.

| Se mudar um dado do dia D | Quais resultados podem mudar |
|---|---|
| Preço de fechamento | MM50 de D até D+49 e MM200 de D até D+199, para as datas já presentes no resumo. |
| Saldo diário em BTC | CVD de D em diante, pois todos os acumulados seguintes incluem esse saldo. |
| Volume total em BTC ou em USDT | VWAP apenas do dia D. |

No Snowflake, o primeiro controle verifica os arquivos esperados antes da carga. Assim, um arquivo ausente interrompe a carga completa antes de esvaziar as tabelas. O segundo verifica se há negociações nos dias esperados e, na carga incremental, se cada dia já validado continua com uma única linha no resumo. O terceiro compara o resumo reconstruído com as negociações Silver, conferindo a presença de uma linha por dia e a contagem de negociações antes de liberar a Gold.

Se faltar um dia já validado no resumo, a recuperação pode reconstruir esse dia ou um intervalo a partir das negociações Silver. Há também um fluxo para reconstruir o resumo inteiro, validá-lo e recalcular os quatro indicadores.

**Fonte dos dados** · [Arquivos diários de negociações BTCUSDT da Binance](https://data.binance.vision/?prefix=data/spot/daily/trades/BTCUSDT/)
