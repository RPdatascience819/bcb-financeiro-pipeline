<#
.SYNOPSIS
    Cria, do zero, o projeto de portfolio "Pipeline: API publica -> PostgreSQL -> Dashboard".

.DESCRIPTION
    Este script gera toda a estrutura de pastas e arquivos do projeto (codigo,
    SQL, testes, CI, documentacao) na pasta indicada, cria um ambiente virtual
    Python, instala as dependencias e (opcionalmente) inicializa um repositorio
    Git com o primeiro commit.

    Depois de rodar este script, siga o README.md gerado dentro do projeto
    (secao "Como rodar") ou docs/IMPLEMENTATION_GUIDE.md para o passo a passo
    completo.

.PARAMETER ProjectPath
    Pasta onde o projeto sera criado. Default: ".\bcb-financeiro-pipeline"
    Use "." para gerar na pasta atual.

.PARAMETER SkipVenv
    Se informado, nao cria o ambiente virtual nem instala dependencias.

.PARAMETER SkipGit
    Se informado, nao roda "git init" nem o commit inicial.

.EXAMPLE
    .\create_project.ps1

.EXAMPLE
    .\create_project.ps1 -ProjectPath C:\dev\bcb-financeiro-pipeline -SkipGit
#>

[CmdletBinding()]
param(
    [string]$ProjectPath = ".\bcb-financeiro-pipeline",
    [switch]$SkipVenv,
    [switch]$SkipGit
)

$ErrorActionPreference = "Stop"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Write-FileContent {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        # AllowEmptyString e obrigatorio: parametros Mandatory aplicam um
        # ValidateNotNullOrEmpty implicito, e os __init__.py sao vazios.
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )
    $fullPath = Join-Path $ProjectPath $RelativePath
    $parent = Split-Path $fullPath -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    # O .NET resolve caminhos relativos contra o diretorio do processo, que nao
    # acompanha o Set-Location do PowerShell -- por isso absolutizamos aqui.
    $absolutePath = Join-Path (Resolve-Path $parent).Path (Split-Path $fullPath -Leaf)
    # Remove-se a quebra de linha inicial que o here-string literal adiciona.
    $Content = $Content.TrimStart("`r`n")
    # UTF-8 SEM BOM: "Set-Content -Encoding utf8" no Windows PowerShell 5.1
    # grava com BOM, o que quebra parsers de YAML e leitores de .env.
    [System.IO.File]::WriteAllText($absolutePath, $Content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  criado: $RelativePath"
}

Write-Step "Criando estrutura do projeto em '$ProjectPath'"
if (Test-Path $ProjectPath) {
    Write-Warning "A pasta '$ProjectPath' ja existe. Arquivos existentes com o mesmo nome serao sobrescritos."
} else {
    New-Item -ItemType Directory -Path $ProjectPath -Force | Out-Null
}

$directories = @(
    "ingestion", "transform", "sql", "db", "dashboard", "tests",
    "docs", ".github\workflows"
)
foreach ($dir in $directories) {
    New-Item -ItemType Directory -Path (Join-Path $ProjectPath $dir) -Force | Out-Null
}

Write-FileContent -RelativePath 'README.md' -Content @'
# bcb-financeiro-pipeline

