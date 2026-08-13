# Guia de implementação

Este arquivo complementa o README: aqui está o passo a passo comentado, o
porquê de cada decisão técnica e exemplos de como estender o projeto.

## 1. Passo a passo comentado

### 1.1 Subir o banco

```powershell
Copy-Item .env.example .env
docker compose up -d
docker compose ps        # confirma que o container está "healthy"
```

O `docker-compose.yml` sobe um Postgres 16 isolado, com os dados persistidos
em um volume nomeado (`pgdata`). Isso significa que você pode derrubar e
subir o container (`docker compose down` / `up`) sem perder dados — só
`docker compose down -v` apaga o volume.

> **Conflito de porta**: se você já tiver um PostgreSQL instalado nativamente
> na máquina, ele provavelmente ocupa a porta 5432 e o `docker compose up -d`
> falhará com erro de bind. O Compose é parametrizado para isso — basta
> definir `POSTGRES_PORT=5433` no `.env` e o container passa a expor a 5433
> no host, sem editar o YAML.

### 1.2 Ambiente Python

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.lock
```

Instale a partir do `requirements.lock`, não do `requirements.txt`: o lock
tem as 51 versões exatas já validadas, incluindo as transitivas. O
`requirements.txt` fixa só as 9 diretas — o resto ficaria flutuando.

Se o PowerShell bloquear a ativação do venv com erro de execution policy,
rode uma vez (como usuário, não precisa ser admin):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

Alternativa que dispensa ativação: chamar o interpretador do venv
diretamente, com `.venv\Scripts\python.exe -m ...`. É o que os scripts de
automação deste projeto fazem, porque `Activate.ps1` roda em escopo filho e
o `PATH` que ele define não sobrevive ao fim do script.

### 1.3 Ingestão

```powershell
python -m ingestion.fetch_data --inicio 01/01/2024 --fim 31/12/2025
```

O que acontece:
1. `ensure_raw_table()` garante que `raw.serie_bcb` existe (idempotente).
2. `fetch_series()` chama a API do BCB e valida a resposta.
3. `load_raw()` faz um upsert (`INSERT ... ON CONFLICT DO UPDATE`), então
   rodar o comando de novo não duplica linhas — atualiza os valores mais
   recentes.

Alternativas de execução:
```powershell
# atalho: ingestão + transformação, janela em anos (padrão 2)
.\run_pipeline.ps1 -Anos 5

# todas as series do catalogo (dolar, Selic, IPCA)
python -m ingestion.fetch_data --todas --inicio 01/01/2024 --fim 31/12/2025

# uma serie especifica
python -m ingestion.fetch_data --serie 11 --inicio 01/01/2024 --fim 31/12/2025

# espiada rápida: o modo --ultimos existe, mas o teto da API é 20
python -m ingestion.fetch_data --ultimos 20
```

`--todas` e `--serie` são mutuamente exclusivas: passar as duas é erro de uso.
Uma série que falhe (o throttle do SGS, por exemplo) não derruba as demais —
o log diz quantas de quantas foram carregadas e o processo sai com código
diferente de zero se alguma falhou. Há uma pausa de 3s entre as séries,
porque três chamadas em sequência são exatamente o padrão que dispara o
limite por IP descrito abaixo.

Para acrescentar uma série ao projeto, basta adicioná-la a `SERIES` em
`db/series_catalog.py` — a ingestão e o seletor do dashboard passam a
enxergá-la automaticamente. Informe a periodicidade correta: as janelas do
SQL contam linhas, então é ela que define se "7" significa 7 dias ou 7 meses.

> **Limites da API, medidos em 11/08/2026:**
> - `/ultimos/{N}` aceita **no máximo N=20**. Acima disso: HTTP 400 com
>   `"A quantidade máxima de valores deve ser 20"`. Verificado por bisseção —
>   `ultimos/11` passa, `ultimos/25` já é recusado.
> - Consulta por intervalo aceita até **10 anos** em séries de periodicidade
>   diária. Acima disso: HTTP 406 explicando a janela.
> - **Rate limiting por IP vem como HTTP 200 + `text/html`** (a página
>   "Requisição inválida!"), e **não** como 429. Isso faz o `raise_for_status()`
>   passar direto — por isso `fetch_series()` também valida que o corpo é JSON
>   antes de confiar na resposta. Recupera sozinho em menos de 1 minuto.
>
> Consequência prática: o pipeline usa **intervalo de datas**, não `/ultimos`.
> Com teto de 20 pontos, a média móvel de 30 dias não teria o que calcular.

### 1.4 Transformação

```powershell
python -m transform.run_transform
```

Executa, em ordem, cada arquivo em `sql/`. Hoje são dois:
- `01_create_raw_table.sql` — idempotente, documenta o contrato da camada raw.
- `02_create_analytics_table.sql` — recria `analytics.serie_bcb_metrics` do
  zero a cada execução (`DROP` + `CREATE TABLE AS SELECT`). Para uma série
  diária isso é instantâneo; para volumes maiores, veja a seção 3.2.

### 1.5 Dashboard

```powershell
streamlit run dashboard/app.py
```

Abre em `http://localhost:8501`. O sidebar permite trocar a série e filtrar
o período; os KPIs e o gráfico recalculam a partir do DataFrame já filtrado.
A faixa de indicadores do topo é a exceção: ela mostra sempre o valor mais
recente de cada série, com a data de referência ao lado, porque um cartão
rotulado como valor atual exibindo um número de dois anos atrás seria falso.

### Aparência

