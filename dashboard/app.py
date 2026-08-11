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


def render_kpis(df: pd.DataFrame) -> None:
    ultimo = df.iloc[-1]
    col1, col2, col3, col4 = st.columns(4)
    col1.metric("Último valor", f'{ultimo["valor"]:.4f}')
    col2.metric(
        "Variação vs. dia anterior",
        f'{ultimo["variacao_percentual"]:.2f}%' if pd.notna(ultimo["variacao_percentual"]) else "-",
    )
    col3.metric("Média móvel 7d", f'{ultimo["media_movel_7d"]:.4f}')
    col4.metric("Volatilidade 30d", f'{ultimo["volatilidade_30d"]:.4f}' if pd.notna(ultimo["volatilidade_30d"]) else "-")


def render_chart(df: pd.DataFrame) -> None:
    fig = go.Figure()
    fig.add_trace(go.Scatter(x=df["data"], y=df["valor"], name="Valor", mode="lines"))
    fig.add_trace(go.Scatter(x=df["data"], y=df["media_movel_7d"], name="Média móvel 7d", mode="lines"))
    fig.add_trace(go.Scatter(x=df["data"], y=df["media_movel_30d"], name="Média móvel 30d", mode="lines"))
    fig.update_layout(
        title="Série histórica com médias móveis",
        xaxis_title="Data",
        yaxis_title="Valor",
        legend_title="",
        height=450,
    )
    st.plotly_chart(fig, use_container_width=True)


def main() -> None:
    st.title("Indicadores Econômicos — Banco Central do Brasil")
    st.caption(
        "Valores diários das séries do SGS/Banco Central, com médias móveis "
        "de 7 e 30 dias, volatilidade e variação diária."
    )

    codigo_serie = st.sidebar.number_input("Código da série SGS", min_value=1, value=1, step=1)

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
        st.warning("Nenhum dado encontrado para essa série. Rode a ingestão primeiro.")
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

    render_kpis(df_filtrado)
    render_chart(df_filtrado)

    with st.expander("Ver tabela detalhada"):
        st.dataframe(df_filtrado.sort_values("data", ascending=False), use_container_width=True)


if __name__ == "__main__":
    main()
