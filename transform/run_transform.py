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
