# bcb-financeiro-pipeline

[![CI](https://github.com/RPdatascience819/bcb-financeiro-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/RPdatascience819/bcb-financeiro-pipeline/actions/workflows/ci.yml)
[![Python 3.11](https://img.shields.io/badge/python-3.11-blue.svg)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

### Pipeline de Dados: API pública → PostgreSQL → Dashboard

Pipeline de engenharia de dados ponta a ponta, construído como peça de portfólio
para freelancing. Em vez de mais um notebook de exploração, o objetivo aqui é
demonstrar entrega: ingestão, transformação, teste, execução reprodutível e
documentação — o conjunto de competências que um cliente pequeno/médio
realmente avalia ao contratar.

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
  pública, sem autenticação, retorna séries temporais em JSON. Por padrão o
  projeto usa a série 1 (dólar comercial, venda, diário), mas qualquer código
  de série SGS funciona (ex.: 11 = Selic, 433 = IPCA).
- **Banco**: PostgreSQL 16, via Docker Compose.
- **Transformação**: SQL puro com window functions (média móvel de 7 e 30
  dias, volatilidade, variação diária). Fica fácil de migrar para dbt depois
  (ver `docs/IMPLEMENTATION_GUIDE.md`).
- **Apresentação**: Streamlit + Plotly, com KPIs, gráfico e tabela filtrável.
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
├── dashboard/app.py              # app Streamlit
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

# 3) rodar o pipeline
python -m ingestion.fetch_data --ultimos 500
python -m transform.run_transform

# 4) subir o dashboard
streamlit run dashboard/app.py
```

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

## O que este projeto demonstra

| Competência            | Onde                                                 |
|------------------------|------------------------------------------------------|
| Consumo de API REST    | `ingestion/fetch_data.py`                            |
| Modelagem de dados     | `sql/01_create_raw_table.sql`, schemas raw/analytics  |
| SQL avançado           | `sql/02_create_analytics_table.sql` (window functions)|
| ORM / conexão a banco  | `db/connection.py` (SQLAlchemy)                      |
| Testes automatizados   | `tests/`                                             |
| CI/CD                  | `.github/workflows/ci.yml`                           |
| Build reprodutível     | `requirements.lock`                                  |
| Containerização        | `docker-compose.yml`                                 |
| Visualização de dados  | `dashboard/app.py`                                   |
| Documentação           | este README + `docs/IMPLEMENTATION_GUIDE.md`         |

## Licença

MIT — sinta-se livre para usar como base para o seu próprio projeto.
