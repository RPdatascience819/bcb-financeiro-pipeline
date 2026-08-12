"""
dashboard/app.py

Camada de apresentacao: le a tabela analytics.serie_bcb_metrics e exibe
um dashboard simples em Streamlit (KPIs, grafico de linha com media
movel e tabela detalhada com filtro de data).

Uso:
    streamlit run dashboard/app.py
"""

from __future__ import annotations

import os
import sys

import pandas as pd
import plotly.graph_objects as go
import streamlit as st
from sqlalchemy import text

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from db.connection import get_engine  # noqa: E402
from db.series_catalog import (  # noqa: E402
    DIARIA,
    SERIES,
    Serie,
    formata_valor,
    nome_da_serie,
    opcoes_do_seletor,
    rotulo_janela,
)

st.set_page_config(page_title="Indicadores Econômicos — BCB", layout="wide")


@st.cache_data(ttl=300)
def load_data(codigo_serie: int) -> pd.DataFrame:
    engine = get_engine()
    # Bind nomeado (:codigo) e nao pyformat (%(codigo)s): com uma engine
    # SQLAlchemy o pandas embrulha a query em text(), que so entende ":nome".
    query = text(
        """
        SELECT data, valor, media_movel_7d, media_movel_30d,
               volatilidade_30d, variacao_absoluta, variacao_percentual
        FROM analytics.serie_bcb_metrics
        WHERE codigo_serie = :codigo
        ORDER BY data
        """
    )
    df = pd.read_sql(query, engine, params={"codigo": codigo_serie}, parse_dates=["data"])
    return df


@st.cache_data(ttl=300)
def series_disponiveis() -> list[int]:
    """Codigos de serie que existem na tabela de metricas."""
    engine = get_engine()
    query = text("SELECT DISTINCT codigo_serie FROM analytics.serie_bcb_metrics")
    with engine.connect() as conn:
        codigos = [linha[0] for linha in conn.execute(query)]
    return opcoes_do_seletor(codigos)


def render_kpis(df: pd.DataFrame, serie: Serie) -> None:
    ultimo = df.iloc[-1]
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Último valor", formata_valor(ultimo["valor"], serie))
    col2.metric(
        "Variação vs. período anterior",
        f'{ultimo["variacao_percentual"]:.2f}%'.replace(".", ",")
        if pd.notna(ultimo["variacao_percentual"]) else "-",
    )
    col3.metric(
        f"Média móvel {rotulo_janela(serie.periodicidade, 7)}",
        formata_valor(ultimo["media_movel_7d"], serie),
    )
    col4.metric(
        f"Volatilidade {rotulo_janela(serie.periodicidade, 30)}",
        formata_valor(ultimo["volatilidade_30d"], serie)
        if pd.notna(ultimo["volatilidade_30d"]) else "-",
    )


def render_chart(df: pd.DataFrame, serie: Serie) -> None:
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=df["data"], y=df["valor"], name="Valor", mode="lines"))
    fig.add_trace(go.Scatter(
        x=df["data"], y=df["media_movel_7d"],
        name=f"Média móvel {rotulo_janela(serie.periodicidade, 7)}", mode="lines",
    ))
    fig.add_trace(go.Scatter(
        x=df["data"], y=df["media_movel_30d"],
        name=f"Média móvel {rotulo_janela(serie.periodicidade, 30)}", mode="lines",
    ))
    fig.update_layout(
        title=f"{serie.nome} — série histórica com médias móveis",
        xaxis_title="Data",
        yaxis_title=serie.unidade,
        legend_title="",
        height=450,
    )
    st.plotly_chart(fig, use_container_width=True)


def main() -> None:
    st.title("Indicadores Econômicos — Banco Central do Brasil")
    st.caption(
        "Séries do SGS/Banco Central, com médias móveis de 7 e 30 períodos, "
        "volatilidade e variação em relação ao período anterior."
    )

    codigos = series_disponiveis()
    if not codigos:
        st.warning(
            "Nenhuma série carregada ainda. Rode `.\\run_pipeline.ps1` para "
            "popular o banco e recarregue esta página."
        )
        return

    codigo_serie = st.sidebar.selectbox(
        "Série", codigos, format_func=nome_da_serie,
    )
    serie = SERIES.get(
        codigo_serie,
        Serie(nome_da_serie(codigo_serie), "", DIARIA, 4),
    )

    try:
        df = load_data(int(codigo_serie))
    except Exception as exc:  # noqa: BLE001 - exibicao amigavel de erro no dashboard
        st.error(
            "Não foi possível conectar ao banco. Verifique se o container está no ar "
            "(`docker compose ps`) e se o `.env` aponta para a porta certa."
        )
        st.exception(exc)
        return

    if df.empty:
        st.warning("Nenhum dado encontrado para essa série.")
        return

    min_data, max_data = df["data"].min().date(), df["data"].max().date()
    data_inicio, data_fim = st.sidebar.slider(
        "Período",
        min_value=min_data,
        max_value=max_data,
        value=(min_data, max_data),
        format="DD/MM/YYYY",
    )
    df_filtrado = df[(df["data"].dt.date >= data_inicio) & (df["data"].dt.date <= data_fim)]

    if df_filtrado.empty:
        st.warning("Nenhum dado no período selecionado.")
        return

    render_kpis(df_filtrado, serie)
    render_chart(df_filtrado, serie)

    with st.expander("Ver tabela detalhada"):
        st.dataframe(df_filtrado.sort_values("data", ascending=False), use_container_width=True)


if __name__ == "__main__":
    main()
