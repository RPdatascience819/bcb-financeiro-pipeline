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
