# Seletor de séries no dashboard

Data: 11/08/2026
Status: aprovado, aguardando plano de implementação

## Problema

O dashboard tem um campo numérico "Código da série SGS" no sidebar. Ele
funciona, mas é inútil na prática por duas razões:

1. **Exige conhecimento que não está na tela.** Para ver a Selic é preciso
   saber, de cabeça, que ela é a série 11. O campo não dá pista nenhuma.
2. **Aceita códigos que levam a lugar nenhum.** O dashboard só lê
   `analytics.serie_bcb_metrics`; ele não busca na API. Como só a série 1 foi
   ingerida, digitar 11 produz "nenhum dado encontrado" — um beco sem saída
   que parece um bug.

## Decisões tomadas

### O dashboard continua sendo apenas leitura

Descartada a alternativa de um botão "carregar série agora" que dispararia a
ingestão pela interface.

**Por quê:** a separação ingestão → transformação → apresentação é uma das
competências que o projeto demonstra, e o README a vende explicitamente. Além
disso, chamar a API dentro do clique do usuário traria modos de falha que hoje
não existem: o SGS faz rate limiting por IP devolvendo `HTTP 200 + text/html`
(ver `docs/IMPLEMENTATION_GUIDE.md`), o que exigiria retry, timeout, spinner e
proteção contra cliques concorrentes — bastante complexidade para uma
conveniência.

**Consequência aceita:** só é possível ver no dashboard as séries que o
pipeline já carregou. O seletor nunca oferece uma opção vazia.

### Um catálogo de séries como fonte única da verdade

Novo módulo `db/series_catalog.py`, com um dicionário de séries conhecidas.
Ele responde a duas perguntas que hoje ninguém responde: **quais séries o
pipeline carrega** e **como rotular cada uma na tela**.

Fica em Python, não numa tabela do banco: os dados mudam quando o código muda,
não em runtime, e uma tabela exigiria migração e join sem benefício.

### Rótulos derivados da periodicidade

As séries têm periodicidades diferentes — verificado contra a API em
11/08/2026, no 1º semestre de 2025:

| Série | Registros | Periodicidade | Unidade | Exemplo |
|-------|-----------|---------------|---------|---------|
| 1 — Dólar comercial (venda) | 122 | diária | R$ | 5,4571 |
| 11 — Selic | 122 | diária | % a.d. | 0,055131 |
| 433 — IPCA | 6 | **mensal** | % a.m. | 0,24 |

`02_create_analytics_table.sql` define as janelas com `ROWS BETWEEN N
PRECEDING`, que conta **linhas**, não dias. Numa série mensal, "média móvel
7d" seriam 7 meses. O SQL não muda; **o rótulo passa a dizer a verdade**:
"Média móvel 7 dias" na série diária, "Média móvel 7 meses" na mensal.

## Arquitetura

```
db/series_catalog.py ──┬──→ ingestão (--todas) ──→ raw.serie_bcb
                       │                                  │
                       │                                  ▼ SQL (inalterado)
                       │                    analytics.serie_bcb_metrics
                       │                                  │
                       └──→ dashboard (rótulo, unidade) ←──┘
                                    ▲
                     SELECT DISTINCT codigo_serie
```

O SQL de transformação **não muda**. Todas as window functions de
`02_create_analytics_table.sql` já usam `PARTITION BY codigo_serie` e a chave
primária é `(codigo_serie, data)` — a tabela sempre soube conviver com várias
séries, apenas nunca teve mais de uma.

## Componentes

### 1. `db/series_catalog.py` (novo)

```python
@dataclass(frozen=True)
class Serie:
    nome: str            # rótulo exibido no seletor
    unidade: str         # sufixo/prefixo do valor formatado
    periodicidade: str   # "diaria" | "mensal"
    decimais: int        # casas decimais na exibição

SERIES: dict[int, Serie] = {
    1:   Serie("Dólar comercial (venda)", "R$",     "diaria", 4),
    11:  Serie("Selic",                   "% a.d.", "diaria", 4),
    433: Serie("IPCA",                    "% a.m.", "mensal", 2),
}
```

