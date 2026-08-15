# bcb-financeiro-pipeline

[![CI](https://github.com/RPdatascience819/bcb-financeiro-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/RPdatascience819/bcb-financeiro-pipeline/actions/workflows/ci.yml)
[![Python 3.11](https://img.shields.io/badge/python-3.11-blue.svg)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

### Pipeline de Dados: API pública → PostgreSQL → Dashboard

Pipeline que coleta séries temporais econômicas da API pública do Banco Central
do Brasil (SGS), grava os dados brutos no PostgreSQL, calcula métricas
derivadas em SQL e as apresenta num dashboard Streamlit.

São três séries por padrão — dólar comercial, Selic e IPCA — e as métricas
calculadas são média móvel de 7 e 30 períodos, volatilidade e variação
percentual. Todo o fluxo roda com um comando (`run_pipeline.ps1`) e não
depende de credenciais: a API do BCB é aberta.

## Arquitetura

```
API pública (BCB / SGS)
        │  Python (requests + pandas)
        ▼
   raw.serie_bcb            (Postgres, dados brutos)
        │  SQL (window functions)
        ▼
analytics.serie_bcb_metrics  (Postgres, métricas prontas para consumo)
        │  Streamlit + Plotly
        ▼
    Dashboard interativo
```

- **Fonte de dados**: [API SGS do Banco Central do Brasil](https://dadosabertos.bcb.gov.br/) —
  pública, sem autenticação, retorna séries temporais em JSON. O projeto
  carrega três séries (dólar comercial, Selic e IPCA), definidas em
  `db/series_catalog.py`; qualquer outro código SGS funciona.
- **Banco**: PostgreSQL 16, via Docker Compose.
- **Transformação**: SQL puro com window functions (média móvel de 7 e 30
  períodos, volatilidade, variação). As janelas contam linhas, então numa
  série diária são dias e numa mensal, meses — o dashboard rotula conforme a
  periodicidade. Fica fácil de migrar para dbt depois
  (ver `docs/IMPLEMENTATION_GUIDE.md`).
- **Apresentação**: Streamlit + Plotly, com faixa dos três indicadores,
  gráfico detalhado da série escolhida e tabela filtrável. Tema próprio em
  `dashboard/estilo.py`.
- **Qualidade**: testes automatizados com pytest (mockando a API, sem
  dependência de rede) e um workflow de CI no GitHub Actions.

## Estrutura do projeto

```
.
├── ingestion/fetch_data.py       # extrai da API e carrega em raw.*
├── transform/run_transform.py    # aplica os scripts sql/*.sql
├── sql/
│   ├── 01_create_raw_table.sql
│   └── 02_create_analytics_table.sql
├── db/connection.py              # engine SQLAlchemy compartilhada
├── db/series_catalog.py          # séries conhecidas: nome, unidade, periodicidade
├── dashboard/app.py              # app Streamlit
├── dashboard/estilo.py           # tokens de cor, tema do Plotly e CSS
├── .streamlit/config.toml        # tema nativo do Streamlit
├── run_pipeline.ps1              # atalho: ingestão + transformação
├── tests/                        # testes unitários (pytest)
├── .github/workflows/ci.yml      # lint + testes no push/PR
├── docker-compose.yml            # Postgres local
├── requirements.txt              # dependências diretas (o que o projeto pede)
├── requirements.lock             # versões exatas resolvidas (o que o CI instala)
├── .env.example
└── docs/IMPLEMENTATION_GUIDE.md  # passo a passo e como estender
```

## Como rodar

Pré-requisitos: Python 3.11, Docker Desktop, Git.

```powershell
# 1) subir o Postgres
Copy-Item .env.example .env
docker compose up -d

# 2) ambiente Python
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.lock

# 3) rodar o pipeline (ingestão + transformação, últimos 2 anos)
.\run_pipeline.ps1

# 4) subir o dashboard
streamlit run dashboard/app.py
```

> **Porta 5432 ocupada?** Se você já tiver um PostgreSQL instalado nativamente,
> o `docker compose up -d` falha com erro de bind. Defina `POSTGRES_PORT=5433`
> no `.env` antes de subir — o Compose é parametrizado e nenhum YAML precisa
> ser editado.

O `run_pipeline.ps1` carrega todas as séries do catálogo
(`db/series_catalog.py`): dólar comercial, Selic e IPCA. No dashboard, o
seletor do sidebar troca entre elas pelo nome.

O `run_pipeline.ps1` aceita `-Anos` para mudar a janela (padrão: 2). Para rodar
cada camada separadamente, ou carregar uma série só:

```powershell
python -m ingestion.fetch_data --serie 1 --inicio 01/01/2024 --fim 31/12/2025
python -m transform.run_transform
```

> **Por que intervalo de datas e não `--ultimos N`?** O endpoint `/ultimos/{N}`
> da API do BCB aceita no máximo **20 valores** — acima disso devolve HTTP 400
> ("A quantidade máxima de valores deve ser 20"). E 20 pontos não preenchem a
> janela de 30 dias das métricas. O endpoint por intervalo aceita até 10 anos
> em séries diárias.

Passo a passo detalhado, explicação de cada camada e exemplos de extensão
(dbt, Airflow, outras fontes de dados) em `docs/IMPLEMENTATION_GUIDE.md`.

## Dependências: dois arquivos, dois papéis

- `requirements.txt` — as 9 dependências **diretas**, com a versão que o
  projeto pede. É o arquivo que você edita quando quer adicionar ou subir
  uma biblioteca.
- `requirements.lock` — as 51 versões **resolvidas**, incluindo todas as
  transitivas. É gerado (`pip freeze`), nunca editado à mão, e é o que o CI
  instala. Sem ele, quem clonasse o repositório meses depois receberia um
  `numpy` ou um `pyarrow` diferente do testado — e veria comportamentos que
  ninguém aqui jamais observou.

Para regenerar o lock depois de mexer no `requirements.txt`:

```powershell
.venv\Scripts\python.exe -m pip install -r requirements.txt
.venv\Scripts\python.exe -m pip freeze > requirements.lock
```

## Testes

```powershell
pytest tests/ -v
```

Os testes de ingestão mockam a chamada HTTP (não dependem de rede) e os
testes de transformação validam a estrutura dos scripts SQL — o suite
inteiro roda sem precisar de Postgres, o que é o que o workflow de CI faz
a cada push.

## Licença

MIT — veja [LICENSE](LICENSE).