O tema mora em dois arquivos, e só neles: `.streamlit/config.toml` (cores
base, lidas nativamente pelo Streamlit) e `dashboard/estilo.py` (tokens,
template do Plotly e o CSS pontual). Os valores de cor estão repetidos nos
dois porque o tema nativo só lê TOML — ao mudar um, mude o outro.

O CSS cobre apenas o que o Streamlit 1.36 não permite nativamente: o
`st.metric` só passou a aceitar `border` na 1.44, e a tipografia dos KPIs
não é configurável. Cada regra leva um comentário dizendo o que faz, porque
os seletores miram `data-testid` internos do Streamlit e podem desalinhar
num upgrade. Se isso acontecer, apagar a regra é seguro: nada quebra
funcionalmente sem ela.

Para trocar a paleta, edite os tokens em `estilo.py` e espelhe as quatro
cores base no `config.toml`.

## 2. Por que essas decisões técnicas

- **SQL puro em vez de dbt na v1**: para um primeiro projeto de portfólio,
  dois arquivos `.sql` bem comentados comunicam a mesma competência técnica
  que um projeto dbt, com muito menos fricção de setup para quem for avaliar
  o repositório. A migração para dbt (seção 3.1) é o passo natural para a v2.
- **Upsert na ingestão**: rodar o pipeline mais de uma vez é o caso comum
  (agendamento diário, reprocessamento). Um upsert idempotente evita
  duplicidade sem exigir lógica extra de "já rodei hoje?".
- **Testes sem dependência de rede/banco**: isso é o que permite o CI rodar
  em qualquer PR sem precisar provisionar Postgres no GitHub Actions —
  reduz a superfície de coisas que podem falhar no pipeline de CI.
- **Lockfile separado do requirements.txt**: `requirements.txt` declara a
  intenção (9 pacotes), `requirements.lock` registra a resolução (51). Sem
  essa separação, ou você não sabe o que realmente pediu, ou não sabe o que
  realmente instalou.
- **Bind nomeado (`:codigo`) no dashboard**: com uma engine SQLAlchemy, o
  pandas embrulha a query em `text()`, que só entende `:nome`. O estilo
  pyformat (`%(nome)s`) só funciona quando se passa uma conexão DBAPI crua.

## 3. Como estender

### 3.1 Migrar a transformação para dbt

```powershell
pip install dbt-postgres
dbt init analytics_dbt
```

Mova a lógica de `sql/02_create_analytics_table.sql` para um model
`models/serie_bcb_metrics.sql`, trocando `CREATE TABLE ... AS` pela lógica
pura de `SELECT` (o dbt cuida da materialização). Isso ganha versionamento
de schema, testes declarativos (`not_null`, `unique`) e documentação
automática (`dbt docs generate`) — bom argumento de venda para clientes que
já usam dbt.

### 3.2 Transformação incremental

Para séries com muito mais volume, troque o `DROP TABLE` por uma carga
incremental:

```sql
INSERT INTO analytics.serie_bcb_metrics (...)
SELECT ...
FROM raw.serie_bcb
WHERE data > (SELECT COALESCE(MAX(data), '1900-01-01') FROM analytics.serie_bcb_metrics);
```

Cuidado: como a média móvel de 30 dias olha para trás, uma carga puramente
incremental precisa reprocessar também os últimos ~30 dias já existentes
para manter as janelas corretas.

### 3.3 Orquestração

Hoje o pipeline é rodado manualmente (ou via CI, só para testes). Para
simular um ambiente de produção:
- **Windows Task Scheduler**: forma mais simples de agendar
  `ingestion` + `transform` diariamente sem infraestrutura extra.
- **Airflow / Prefect**: se o objetivo é mostrar competência de
  orquestração para clientes maiores, criar uma DAG com duas tasks
  (`extract_load` → `transform`) usando este mesmo código como base.

### 3.4 Outras fontes de dados

`ingestion/fetch_data.py` foi escrito para qualquer série numérica do SGS —
trocar `--serie` já basta. Para conectar a uma API totalmente diferente,
o padrão a seguir é: função `fetch_*()` que devolve um DataFrame validado,
função `ensure_*_table()` idempotente, função `load_*()` com upsert. Isso
mantém a mesma estrutura de raw → analytics → dashboard.

## 4. Testes de integração (opcional)

Os testes do repositório são unitários (mockados). Para um teste de
integração real contra o Postgres do `docker-compose.yml`:

```powershell
docker compose up -d
python -m ingestion.fetch_data --inicio 01/01/2025 --fim 31/12/2025
python -m transform.run_transform
python -c "from db.connection import get_engine; import pandas as pd; print(pd.read_sql('SELECT count(*) FROM analytics.serie_bcb_metrics', get_engine()))"
```

Se quiser formalizar isso como teste automatizado, use `pytest` com um
fixture que sobe/derruba o container (ex.: biblioteca `testcontainers-python`).

## 5. Como apresentar este projeto em uma proposta de freelance

Ao invés de "fiz um projeto de ETL", descreva o que o cliente ganha:

> "Construo pipelines que puxam dados de uma API ou planilha, carregam em um
> banco relacional, aplicam as regras de negócio em SQL versionado e entregam
> um dashboard — com testes automatizados e um pipeline de CI, para que o
> código continue funcionando conforme o projeto cresce."

Vale linkar o repositório e, se possível, um screenshot do dashboard e do
badge do GitHub Actions (verde) direto na proposta — é o tipo de sinal que
diferencia de um portfólio só de notebooks.