[![CI](https://github.com/RPdatascience819/bcb-financeiro-pipeline/actions/workflows/ci.yml/badge.svg)](https://github.com/RPdatascience819/bcb-financeiro-pipeline/actions/workflows/ci.yml)
[![Python 3.12](https://img.shields.io/badge/python-3.12-blue.svg)](https://www.python.org/)
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
├── requirements.txt
├── .env.example
└── docs/IMPLEMENTATION_GUIDE.md  # passo a passo e como estender
```

## Como rodar

Pré-requisitos: Python 3.11+, Docker Desktop, Git.

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

Passo a passo detalhado, explicação de cada camada e exemplos de extensão
(dbt, Airflow, outras fontes de dados) em `docs/IMPLEMENTATION_GUIDE.md`.

## Testes

```powershell
pytest tests/ -v
```

Os testes de ingestão mockam a chamada HTTP (não dependem de rede) e os
testes de transformação validam a estrutura dos scripts SQL — o suite
inteiro roda sem precisar de Postgres, o que é o que o workflow de CI faz
a cada push.

## O que este projeto demonstra

| Competência           | Onde                                              |
|------------------------|----------------------------------------------------|
| Consumo de API REST    | `ingestion/fetch_data.py`                          |
| Modelagem de dados     | `sql/01_create_raw_table.sql`, schemas raw/analytics |
| SQL avançado           | `sql/02_create_analytics_table.sql` (window functions) |
| ORM / conexão a banco  | `db/connection.py` (SQLAlchemy)                    |
| Testes automatizados   | `tests/`                                           |
| CI/CD                  | `.github/workflows/ci.yml`                         |
| Containerização        | `docker-compose.yml`                               |
| Visualização de dados  | `dashboard/app.py`                                 |
| Documentação           | este README + `docs/IMPLEMENTATION_GUIDE.md`       |

## Licença

MIT — sinta-se livre para usar como base para o seu próprio projeto.

'@

Write-FileContent -RelativePath 'LICENSE' -Content @'
MIT License

Copyright (c) 2026 Ronaldo Philippe

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

'@

Write-FileContent -RelativePath '.env.example' -Content @'
# Copie este arquivo para ".env" e ajuste os valores.
# O ".env" real nunca deve ser commitado (ja esta no .gitignore).

POSTGRES_USER=portfolio_user
POSTGRES_PASSWORD=change_me
POSTGRES_DB=portfolio_pipeline
POSTGRES_HOST=localhost
POSTGRES_PORT=5432

# Serie SGS do Banco Central (default 1 = dolar comercial, venda, diario).
# Outras series uteis: 11 = Selic, 433 = IPCA.
BCB_SERIES_CODE=1

# Deixe em branco para usar --ultimos no lugar de um intervalo de datas.
BCB_START_DATE=
BCB_END_DATE=

'@

Write-FileContent -RelativePath '.gitignore' -Content @'
# Python
__pycache__/
*.pyc
.pytest_cache/
.ruff_cache/
*.egg-info/

# Ambiente virtual
.venv/
venv/

# Segredos
.env

# Postgres / Docker
pgdata/

# Streamlit
.streamlit/

# IDE
.vscode/*
!.vscode/extensions.json

# SO
.DS_Store
Thumbs.db

'@

Write-FileContent -RelativePath 'requirements.txt' -Content @'
requests==2.32.3
pandas==2.2.2
SQLAlchemy==2.0.30
psycopg2-binary==2.9.9
python-dotenv==1.0.1
streamlit==1.36.0
plotly==5.22.0
pytest==8.2.2
ruff==0.5.0

'@

Write-FileContent -RelativePath 'docker-compose.yml' -Content @'
services:
  postgres:
    image: postgres:16
    container_name: portfolio_postgres
    restart: unless-stopped
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-portfolio_user}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-change_me}
      POSTGRES_DB: ${POSTGRES_DB:-portfolio_pipeline}
    ports:
      - "${POSTGRES_PORT:-5432}:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-portfolio_user}"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pgdata:

'@

Write-FileContent -RelativePath 'db/connection.py' -Content @'
"""
db/connection.py

Centraliza a criacao da engine SQLAlchemy usada por todo o pipeline
(ingestion, transform e dashboard), lendo a configuracao de um arquivo
.env na raiz do projeto.

Mantido em um unico lugar para que qualquer mudanca de credenciais ou
de driver nao exija alterar mais de um arquivo.
"""

from __future__ import annotations

import os
from functools import lru_cache

from dotenv import load_dotenv
from sqlalchemy import Engine, create_engine

load_dotenv()


def _build_url() -> str:
    user = os.environ.get("POSTGRES_USER", "portfolio_user")
    password = os.environ.get("POSTGRES_PASSWORD", "change_me")
    host = os.environ.get("POSTGRES_HOST", "localhost")
    port = os.environ.get("POSTGRES_PORT", "5432")
    db = os.environ.get("POSTGRES_DB", "portfolio_pipeline")
    return f"postgresql+psycopg2://{user}:{password}@{host}:{port}/{db}"


@lru_cache(maxsize=1)
def get_engine() -> Engine:
    """Retorna uma engine SQLAlchemy reutilizavel (singleton por processo)."""
    url = _build_url()
    return create_engine(url, pool_pre_ping=True, future=True)


if __name__ == "__main__":
    engine = get_engine()
    with engine.connect() as conn:
        print("Conexao OK:", conn.engine.url.render_as_string(hide_password=True))

'@

Write-FileContent -RelativePath 'ingestion/fetch_data.py' -Content @'
"""
ingestion/fetch_data.py

Camada de ingestao: busca uma serie temporal publica da API do
Banco Central do Brasil (SGS - Sistema Gerenciador de Series Temporais)
e grava os dados brutos (raw) no Postgres, sem transformacao.

Endpoint publico, sem autenticacao:
  https://api.bcb.gov.br/dados/serie/bcdata.sgs.{codigo}/dados?formato=json
  https://api.bcb.gov.br/dados/serie/bcdata.sgs.{codigo}/dados/ultimos/{n}?formato=json

Uso:
    python -m ingestion.fetch_data --serie 1 --ultimos 500
    python -m ingestion.fetch_data --serie 1 --inicio 01/01/2023 --fim 31/12/2023
"""

from __future__ import annotations

import argparse
import logging
import os
import sys
from datetime import datetime, timezone

import pandas as pd
import requests
from sqlalchemy import text

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from db.connection import get_engine  # noqa: E402

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger("ingestion")

BASE_URL = "https://api.bcb.gov.br/dados/serie/bcdata.sgs.{codigo}/dados"
RAW_SCHEMA = "raw"
RAW_TABLE = "serie_bcb"
REQUEST_TIMEOUT = 30


class IngestionError(RuntimeError):
    """Erro especifico da camada de ingestao (rede, parsing ou API)."""


def build_url(codigo: int, inicio: str | None, fim: str | None, ultimos: int | None) -> str:
    base = BASE_URL.format(codigo=codigo)
    if ultimos:
        return f"{base}/ultimos/{ultimos}?formato=json"
    params = ["formato=json"]
    if inicio:
        params.append(f"dataInicial={inicio}")
    if fim:
        params.append(f"dataFinal={fim}")
    return f"{base}?{'&'.join(params)}"


def fetch_series(
    codigo: int,
    inicio: str | None = None,
    fim: str | None = None,
    ultimos: int | None = None,
) -> pd.DataFrame:
    """Busca a serie na API do BCB e devolve um DataFrame padronizado.

    Levanta IngestionError em caso de falha de rede ou resposta invalida,
    para que o chamador decida como tratar (retry, alerta, etc.).
    """
    url = build_url(codigo, inicio, fim, ultimos)
    logger.info("Buscando serie %s em %s", codigo, url)

    try:
        response = requests.get(url, timeout=REQUEST_TIMEOUT)
        response.raise_for_status()
    except requests.RequestException as exc:
        raise IngestionError(f"Falha ao consultar a API do BCB: {exc}") from exc

    payload = response.json()
    if not isinstance(payload, list) or not payload:
        raise IngestionError(f"Resposta vazia ou em formato inesperado para a serie {codigo}")

    df = pd.DataFrame(payload)
    if not {"data", "valor"}.issubset(df.columns):
        raise IngestionError(f"Colunas inesperadas na resposta: {df.columns.tolist()}")

    df["data"] = pd.to_datetime(df["data"], format="%d/%m/%Y")
    df["valor"] = pd.to_numeric(df["valor"], errors="coerce")
    df = df.dropna(subset=["valor"])

    df["codigo_serie"] = codigo
    df["carregado_em"] = datetime.now(timezone.utc)

    return df[["codigo_serie", "data", "valor", "carregado_em"]]


def ensure_raw_table() -> None:
    """Garante que o schema/tabela raw existam antes da carga."""
    ddl = f"""
    CREATE SCHEMA IF NOT EXISTS {RAW_SCHEMA};
    CREATE TABLE IF NOT EXISTS {RAW_SCHEMA}.{RAW_TABLE} (
        codigo_serie INTEGER NOT NULL,
        data DATE NOT NULL,
        valor NUMERIC(18, 6) NOT NULL,
        carregado_em TIMESTAMPTZ NOT NULL,
        PRIMARY KEY (codigo_serie, data)
    );
    """
    engine = get_engine()
    with engine.begin() as conn:
        for statement in ddl.strip().split(";"):
            statement = statement.strip()
            if statement:
                conn.execute(text(statement))


def load_raw(df: pd.DataFrame) -> int:
    """Faz upsert dos registros na tabela raw. Retorna quantidade de linhas."""
    if df.empty:
        logger.warning("DataFrame vazio, nada para carregar.")
        return 0

    engine = get_engine()
    insert_sql = text(
        f"""
        INSERT INTO {RAW_SCHEMA}.{RAW_TABLE} (codigo_serie, data, valor, carregado_em)
        VALUES (:codigo_serie, :data, :valor, :carregado_em)
        ON CONFLICT (codigo_serie, data)
        DO UPDATE SET valor = EXCLUDED.valor, carregado_em = EXCLUDED.carregado_em;
        """
    )
    records = df.to_dict(orient="records")
    with engine.begin() as conn:
        conn.execute(insert_sql, records)

    logger.info("Carregadas/atualizadas %d linhas em %s.%s", len(records), RAW_SCHEMA, RAW_TABLE)
    return len(records)


def run(codigo: int, inicio: str | None, fim: str | None, ultimos: int | None) -> int:
    ensure_raw_table()
    df = fetch_series(codigo, inicio, fim, ultimos)
    return load_raw(df)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Ingestao de series temporais do BCB (SGS).")
    parser.add_argument("--serie", type=int, default=int(os.environ.get("BCB_SERIES_CODE", 1)),
                         help="Codigo da serie SGS (default: 1 = dolar comercial, venda).")
    parser.add_argument("--inicio", type=str, default=os.environ.get("BCB_START_DATE") or None,
                         help="Data inicial no formato dd/MM/aaaa.")
    parser.add_argument("--fim", type=str, default=os.environ.get("BCB_END_DATE") or None,
                         help="Data final no formato dd/MM/aaaa.")
    parser.add_argument("--ultimos", type=int, default=None,
                         help="Se informado, ignora --inicio/--fim e busca os N valores mais recentes.")
    return parser.parse_args(argv)


if __name__ == "__main__":
    args = parse_args()
    total = run(args.serie, args.inicio, args.fim, args.ultimos)
    logger.info("Ingestao concluida: %d linhas processadas.", total)

'@

Write-FileContent -RelativePath 'transform/run_transform.py' -Content @'
"""
transform/run_transform.py

Camada de transformacao: aplica os scripts SQL em sql/*.sql, em ordem,
sobre o banco Postgres. Separado da ingestao de proposito -- em um
pipeline real, isso permite rodar "extract/load" e "transform" em
horarios ou orquestradores diferentes (ex.: Airflow, cron, GitHub Actions).

Uso:
    python -m transform.run_transform
"""

from __future__ import annotations

import logging
import os
import sys
from pathlib import Path

from sqlalchemy import text

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from db.connection import get_engine  # noqa: E402

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s | %(levelname)s | %(message)s",
)
logger = logging.getLogger("transform")

SQL_DIR = Path(__file__).resolve().parent.parent / "sql"


def load_sql_files() -> list[Path]:
    files = sorted(SQL_DIR.glob("*.sql"))
    if not files:
        raise FileNotFoundError(f"Nenhum arquivo .sql encontrado em {SQL_DIR}")
    return files


def run_sql_file(path: Path) -> None:
    engine = get_engine()
    sql_text = path.read_text(encoding="utf-8")
    statements = [s.strip() for s in sql_text.split(";") if s.strip()]

    logger.info("Executando %s (%d comandos)", path.name, len(statements))
    with engine.begin() as conn:
        for statement in statements:
            conn.execute(text(statement))


def run() -> None:
    for path in load_sql_files():
        run_sql_file(path)
    logger.info("Transformacao concluida.")


if __name__ == "__main__":
    run()

'@

Write-FileContent -RelativePath 'sql/01_create_raw_table.sql' -Content @'
-- 01_create_raw_table.sql
-- Camada RAW: espelha a resposta da API do BCB praticamente sem tratamento.
-- Esta tabela tambem eh criada automaticamente pelo ingestion/fetch_data.py,
-- mas o script fica aqui para deixar o contrato de dados explicito e versionado.

CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.serie_bcb (
    codigo_serie   INTEGER        NOT NULL,
    data           DATE           NOT NULL,
    valor          NUMERIC(18, 6) NOT NULL,
    carregado_em   TIMESTAMPTZ    NOT NULL,
    PRIMARY KEY (codigo_serie, data)
);

COMMENT ON TABLE raw.serie_bcb IS
    'Dados brutos de series temporais do BCB (SGS), carregados via ingestion/fetch_data.py.';

'@

Write-FileContent -RelativePath 'sql/02_create_analytics_table.sql' -Content @'
-- 02_create_analytics_table.sql
-- Camada ANALYTICS: transforma a serie bruta em uma tabela pronta para
-- consumo no dashboard, com media movel, variacao diaria e variacao
-- percentual em relacao ao dia anterior.
--
-- Executado por transform/run_transform.py apos cada carga incremental.
-- Usa DROP + CREATE (materializacao completa) porque o volume de uma
-- serie temporal diaria do BCB e pequeno; para volumes maiores, trocar
-- por uma estrategia incremental (INSERT ... WHERE data > ultima_data).

CREATE SCHEMA IF NOT EXISTS analytics;

DROP TABLE IF EXISTS analytics.serie_bcb_metrics;

CREATE TABLE analytics.serie_bcb_metrics AS
WITH base AS (
    SELECT
        codigo_serie,
        data,
        valor
    FROM raw.serie_bcb
),
com_janela AS (
    SELECT
        codigo_serie,
        data,
        valor,
        LAG(valor) OVER (PARTITION BY codigo_serie ORDER BY data)        AS valor_dia_anterior,
        AVG(valor) OVER (
            PARTITION BY codigo_serie
            ORDER BY data
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )                                                                AS media_movel_7d,
        AVG(valor) OVER (
            PARTITION BY codigo_serie
            ORDER BY data
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        )                                                                AS media_movel_30d,
        STDDEV_SAMP(valor) OVER (
            PARTITION BY codigo_serie
            ORDER BY data
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        )                                                                AS volatilidade_30d
    FROM base
)
SELECT
    codigo_serie,
    data,
    valor,
    ROUND(media_movel_7d, 4)  AS media_movel_7d,
    ROUND(media_movel_30d, 4) AS media_movel_30d,
    ROUND(volatilidade_30d, 4) AS volatilidade_30d,
    ROUND(valor - valor_dia_anterior, 4) AS variacao_absoluta,
    CASE
        WHEN valor_dia_anterior IS NULL OR valor_dia_anterior = 0 THEN NULL
        ELSE ROUND(100.0 * (valor - valor_dia_anterior) / valor_dia_anterior, 4)
    END AS variacao_percentual
FROM com_janela
ORDER BY codigo_serie, data;

ALTER TABLE analytics.serie_bcb_metrics ADD PRIMARY KEY (codigo_serie, data);

COMMENT ON TABLE analytics.serie_bcb_metrics IS
    'Serie do BCB com medias moveis (7d/30d), volatilidade e variacao diaria, pronta para o dashboard.';

'@

Write-FileContent -RelativePath 'dashboard/app.py' -Content @'
"""
dashboard/app.py

Camada de apresentacao: le a tabela analytics.serie_bcb_metrics e exibe
um dashboard simples em Streamlit (KPIs, grafico de linha com media
movel e tabela detalhada com filtro de data).

Uso:
    streamlit run dashboard/app.py
"""

from __future__ import annotations

import os
import sys

import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from sqlalchemy import text

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from db.connection import get_engine  # noqa: E402

st.set_page_config(page_title="Pipeline Portfolio - Series BCB", layout="wide")


@st.cache_data(ttl=300)
def load_data(codigo_serie: int) -> pd.DataFrame:
    engine = get_engine()
    # Bind nomeado (:codigo) e nao pyformat (%(codigo)s): com uma engine
    # SQLAlchemy o pandas embrulha a query em text(), que so entende ":nome".
    query = text(
        """
        SELECT data, valor, media_movel_7d, media_movel_30d,
               volatilidade_30d, variacao_absoluta, variacao_percentual
        FROM analytics.serie_bcb_metrics
        WHERE codigo_serie = :codigo
        ORDER BY data
        """
    )
    df = pd.read_sql(query, engine, params={"codigo": codigo_serie}, parse_dates=["data"])
    return df


def render_kpis(df: pd.DataFrame) -> None:
    ultimo = df.iloc[-1]
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Ultimo valor", f'{ultimo["valor"]:.4f}')
    col2.metric(
        "Variacao vs. dia anterior",
        f'{ultimo["variacao_percentual"]:.2f}%' if pd.notna(ultimo["variacao_percentual"]) else "-",
    )
    col3.metric("Media movel 7d", f'{ultimo["media_movel_7d"]:.4f}')
    col4.metric("Volatilidade 30d", f'{ultimo["volatilidade_30d"]:.4f}' if pd.notna(ultimo["volatilidade_30d"]) else "-")


def render_chart(df: pd.DataFrame) -> None:
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=df["data"], y=df["valor"], name="Valor", mode="lines"))
    fig.add_trace(go.Scatter(x=df["data"], y=df["media_movel_7d"], name="Media movel 7d", mode="lines"))
    fig.add_trace(go.Scatter(x=df["data"], y=df["media_movel_30d"], name="Media movel 30d", mode="lines"))
    fig.update_layout(
        title="Serie historica com medias moveis",
        xaxis_title="Data",
        yaxis_title="Valor",
        legend_title="",
        height=450,
    )
    st.plotly_chart(fig, use_container_width=True)


def main() -> None:
    st.title("Pipeline de dados: API -> PostgreSQL -> Dashboard")
    st.caption(
        "Fonte: API SGS do Banco Central do Brasil. "
        "Ingestao em Python, transformacao em SQL, visualizacao em Streamlit."
    )

    codigo_serie = st.sidebar.number_input("Codigo da serie SGS", min_value=1, value=1, step=1)

    try:
        df = load_data(int(codigo_serie))
    except Exception as exc:  # noqa: BLE001 - exibicao amigavel de erro no dashboard
        st.error(
            "Nao foi possivel conectar ao banco ou a serie ainda nao foi carregada. "
            "Rode a ingestao e a transformacao antes de abrir o dashboard."
        )
        st.exception(exc)
        return

    if df.empty:
        st.warning("Nenhum dado encontrado para essa serie. Rode a ingestao primeiro.")
        return

    min_data, max_data = df["data"].min().date(), df["data"].max().date()
    data_inicio, data_fim = st.sidebar.slider(
        "Periodo",
        min_value=min_data,
        max_value=max_data,
        value=(min_data, max_data),
        format="DD/MM/YYYY",
    )
    df_filtrado = df[(df["data"].dt.date >= data_inicio) & (df["data"].dt.date <= data_fim)]

    if df_filtrado.empty:
        st.warning("Nenhum dado no periodo selecionado.")
        return

    render_kpis(df_filtrado)
    render_chart(df_filtrado)

    with st.expander("Ver tabela detalhada"):
        st.dataframe(df_filtrado.sort_values("data", ascending=False), use_container_width=True)


if __name__ == "__main__":
    main()

'@

Write-FileContent -RelativePath 'tests/test_ingestion.py' -Content @'
"""
tests/test_ingestion.py

Testes unitarios da camada de ingestao. Nao dependem de banco de dados
nem de rede: a chamada HTTP e mockada, entao rodam em qualquer ambiente
(inclusive CI) sem Postgres nem Docker.
"""

from __future__ import annotations

import os
import sys
from unittest.mock import MagicMock, patch

import pandas as pd
import pytest

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from ingestion.fetch_data import IngestionError, build_url, fetch_series  # noqa: E402

FAKE_PAYLOAD = [
    {"data": "01/01/2024", "valor": "4.8523"},
    {"data": "02/01/2024", "valor": "4.9011"},
    {"data": "03/01/2024", "valor": "4.8790"},
]


def test_build_url_com_ultimos():
    url = build_url(codigo=1, inicio=None, fim=None, ultimos=10)
    assert url == "https://api.bcb.gov.br/dados/serie/bcdata.sgs.1/dados/ultimos/10?formato=json"


def test_build_url_com_periodo():
    url = build_url(codigo=1, inicio="01/01/2024", fim="31/01/2024", ultimos=None)
    assert "dataInicial=01/01/2024" in url
    assert "dataFinal=31/01/2024" in url


@patch("ingestion.fetch_data.requests.get")
def test_fetch_series_parseia_payload_valido(mock_get):
    mock_response = MagicMock()
    mock_response.json.return_value = FAKE_PAYLOAD
    mock_response.raise_for_status.return_value = None
    mock_get.return_value = mock_response

    df = fetch_series(codigo=1, ultimos=3)

    assert list(df.columns) == ["codigo_serie", "data", "valor", "carregado_em"]
    assert len(df) == 3
    assert df["valor"].dtype.kind == "f"
    assert pd.api.types.is_datetime64_any_dtype(df["data"])


@patch("ingestion.fetch_data.requests.get")
def test_fetch_series_payload_vazio_gera_erro(mock_get):
    mock_response = MagicMock()
    mock_response.json.return_value = []
    mock_response.raise_for_status.return_value = None
    mock_get.return_value = mock_response

    with pytest.raises(IngestionError):
        fetch_series(codigo=1, ultimos=3)


@patch("ingestion.fetch_data.requests.get")
def test_fetch_series_colunas_inesperadas_gera_erro(mock_get):
    mock_response = MagicMock()
    mock_response.json.return_value = [{"foo": "bar"}]
    mock_response.raise_for_status.return_value = None
    mock_get.return_value = mock_response

    with pytest.raises(IngestionError):
        fetch_series(codigo=1, ultimos=3)

'@

Write-FileContent -RelativePath 'tests/test_transform.py' -Content @'
"""
tests/test_transform.py

Testes leves da camada de transformacao. Nao exigem Postgres: validam
que os scripts SQL existem, sao validos como texto (sem comandos vazios)
e que a tabela analytics esperada e criada com as colunas certas.
Para um teste de integracao completo (com Postgres real), ver
docs/IMPLEMENTATION_GUIDE.md, secao "Testes de integracao".
"""

from __future__ import annotations

from pathlib import Path

SQL_DIR = Path(__file__).resolve().parent.parent / "sql"

EXPECTED_COLUMNS = {
    "codigo_serie",
    "data",
    "valor",
    "media_movel_7d",
    "media_movel_30d",
    "volatilidade_30d",
    "variacao_absoluta",
    "variacao_percentual",
}


def test_sql_dir_existe_e_tem_arquivos():
    assert SQL_DIR.exists()
    arquivos = sorted(SQL_DIR.glob("*.sql"))
    assert len(arquivos) >= 2, "Esperado ao menos raw e analytics"


def test_scripts_sql_nao_estao_vazios_nem_tem_comandos_em_branco():
    for path in SQL_DIR.glob("*.sql"):
        conteudo = path.read_text(encoding="utf-8")
        assert conteudo.strip(), f"{path.name} esta vazio"
        comandos = [c.strip() for c in conteudo.split(";")]
        # remove comentarios simples antes de validar
        comandos_validos = [
            c for c in comandos
            if c and not all(line.strip().startswith("--") for line in c.splitlines() if line.strip())
        ]
        assert comandos_validos, f"{path.name} nao parece ter comandos SQL executaveis"


def test_analytics_table_declara_todas_as_colunas_esperadas():
    analytics_sql = (SQL_DIR / "02_create_analytics_table.sql").read_text(encoding="utf-8")
    for coluna in EXPECTED_COLUMNS:
        assert coluna in analytics_sql, f"Coluna '{coluna}' nao encontrada no script de analytics"

'@

Write-FileContent -RelativePath '.github/workflows/ci.yml' -Content @'
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v5
        with:
          python-version: "3.12"
          cache: "pip"

      - name: Install dependencies
        run: pip install -r requirements.txt

      - name: Lint (ruff)
        run: ruff check .

      - name: Run tests
        run: pytest tests/ -v

'@

Write-FileContent -RelativePath 'docs/IMPLEMENTATION_GUIDE.md' -Content @'
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

### 1.2 Ambiente Python

```powershell
python -m venv .venv
.venv\Scripts\Activate.ps1
pip install -r requirements.txt
```

Se o PowerShell bloquear a ativação do venv com erro de execution policy,
rode uma vez (como usuário, não precisa ser admin):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

### 1.3 Ingestão

```powershell
python -m ingestion.fetch_data --ultimos 500
```

O que acontece:
1. `ensure_raw_table()` garante que `raw.serie_bcb` existe (idempotente).
2. `fetch_series()` chama a API do BCB e valida a resposta.
3. `load_raw()` faz um upsert (`INSERT ... ON CONFLICT DO UPDATE`), então
   rodar o comando de novo não duplica linhas — atualiza os valores mais
   recentes.

Alternativas de execução:
```powershell
# intervalo de datas específico (formato dd/MM/aaaa)
python -m ingestion.fetch_data --serie 1 --inicio 01/01/2024 --fim 31/12/2024

# outra série SGS (ex.: 11 = Selic)
python -m ingestion.fetch_data --serie 11 --ultimos 200
```

> A API do BCB passou a exigir filtro de data ou uso do endpoint
> `/ultimos/{N}` a partir de março de 2025, e limita consultas por
> intervalo a no máximo 10 anos. O script já usa `/ultimos/{N}` como
> padrão para evitar esse problema.

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

Abre em `http://localhost:8501`. O sidebar permite trocar o código da série
e filtrar o período; os KPIs e o gráfico recalculam a partir do DataFrame
já filtrado.

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
python -m ingestion.fetch_data --ultimos 30
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

'@


# Arquivos __init__.py para os pacotes Python internos (db, ingestion, transform)
foreach ($pkg in @("db", "ingestion", "transform")) {
    Write-FileContent -RelativePath "$pkg\__init__.py" -Content ""
}

Write-Step "Gerando o helper run_pipeline.ps1 dentro do projeto"
Write-FileContent -RelativePath "run_pipeline.ps1" -Content @'
# run_pipeline.ps1
# Atalho: roda ingestao + transformacao em sequencia.
# Uso: .\run_pipeline.ps1 [-Ultimos 500]

param([int]$Ultimos = 500)

$ErrorActionPreference = "Stop"

Write-Host "==> Ingestao (ultimos $Ultimos valores)" -ForegroundColor Cyan
python -m ingestion.fetch_data --ultimos $Ultimos

Write-Host "==> Transformacao" -ForegroundColor Cyan
python -m transform.run_transform

Write-Host ""
Write-Host "Pipeline concluido. Para abrir o dashboard:" -ForegroundColor Green
Write-Host "  streamlit run dashboard/app.py"
'@

if (-not $SkipVenv) {
    Write-Step "Criando ambiente virtual Python (.venv)"
    Push-Location $ProjectPath
    try {
        python -m venv .venv
        Write-Host "  ambiente virtual criado."

        # Chamar o python.exe do venv diretamente, em vez de ativar: o
        # "& .\.venv\Scripts\Activate.ps1" roda em escopo filho e o PATH que
        # ele define morre com o script -- o pip seguinte seria o global.
        $venvPython = ".\.venv\Scripts\python.exe"
        Write-Step "Instalando dependencias (requirements.txt)"
        & $venvPython -m pip install --upgrade pip | Out-Null
        & $venvPython -m pip install -r requirements.txt
        Write-Host "  dependencias instaladas." -ForegroundColor Green
    }
    catch {
        Write-Warning "Nao foi possivel criar o venv/instalar dependencias automaticamente: $_"
        Write-Warning "Rode manualmente dentro da pasta do projeto:"
        Write-Warning "  python -m venv .venv; .venv\Scripts\python.exe -m pip install -r requirements.txt"
    }
    finally {
        Pop-Location
    }
} else {
    Write-Host "  (SkipVenv) ambiente virtual nao foi criado."
}

if (-not $SkipGit) {
    Write-Step "Inicializando repositorio Git"
    Push-Location $ProjectPath
    try {
        if (-not (Test-Path ".git")) {
            git init | Out-Null
        }
        git add -A
        git commit -m "chore: scaffold do pipeline API -> PostgreSQL -> dashboard" | Out-Null
        Write-Host "  repositorio git inicializado com o commit inicial." -ForegroundColor Green
    }
    catch {
        Write-Warning "Nao foi possivel inicializar o git automaticamente: $_"
    }
    finally {
        Pop-Location
    }
} else {
    Write-Host "  (SkipGit) git init nao foi executado."
}

Write-Step "Projeto criado com sucesso"
Write-Host ""
Write-Host "Proximos passos:" -ForegroundColor Green
Write-Host "  cd '$ProjectPath'"
Write-Host "  Copy-Item .env.example .env"
Write-Host "  docker compose up -d"
if ($SkipVenv) {
    Write-Host "  python -m venv .venv; .venv\Scripts\python.exe -m pip install -r requirements.txt"
}
Write-Host "  .\run_pipeline.ps1"
Write-Host "  streamlit run dashboard/app.py"
Write-Host ""
Write-Host "Leia README.md e docs/IMPLEMENTATION_GUIDE.md para o passo a passo completo." -ForegroundColor Yellow
