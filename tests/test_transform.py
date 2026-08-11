"""
tests/test_transform.py

Testes leves da camada de transformacao. Nao exigem Postgres: validam
que os scripts SQL existem, sao validos como texto (sem comandos vazios)
e que a tabela analytics esperada e criada com as colunas certas.
Para um teste de integracao completo (com Postgres real), ver
docs/IMPLEMENTATION_GUIDE.md, secao "Testes de integracao".
"""

from __future__ import annotations

import os
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from transform.run_transform import run_sql_file  # noqa: E402

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


@patch("transform.run_transform.get_engine")
def test_run_sql_file_envia_o_arquivo_inteiro_sem_fatiar(mock_get_engine, tmp_path):
    """Um ';' dentro de um comentario nao pode fatiar o script.

    Fatiar em ';' quebra o arquivo no meio do comentario: sobra um pedaco so
    de comentario (que o Postgres recusa como query vazia) e o resto da frase
    vira lixo sintatico grudado no comando seguinte.
    """
    conteudo = (
        "-- comentario com ; no meio, e a frase continua depois dele\n"
        "CREATE TABLE t (id INTEGER);\n"
    )
    arquivo = tmp_path / "99_teste.sql"
    arquivo.write_text(conteudo, encoding="utf-8")

    conn = MagicMock()
    mock_get_engine.return_value.begin.return_value.__enter__.return_value = conn

    run_sql_file(arquivo)

    enviados = [chamada.args[0] for chamada in conn.exec_driver_sql.call_args_list]
    assert enviados == [conteudo], "O arquivo deve chegar ao driver inteiro, em uma unica chamada"


def test_analytics_table_declara_todas_as_colunas_esperadas():
    analytics_sql = (SQL_DIR / "02_create_analytics_table.sql").read_text(encoding="utf-8")
    for coluna in EXPECTED_COLUMNS:
        assert coluna in analytics_sql, f"Coluna '{coluna}' nao encontrada no script de analytics"
