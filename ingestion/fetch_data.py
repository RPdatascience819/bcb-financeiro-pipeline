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
