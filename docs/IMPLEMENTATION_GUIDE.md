# Guia de implementaÃ§Ã£o

Este arquivo complementa o README: aqui estÃ¡ o passo a passo comentado, o
porquÃª de cada decisÃ£o tÃ©cnica e exemplos de como estender o projeto.

## 1. Passo a passo comentado

### 1.1 Subir o banco

```powershell
Copy-Item .env.example .env
docker compose up -d
docker compose ps        # confirma que o container estÃ¡ "healthy"
```

O `docker-compose.yml` sobe um Postgres 16 isolado, com os dados persistidos
em um volume nomeado (`pgdata`). Isso significa que vocÃª pode derrubar e
subir o container (`docker compose down` / `up`) sem perder dados â€” sÃ³
`docker compose down -v` apaga o volume.

### 1.2 Ambiente Python

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Se o PowerShell bloquear a ativaÃ§Ã£o do venv com erro de execution policy,
rode uma vez (como usuÃ¡rio, nÃ£o precisa ser admin):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### 1.3 IngestÃ£o

```powershell
python -m ingestion.fetch_data --ultimos 500
```

O que acontece:
1. `ensure_raw_table()` garante que `raw.serie_bcb` existe (idempotente).
2. `fetch_series()` chama a API do BCB e valida a resposta.
3. `load_raw()` faz um upsert (`INSERT ... ON CONFLICT DO UPDATE`), entÃ£o
   rodar o comando de novo nÃ£o duplica linhas â€” atualiza os valores mais
   recentes.

Alternativas de execuÃ§Ã£o:
```powershell
# intervalo de datas especÃ­fico (formato dd/MM/aaaa)
python -m ingestion.fetch_data --serie 1 --inicio 01/01/2024 --fim 31/12/2024

# outra sÃ©rie SGS (ex.: 11 = Selic)
python -m ingestion.fetch_data --serie 11 --ultimos 200
```

> A API do BCB passou a exigir filtro de data ou uso do endpoint
> `/ultimos/{N}` a partir de marÃ§o de 2025, e limita consultas por
> intervalo a no mÃ¡ximo 10 anos. O script jÃ¡ usa `/ultimos/{N}` como
> padrÃ£o para evitar esse problema.

### 1.4 TransformaÃ§Ã£o

```powershell
python -m transform.run_transform
```

Executa, em ordem, cada arquivo em `sql/`. Hoje sÃ£o dois:
- `01_create_raw_table.sql` â€” idempotente, documenta o contrato da camada raw.
- `02_create_analytics_table.sql` â€” recria `analytics.serie_bcb_metrics` do
  zero a cada execuÃ§Ã£o (`DROP` + `CREATE TABLE AS SELECT`). Para uma sÃ©rie
  diÃ¡ria isso Ã© instantÃ¢neo; para volumes maiores, veja a seÃ§Ã£o 3.2.

### 1.5 Dashboard

```powershell
streamlit run dashboard/app.py
```

Abre em `http://localhost:8501`. O sidebar permite trocar o cÃ³digo da sÃ©rie
e filtrar o perÃ­odo; os KPIs e o grÃ¡fico recalculam a partir do DataFrame
jÃ¡ filtrado.

## 2. Por que essas decisÃµes tÃ©cnicas

- **SQL puro em vez de dbt na v1**: para um primeiro projeto de portfÃ³lio,
  dois arquivos `.sql` bem comentados comunicam a mesma competÃªncia tÃ©cnica
  que um projeto dbt, com muito menos fricÃ§Ã£o de setup para quem for avaliar
  o repositÃ³rio. A migraÃ§Ã£o para dbt (seÃ§Ã£o 3.1) Ã© o passo natural para a v2.
- **Upsert na ingestÃ£o**: rodar o pipeline mais de uma vez Ã© o caso comum
  (agendamento diÃ¡rio, reprocessamento). Um upsert idempotente evita
  duplicidade sem exigir lÃ³gica extra de "jÃ¡ rodei hoje?".
