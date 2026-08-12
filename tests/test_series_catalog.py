"""
tests/test_series_catalog.py

Testes do catalogo de series. Modulo puro: nao toca banco, rede nem Streamlit.
"""

from __future__ import annotations

import os
import sys

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from db.series_catalog import (  # noqa: E402
    DIARIA,
    MENSAL,
    SERIES,
    formata_valor,
    nome_da_serie,
    opcoes_do_seletor,
    rotulo_janela,
)


def test_catalogo_tem_as_tres_series_do_projeto():
    assert set(SERIES) == {1, 11, 433}


def test_rotulo_janela_em_serie_diaria_fala_em_dias():
    assert rotulo_janela(DIARIA, 7) == "7 dias"


def test_rotulo_janela_em_serie_mensal_fala_em_meses():
    # A janela do SQL e ROWS BETWEEN N PRECEDING: conta linhas, nao dias.
    # Numa serie mensal, 7 linhas sao 7 meses -- o rotulo precisa dizer isso.
    assert rotulo_janela(MENSAL, 7) == "7 meses"


def test_formata_valor_poe_a_moeda_antes_do_numero():
    assert formata_valor(5.1285, SERIES[1]) == "R$ 5,1285"


def test_formata_valor_poe_o_percentual_depois_do_numero():
    assert formata_valor(0.24, SERIES[433]) == "0,24 % a.m."


def test_formata_valor_respeita_as_casas_decimais_da_serie():
    # A Selic diaria vale 0,055131. Com 2 casas viraria 0,06 e perderia
    # a informacao, por isso o catalogo define 4 casas para ela.
    assert formata_valor(0.055131, SERIES[11]) == "0,0551 % a.d."


def test_nome_da_serie_conhecida_vem_do_catalogo():
    assert nome_da_serie(11) == "Selic"


def test_nome_da_serie_desconhecida_cai_no_codigo():
    assert nome_da_serie(999) == "Série 999"


def test_opcoes_do_seletor_seguem_a_ordem_do_catalogo():
    assert opcoes_do_seletor([433, 1, 11]) == [1, 11, 433]


def test_opcoes_do_seletor_poem_codigo_desconhecido_no_final():
    assert opcoes_do_seletor([999, 1]) == [1, 999]


def test_opcoes_do_seletor_ignora_serie_do_catalogo_ausente_no_banco():
    assert opcoes_do_seletor([1]) == [1]
