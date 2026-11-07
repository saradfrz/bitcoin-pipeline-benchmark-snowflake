# Controles de qualidade do pipeline BTCUSDT no Snowflake

Os três controles protegem a unidade de processamento do projeto: **um arquivo Parquet e uma linha de resumo por dia de negociação UTC**. No fluxo completo, o primeiro controle protege as tabelas contra um reset com arquivos faltando. No incremental, o segundo identifica uma exclusão histórica antes que o modelo dbt recrie a linha e oculte a falha.

## Onde cada controle atua

| Controle | Quando executa | Critério de aprovação | Efeito da falha |
|---|---|---|---|
| **DQ_LANDING** | Na tarefa raiz de FULL e DELTA, antes do primeiro TRUNCATE ou COPY | O stage contém exatamente um arquivo BTCUSDT com o nome esperado para cada data, inclusive a primeira e a última. Arquivos que correspondem ao padrão do carregador, mas têm nome inesperado ou data fora do intervalo, também provocam falha. | O grafo para na raiz. No FULL, as tabelas ainda contêm os dados anteriores. |
| **DQ_BEFORE_SUMMARY** | Depois de carregar os trades Silver e antes de agregar o resumo | Existe pelo menos um trade Silver BTCUSDT por data esperada. No DELTA, cada dia previamente validado também deve continuar com exatamente uma linha no resumo. | O modelo de resumo e os quatro marts Gold ficam bloqueados. Bronze e Silver trades podem já ter concluído. |
| **DQ_AFTER_SUMMARY** | Depois de gravar o resumo, antes das quatro tarefas Gold | Cada data tem exatamente uma linha BTCUSDT no resumo e sua quantidade_trades é igual à contagem de trades Silver daquela data UTC. | O resumo já foi escrito. A falha bloqueia os quatro marts e impede o avanço da cobertura validada. |

### Como o DELTA distingue uma exclusão de um dia novo

A tabela **BTC_TRADING.ORCHESTRATION.DQ_SUMMARY_BASELINE** guarda o primeiro e o último dia do intervalo contínuo aprovado. Se a última validação cobriu até 27/10, a linha de 28/10 pode ainda não existir antes da agregação. Já a ausência de 26/10 indica perda de histórico e interrompe a execução. Depois da agregação, o terceiro controle exige também a linha do dia 28 antes de ampliar a cobertura.

Inicialize a cobertura com um FULL bem-sucedido ou com a reconstrução completa a partir de Silver trades. Para FULL e DELTA, informe o intervalo **de todo o histórico esperado**. No DELTA, mantenha a data inicial e avance a final quando chegar um novo arquivo. A carga continua incremental, mas a validação consulta o histórico. O desenho pressupõe que os arquivos permaneçam no stage e que os trades Silver existam durante todo o intervalo. Considere esse requisito ao aplicar a retenção de 270 dias.

## Teste 1 · Arquivo ausente no FULL

Em ambiente de teste, reserve uma cópia do arquivo de 26/10 e deixe-o fora do stage. Mantenha os limites reais do histórico. No exemplo, o conjunto esperado vai de 01/01 a 27/10.

```sql
EXECUTE TASK BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_FULL
  USING CONFIG = '{"start_date":"2026-01-01","end_date":"2026-10-27"}';
```

**Evidência esperada:** a raiz BINANCE_BITCOIN_FULL falha indicando 26/10. FULL_RESET_AFTER_LANDING_CHECK não executa. Reponha o mesmo arquivo e execute o FULL com os mesmos parâmetros. Aguarde a conclusão antes do próximo teste.

## Teste 2 · Dia ausente no resumo durante o DELTA

Após validar o histórico, remova somente a linha de 26/10 do resumo de teste. Preserve o arquivo e os trades desse dia.

```sql
DELETE FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
WHERE symbol = 'BTCUSDT' AND data = '2026-10-26';

EXECUTE TASK BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_DELTA
  USING CONFIG = '{"start_date":"2026-01-01","end_date":"2026-10-27"}';
```

**Evidência esperada:** a validação do stage passa. DELTA_DQ_BEFORE_SUMMARY falha indicando 26/10. O escritor do resumo e as tarefas Gold não executam nessa tentativa.

## Recuperação do resumo

1. Execute o backfill com as datas afetadas. Use a mesma data nos dois campos para reparar um único dia. O procedimento confere a origem, substitui o intervalo e reconcilia as contagens na mesma transação de escrita. Se a validação falhar, as alterações são desfeitas.

   ```sql
   EXECUTE TASK BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_BACKFILL_SUMMARY
     USING CONFIG = '{"start_date":"2026-10-26","end_date":"2026-10-26"}';
   ```

2. Aguarde o sucesso do backfill. Para demonstrar a reconstrução completa, informe **todo o histórico** na segunda execução. Esse pipeline lê os trades Silver, reconstrói o resumo, valida a cobertura e dispara em paralelo os marts de SMA 50, SMA 200, CVD e VWAP.

   ```sql
   EXECUTE TASK BTC_TRADING.ORCHESTRATION.BINANCE_BITCOIN_FULL_SUMMARY_TO_GOLD
     USING CONFIG = '{"start_date":"2026-01-01","end_date":"2026-10-27"}';
   ```

3. Aguarde os quatro marts e repita o DELTA com os parâmetros do teste 2. Para um reparo pontual de rotina, também é possível executar o DELTA logo após o backfill, sem repetir a reconstrução completa. Execute um grafo por vez.

## Evidências da entrega

Compare as tarefas pelo identificador da execução. Guarde a mensagem com a data faltante, o estado das tarefas dependentes e a execução bem-sucedida após o reparo.

```sql
SELECT graph_run_group_id, name, state, scheduled_time, completed_time, error_message
FROM TABLE(BTC_TRADING.INFORMATION_SCHEMA.TASK_HISTORY(RESULT_LIMIT => 1000))
WHERE database_name = 'BTC_TRADING' AND schema_name = 'ORCHESTRATION'
ORDER BY scheduled_time DESC;

SELECT data, quantidade_trades
FROM BTC_TRADING.BINANCE_SILVER.BTCUSDT_DAILY_TRADE_SUMMARY
WHERE symbol = 'BTCUSDT' AND data = '2026-10-26';
```

Os resultados acima são os critérios de aceitação dos testes. A reconciliação verifica cobertura e contagens. Uma alteração de preço que preserve a quantidade de trades exige um teste adicional de valores ou dos indicadores.
