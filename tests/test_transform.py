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
