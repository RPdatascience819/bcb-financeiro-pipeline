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
import requests

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from db.series_catalog import SERIES  # noqa: E402
from ingestion.fetch_data import (  # noqa: E402
    IngestionError,
    build_url,
    fetch_series,
    parse_args,
    run_todas,
)

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
def test_fetch_series_resposta_nao_json_gera_erro(mock_get):
    """A API do BCB sinaliza throttling com HTTP 200 + pagina HTML de erro.

    O raise_for_status() nao pega (o status e 200) e o .json() estoura. Isso
    precisa virar IngestionError, e nao vazar um JSONDecodeError cru cuja
    mensagem aponta para o parsing e esconde a causa real.
    """
    mock_response = MagicMock()
    mock_response.raise_for_status.return_value = None
    mock_response.json.side_effect = requests.exceptions.JSONDecodeError(
        "Expecting value", "<html><title>Requisicao invalida!</title></html>", 0
    )
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


@patch("ingestion.fetch_data.run")
def test_run_todas_ingere_todas_as_series_do_catalogo(mock_run):
    mock_run.return_value = 10

    sucessos, falhas = run_todas(None, None, None, pausa=0)

    codigos_chamados = [chamada.args[0] for chamada in mock_run.call_args_list]
    assert codigos_chamados == list(SERIES)
    assert (sucessos, falhas) == (len(SERIES), 0)


@patch("ingestion.fetch_data.run")
def test_run_todas_continua_apos_falha_de_uma_serie(mock_run):
    """Uma serie bloqueada pelo throttle nao pode derrubar as outras duas."""

    def efeito(codigo, *args, **kwargs):
        if codigo == 11:
            raise IngestionError("bloqueado pelo limite de requisicoes")
        return 10

    mock_run.side_effect = efeito

    sucessos, falhas = run_todas(None, None, None, pausa=0)

    codigos_chamados = [chamada.args[0] for chamada in mock_run.call_args_list]
    assert codigos_chamados == list(SERIES), "deveria seguir para a serie seguinte"
    assert (sucessos, falhas) == (len(SERIES) - 1, 1)


def test_todas_e_serie_nao_podem_ser_usados_juntos():
    with pytest.raises(SystemExit):
        parse_args(["--todas", "--serie", "11"])
