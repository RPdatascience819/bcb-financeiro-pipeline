"""
dashboard/estilo.py

Aparencia do dashboard: tokens de cor, template do Plotly e o CSS pontual.

Existe para que o app.py responda "o que a tela mostra" enquanto este
arquivo responde "como ela se parece". Trocar a paleta inteira deve exigir
mexer aqui e em .streamlit/config.toml, e em lugar nenhum alem desses dois.
"""

from __future__ import annotations

import plotly.graph_objects as go
import streamlit as st

# Paleta Navy financeiro. Os quatro primeiros valores estao repetidos em
# .streamlit/config.toml -- o tema nativo do Streamlit so le TOML.
FUNDO = "#0B1B2B"
SUPERFICIE = "#12293F"
BORDA = "#1E3A52"
TEXTO = "#E8F1F8"
TEXTO_FRACO = "#8AA6BC"
ACENTO = "#22D3EE"

# Cor por serie, usada no grafico detalhado e no minigrafico do cartao.
COR_SERIE = {1: "#22D3EE", 11: "#A78BFA", 433: "#FCD34D"}
COR_SERIE_PADRAO = "#22D3EE"
COR_MM7 = "#7C99B3"
COR_MM30 = "#3E5D77"


def cor_da_serie(codigo: int) -> str:
    """Cor da serie. Codigo fora do catalogo cai no acento padrao."""
    return COR_SERIE.get(codigo, COR_SERIE_PADRAO)


# Fundo transparente para o grafico herdar a cor do cartao/pagina, grade
# discreta e texto de eixo no tom fraco: num painel escuro, a grade padrao
# do Plotly compete com os dados.
TEMPLATE_PLOTLY = go.layout.Template(
    layout={
        "paper_bgcolor": "rgba(0,0,0,0)",
        "plot_bgcolor": "rgba(0,0,0,0)",
        "font": {"color": TEXTO_FRACO, "size": 12},
        "xaxis": {"gridcolor": BORDA, "zeroline": False, "linecolor": BORDA},
        "yaxis": {"gridcolor": BORDA, "zeroline": False, "linecolor": BORDA},
        "legend": {"bgcolor": "rgba(0,0,0,0)"},
        "hoverlabel": {
            "bgcolor": SUPERFICIE,
            "bordercolor": BORDA,
            "font": {"color": TEXTO},
        },
    }
)

# Cada regra abaixo cobre algo que o tema nativo do Streamlit 1.36 nao
# alcanca, e leva um comentario dizendo o que faz: os seletores miram
# estrutura interna do Streamlit e podem desalinhar num upgrade. O conserto
# e apagar a regra -- nada quebra funcionalmente sem ela.
CSS = f"""
<style>
/* Da o tom Navy a borda dos cartoes e do expander.
   O testid e carimbado em TODO vertical block do Streamlit 1.36 (colunas,
   corpo da pagina, interior do expander) -- o border=True entra so como prop
   do emotion, sem atributo que distinga. Por isso aqui so entram propriedades
   inofensivas em quem nao tem borda: border-color e border-radius nao
   desenham nada sozinhos. Um `background` aqui pintaria as colunas e o corpo
   da pagina, e retangulos tintos sobrepostos e o que produz canto quadrado.
   O padding dos cartoes ja vem do proprio border=True. */
div[data-testid="stVerticalBlockBorderWrapper"] {{
    border-color: {BORDA};
    border-radius: 10px;
}}

/* O rotulo do KPI vem do mesmo tamanho do corpo do texto e compete com o
   valor. Menor, em maiusculas e espacado, ele vira etiqueta. */
div[data-testid="stMetricLabel"] p {{
    font-size: 0.72rem;
    font-weight: 700;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: {TEXTO_FRACO};
}}

/* O numero e a informacao principal da faixa: precisa dominar o cartao. */
div[data-testid="stMetricValue"] {{
    font-size: 1.75rem;
    font-weight: 700;
    letter-spacing: -0.02em;
}}

/* O Streamlit reserva ~6rem no topo. Num painel, a primeira linha util
   deve caber na tela sem rolagem. */
div.block-container {{
    padding-top: 2.5rem;
}}
</style>
"""


def aplica_estilo() -> None:
    """Injeta o CSS. Chamar uma vez, no inicio do main()."""
    st.markdown(CSS, unsafe_allow_html=True)