- **Testes sem dependÃªncia de rede/banco**: isso Ã© o que permite o CI rodar
  em qualquer PR sem precisar provisionar Postgres no GitHub Actions â€”
  reduz a superfÃ­cie de coisas que podem falhar no pipeline de CI.

## 3. Como estender

### 3.1 Migrar a transformaÃ§Ã£o para dbt

```powershell
pip install dbt-postgres
dbt init analytics_dbt
```

Mova a lÃ³gica de `sql/02_create_analytics_table.sql` para um model
`models/serie_bcb_metrics.sql`, trocando `CREATE TABLE ... AS` pela lÃ³gica
pura de `SELECT` (o dbt cuida da materializaÃ§Ã£o). Isso ganha versionamento
de schema, testes declarativos (`not_null`, `unique`) e documentaÃ§Ã£o
automÃ¡tica (`dbt docs generate`) â€” bom argumento de venda para clientes que
jÃ¡ usam dbt.

### 3.2 TransformaÃ§Ã£o incremental

Para sÃ©ries com muito mais volume, troque o `DROP TABLE` por uma carga
incremental:

```sql
INSERT INTO analytics.serie_bcb_metrics (...)
SELECT ...
FROM raw.serie_bcb
WHERE data > (SELECT COALESCE(MAX(data), '1900-01-01') FROM analytics.serie_bcb_metrics);
```

Cuidado: como a mÃ©dia mÃ³vel de 30 dias olha para trÃ¡s, uma carga puramente
incremental precisa reprocessar tambÃ©m os Ãºltimos ~30 dias jÃ¡ existentes
para manter as janelas corretas.

### 3.3 OrquestraÃ§Ã£o

Hoje o pipeline Ã© rodado manualmente (ou via CI, sÃ³ para testes). Para
simular um ambiente de produÃ§Ã£o:
- **Windows Task Scheduler**: forma mais simples de agendar
  `ingestion` + `transform` diariamente sem infraestrutura extra.
- **Airflow / Prefect**: se o objetivo Ã© mostrar competÃªncia de
  orquestraÃ§Ã£o para clientes maiores, criar uma DAG com duas tasks
  (`extract_load` â†’ `transform`) usando este mesmo cÃ³digo como base.

### 3.4 Outras fontes de dados

`ingestion/fetch_data.py` foi escrito para qualquer sÃ©rie numÃ©rica do SGS â€”
trocar `--serie` jÃ¡ basta. Para conectar a uma API totalmente diferente,
o padrÃ£o a seguir Ã©: funÃ§Ã£o `fetch_*()` que devolve um DataFrame validado,
funÃ§Ã£o `ensure_*_table()` idempotente, funÃ§Ã£o `load_*()` com upsert. Isso
mantÃ©m a mesma estrutura de raw â†’ analytics â†’ dashboard.

## 4. Testes de integraÃ§Ã£o (opcional)

Os testes do repositÃ³rio sÃ£o unitÃ¡rios (mockados). Para um teste de
integraÃ§Ã£o real contra o Postgres do `docker-compose.yml`:

```powershell
docker compose up -d
python -m ingestion.fetch_data --ultimos 30
python -m transform.run_transform
python -c "from db.connection import get_engine; import pandas as pd; print(pd.read_sql('SELECT count(*) FROM analytics.serie_bcb_metrics', get_engine()))"
```

Se quiser formalizar isso como teste automatizado, use `pytest` com um
fixture que sobe/derruba o container (ex.: biblioteca `testcontainers-python`).

## 5. Como apresentar este projeto em uma proposta de freelance

Ao invÃ©s de "fiz um projeto de ETL", descreva o que o cliente ganha:

> "Construo pipelines que puxam dados de uma API ou planilha, carregam em um
> banco relacional, aplicam as regras de negÃ³cio em SQL versionado e entregam
> um dashboard â€” com testes automatizados e um pipeline de CI, para que o
> cÃ³digo continue funcionando conforme o projeto cresce."

Vale linkar o repositÃ³rio e, se possÃ­vel, um screenshot do dashboard e do
badge do GitHub Actions (verde) direto na proposta â€” Ã© o tipo de sinal que
diferencia de um portfÃ³lio sÃ³ de notebooks.
