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
    formata_variacao,
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


def test_formata_variacao_em_serie_de_moeda_usa_percentual():
    # Dolar de 5,1285 para 5,1639: +0,0354 em valor, +0,69% relativo.
    assert formata_variacao(0.0354, 0.6903, SERIES[1]) == "+0,69%"


def test_formata_variacao_em_serie_percentual_usa_pontos_percentuais():
    # IPCA de 0,16% para 0,07% ao mes. A coluna percentual marca -56,25%,
    # e "o IPCA caiu 56%" nao tem sentido economico: caiu 0,09 p.p.
    assert formata_variacao(-0.09, -56.25, SERIES[433]) == "-0,09 p.p."


def test_formata_variacao_zero_nao_leva_sinal():
    # Selic estavel entre dois dias. Com "+" o cartao sugeriria alta.
    assert formata_variacao(0.0, 0.0, SERIES[11]) == "0,0000 p.p."


def test_formata_variacao_sem_valor_anterior_devolve_none():
    # Primeira linha da serie: nao ha anterior, entao nao ha o que exibir.
    assert formata_variacao(float("nan"), float("nan"), SERIES[1]) is None


def test_formata_variacao_negativa_usa_hifen_ascii():
    # O st.metric decide a cor do delta olhando se o primeiro caractere e
    # um hifen ASCII. O menos tipografico (U+2212) quebraria a deteccao.
    resultado = formata_variacao(-0.0354, -0.6903, SERIES[1])
    assert resultado == "-0,69%"
    assert resultado.startswith("-")
