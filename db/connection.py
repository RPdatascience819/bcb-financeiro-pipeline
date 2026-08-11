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
