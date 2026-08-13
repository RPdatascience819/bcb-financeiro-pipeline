"""
db/series_catalog.py

Catalogo das series do SGS que o pipeline conhece: como cada uma se chama,
em que unidade e medida e com que periodicidade e publicada.

Fonte unica da verdade para duas perguntas:
  - quais series a ingestao carrega (flag --todas);
  - como o dashboard rotula e formata cada uma.

Modulo puro de proposito: nao importa banco, rede nem Streamlit, entao pode
ser usado tanto pela ingestao quanto pela apresentacao sem arrastar
dependencias de um lado para o outro.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

DIARIA = "diaria"
MENSAL = "mensal"


@dataclass(frozen=True)
class Serie:
    nome: str
    unidade: str
    periodicidade: str
    decimais: int


# As casas decimais sao por serie, nao por tipo: a Selic diaria vale
# 0,055131 e arredonda-la para 2 casas daria 0,06. A coluna no banco e
# NUMERIC(18, 6), entao a escolha aqui e so de exibicao.
SERIES: dict[int, Serie] = {
    1: Serie("Dólar comercial (venda)", "R$", DIARIA, 4),
    11: Serie("Selic", "% a.d.", DIARIA, 4),
    433: Serie("IPCA", "% a.m.", MENSAL, 2),
}


def nome_da_serie(codigo: int) -> str:
    """Nome de exibicao. Codigo fora do catalogo vira 'Série {codigo}'."""
    serie = SERIES.get(codigo)
    return serie.nome if serie is not None else f"Série {codigo}"


def rotulo_janela(periodicidade: str, n: int) -> str:
    """Descreve uma janela de N linhas na unidade de tempo da serie.

    As janelas do SQL sao definidas em ROWS, entao o que elas contam sao
    linhas. Em serie diaria uma linha e um dia; em serie mensal, um mes.
    """
    return f"{n} {'meses' if periodicidade == MENSAL else 'dias'}"


def formata_valor(valor: float, serie: Serie) -> str:
    """Formata o valor em pt-BR, com a unidade da serie no lugar certo."""
    numero = f"{valor:.{serie.decimais}f}".replace(".", ",")
    if serie.unidade.startswith("%"):
        return f"{numero} {serie.unidade}"
    return f"{serie.unidade} {numero}"


def formata_variacao(
    variacao_absoluta: float,
    variacao_percentual: float,
    serie: Serie,
) -> str | None:
    """Variacao pronta para o delta do st.metric. None se nao houver anterior.

    Series medidas em % exibem a variacao ABSOLUTA, em pontos percentuais.
    O IPCA indo de 0,16% para 0,07% ao mes rende -56,25% na coluna
    percentual, e "o IPCA caiu 56%" nao tem sentido economico: caiu
    0,09 ponto percentual. As demais series exibem a variacao relativa,
    onde ela e a leitura natural (o dolar subiu 0,69%).

    Devolve sem seta e sem cor -- quem desenha isso e o proprio st.metric,
    que decide a direcao olhando se o primeiro caractere e um hifen.
    """
    if serie.unidade.startswith("%"):
        valor, casas, sufixo = variacao_absoluta, serie.decimais, " p.p."
    else:
        valor, casas, sufixo = variacao_percentual, 2, "%"

    if valor is None:
        return None
    valor = float(valor)
    if math.isnan(valor):
        return None

    # O replace da virgula so pode tocar o numero: aplicado na string
    # inteira, " p.p." viraria " p,p,".
    valor_arredondado = round(valor, casas)
    numero = (f"{valor_arredondado:+.{casas}f}" if valor_arredondado else f"{abs(valor_arredondado):.{casas}f}").replace(".", ",")
    return f"{numero}{sufixo}"


def opcoes_do_seletor(codigos_no_banco: list[int]) -> list[int]:
    """Ordena os codigos presentes no banco pela ordem do catalogo.

    Codigos que o catalogo nao conhece vao para o final, ordenados, em vez
    de sumirem da lista -- some-los esconderia dados que existem.
    """
    conhecidos = [c for c in SERIES if c in codigos_no_banco]
    desconhecidos = sorted(c for c in codigos_no_banco if c not in SERIES)
    return conhecidos + desconhecidos
