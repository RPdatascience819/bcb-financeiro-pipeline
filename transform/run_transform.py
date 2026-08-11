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
    """Executa o arquivo .sql inteiro, em uma unica transacao.

    O arquivo vai ao driver de uma vez so, sem ser fatiado em ';': dividir
    o texto por ';' ignora que o separador tambem aparece dentro de
    comentarios, de strings literais e de corpos dollar-quoted -- e ali ele
    nao separa comando nenhum. O Postgres ja sabe onde cada comando termina.
    """
    engine = get_engine()
    sql_text = path.read_text(encoding="utf-8")

    logger.info("Executando %s", path.name)
    with engine.begin() as conn:
        conn.exec_driver_sql(sql_text)


def run() -> None:
    for path in load_sql_files():
        run_sql_file(path)
    logger.info("Transformacao concluida.")


if __name__ == "__main__":
    run()
