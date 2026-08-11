# bcb-financeiro-pipeline

[![CI](https://github.com/RPdatascience819/bcb-financeiro-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/RPdatascience819/bcb-financeiro-pipeline/actions/workflows/ci.yml)
[![Python 3.12](https://img.shields.io/badge/python-3.12-blue.svg)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

### Pipeline de Dados: API pÃºblica â†’ PostgreSQL â†’ Dashboard

Pipeline de engenharia de dados ponta a ponta, construÃ­do como peÃ§a de portfÃ³lio
para freelancing. Em vez de mais um notebook de exploraÃ§Ã£o, o objetivo aqui Ã©
demonstrar entrega: ingestÃ£o, transformaÃ§Ã£o, teste, execuÃ§Ã£o reprodutÃ­vel e
documentaÃ§Ã£o â€” o conjunto de competÃªncias que um cliente pequeno/mÃ©dio
realmente avalia ao contratar.

## Arquitetura

```
API pÃºblica (BCB / SGS)
        â”‚  Python (requests + pandas)
        â–¼
   raw.serie_bcb            (Postgres, dados brutos)
        â”‚  SQL (window functions)
        â–¼
analytics.serie_bcb_metrics  (Postgres, mÃ©tricas prontas para consumo)
        â”‚  Streamlit + Plotly
        â–¼
    Dashboard interativo
```

- **Fonte de dados**: [API SGS do Banco Central do Brasil](https://dadosabertos.bcb.gov.br/) â€”
  pÃºblica, sem autenticaÃ§Ã£o, retorna sÃ©ries temporais em JSON. Por padrÃ£o o
  projeto usa a sÃ©rie 1 (dÃ³lar comercial, venda, diÃ¡rio), mas qualquer cÃ³digo
  de sÃ©rie SGS funciona (ex.: 11 = Selic, 433 = IPCA).
- **Banco**: PostgreSQL 16, via Docker Compose.
- **TransformaÃ§Ã£o**: SQL puro com window functions (mÃ©dia mÃ³vel de 7 e 30
  dias, volatilidade, variaÃ§Ã£o diÃ¡ria). Fica fÃ¡cil de migrar para dbt depois
  (ver `docs/IMPLEMENTATION_GUIDE.md`).
- **ApresentaÃ§Ã£o**: Streamlit + Plotly, com KPIs, grÃ¡fico e tabela filtrÃ¡vel.
- **Qualidade**: testes automatizados com pytest (mockando a API, sem
  dependÃªncia de rede) e um workflow de CI no GitHub Actions.

## Estrutura do projeto

```
.
â”œâ”€â”€ ingestion/fetch_data.py       # extrai da API e carrega em raw.*
â”œâ”€â”€ transform/run_transform.py    # aplica os scripts sql/*.sql
â”œâ”€â”€ sql/
â”‚   â”œâ”€â”€ 01_create_raw_table.sql
â”‚   â””â”€â”€ 02_create_analytics_table.sql
â”œâ”€â”€ db/connection.py              # engine SQLAlchemy compartilhada
â”œâ”€â”€ dashboard/app.py              # app Streamlit
â”œâ”€â”€ tests/                        # testes unitÃ¡rios (pytest)
â”œâ”€â”€ .github/workflows/ci.yml      # lint + testes no push/PR
â”œâ”€â”€ docker-compose.yml            # Postgres local
â”œâ”€â”€ requirements.txt
â”œâ”€â”€ .env.example
â””â”€â”€ docs/IMPLEMENTATION_GUIDE.md  # passo a passo e como estender
```

## Como rodar

PrÃ©-requisitos: Python 3.11+, Docker Desktop, Git.

```powershell
# 1) subir o Postgres
Copy-Item .env.example .env
docker compose up -d

# 2) ambiente Python
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# 3) rodar o pipeline
python -m ingestion.fetch_data --ultimos 500
python -m transform.run_transform

# 4) subir o dashboard
streamlit run dashboard/app.py
```

Passo a passo detalhado, explicaÃ§Ã£o de cada camada e exemplos de extensÃ£o
(dbt, Airflow, outras fontes de dados) em `docs/IMPLEMENTATION_GUIDE.md`.

## Testes

```powershell
pytest tests/ -v
```

Os testes de ingestÃ£o mockam a chamada HTTP (nÃ£o dependem de rede) e os
testes de transformaÃ§Ã£o validam a estrutura dos scripts SQL â€” o suite
inteiro roda sem precisar de Postgres, o que Ã© o que o workflow de CI faz
a cada push.

## O que este projeto demonstra

| CompetÃªncia           | Onde                                              |
|------------------------|----------------------------------------------------|
| Consumo de API REST    | `ingestion/fetch_data.py`                          |
| Modelagem de dados     | `sql/01_create_raw_table.sql`, schemas raw/analytics |
| SQL avanÃ§ado           | `sql/02_create_analytics_table.sql` (window functions) |
| ORM / conexÃ£o a banco  | `db/connection.py` (SQLAlchemy)                    |
| Testes automatizados   | `tests/`                                           |
| CI/CD                  | `.github/workflows/ci.yml`                         |
| ContainerizaÃ§Ã£o        | `docker-compose.yml`                               |
| VisualizaÃ§Ã£o de dados  | `dashboard/app.py`                                 |
| DocumentaÃ§Ã£o           | este README + `docs/IMPLEMENTATION_GUIDE.md`       |

## LicenÃ§a

MIT â€” sinta-se livre para usar como base para o seu prÃ³prio projeto.