As casas decimais são por série, não por tipo: a Selic diária vale `0,055131`
e arredondá-la para 2 casas daria `0,06 %`, perdendo a informação. A coluna
no banco é `NUMERIC(18, 6)`, então nada se perde na origem — a escolha é só
de exibição.

Funções puras, todas testáveis sem banco e sem rede:

- `rotulo_janela(periodicidade, n) -> str` — devolve `"7 dias"` ou `"7 meses"`.
- `formata_valor(valor, serie) -> str` — aplica casas decimais, separador
  decimal **vírgula** (pt-BR) e a unidade completa. Unidade que começa com `%`
  vai **depois** do número (`0,24 % a.m.`, `0,0551 % a.d.`); as demais vão
  **antes** (`R$ 5,1285`).
- `nome_da_serie(codigo) -> str` — nome do catálogo; para código ausente,
  devolve `"Série {codigo}"` em vez de falhar.

### 2. `ingestion/fetch_data.py`

Ganha a flag `--todas`, que itera `SERIES` e ingere cada uma. É **mutuamente
exclusiva** com `--serie` (grupo do argparse); passar as duas é erro de uso.

A lista de séries a carregar mora no catálogo, não no `run_pipeline.ps1` —
caso contrário o script viraria uma segunda fonte da verdade sobre quais
séries existem.

### 3. `dashboard/app.py`

- O `number_input` vira `st.sidebar.selectbox`. As opções vêm do cruzamento
  entre `SELECT DISTINCT codigo_serie FROM analytics.serie_bcb_metrics` (o que
  existe) e o catálogo (como se chama). Ordenadas pela ordem do catálogo, com
  os códigos desconhecidos ao final.
- Seleção inicial: a primeira opção da lista.
- Banco sem série nenhuma: aviso explicando que o pipeline precisa rodar.
- Rótulos dos KPIs e legendas do gráfico passam por `rotulo_janela`.
- Valores passam por `formata_valor`.

### 4. `run_pipeline.ps1`

Passa a chamar `--todas`.

## Tratamento de erro

`--todas` faz **três requisições em sequência** — exatamente o padrão que
disparou o throttle do BCB durante a depuração de 11/08/2026.

- **Espaçamento**: pausa de ~3 s entre séries (não após a última).
- **Falha isolada não derruba o lote**: erro em uma série é registrado no log
  e a próxima continua.
- **Código de saída**: diferente de zero se qualquer série falhou, para o CI e
  o agendador perceberem. O log final diz quantas de quantas foram carregadas.

Carregar 2 de 3 e avisar é melhor que perder as três porque a segunda esbarrou
no limite.

## Testes

Sem banco e sem rede, como o resto da suíte:

1. `rotulo_janela` devolve "7 dias" para série diária e "7 meses" para mensal.
2. `formata_valor` põe `R$` antes e `%` depois, com vírgula decimal e o número
   de casas do catálogo.
3. `nome_da_serie` devolve `"Série 999"` para código fora do catálogo.
4. `--todas` itera todas as séries do catálogo (com `requests.get` mockado).
5. `--todas` continua após falha de uma série e termina com código != 0.
6. `--todas` junto com `--serie` é rejeitado.
7. A montagem das opções do seletor (função pura) devolve os rótulos na ordem
   do catálogo e coloca código desconhecido ao final.

## Fora de escopo

- **Redesign visual** — adiado a pedido do usuário para 12/08/2026.
- **Dashboard chamando a API ou escrevendo no banco** — descartado acima.
- **Janelas próprias por periodicidade** (3 e 12 meses para o IPCA) — foi
  considerado e descartado nesta rodada.

## Ressalva conhecida

Para o IPCA, uma janela de 30 períodos são 30 meses — dois anos e meio. O
rótulo estará correto ("Média móvel 30 meses"), mas a utilidade da métrica
nessa série é discutível. Se incomodar na tela, a saída é a alternativa
descartada acima: janelas próprias por periodicidade.
