# Redesign Visual do Dashboard — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transformar o dashboard num painel que se explica sozinho num screenshot: os três indicadores sempre visíveis no topo, paleta Navy financeiro e variação em unidade economicamente correta.

**Architecture:** Um módulo novo (`dashboard/estilo.py`) concentra tudo que é aparência — tokens de cor, template do Plotly e o CSS pontual —, deixando o `app.py` responsável apenas por estrutura e dados. O tema base vem de `.streamlit/config.toml`. O catálogo ganha uma única função pura, `formata_variacao`, que é a parte testável do trabalho. Nenhuma consulta nova ao banco: a faixa de indicadores reusa a `load_data` já cacheada.

**Tech Stack:** Python 3.11, Streamlit 1.36, Plotly 5.22, pandas 2.2, pytest, ruff, PostgreSQL em container.

## Global Constraints

- Interpretador: sempre `.venv\Scripts\python.exe` (o `python` puro pode ser o global).
- A suíte de testes **não pode** exigir banco nem rede — o CI roda sem Postgres.
- Arquivos gravados em UTF-8 **sem BOM**.
- Todo texto visível ao usuário em pt-BR **com acentuação**.
- `ruff check .` e `pytest` precisam passar antes de cada commit.
- `db/series_catalog.py` é um **módulo puro**: não importa pandas, Streamlit, banco nem rede. `formata_variacao` usa apenas a stdlib.
- Sinal negativo é **hífen ASCII** (`-`), nunca o menos tipográfico `−`: o `st.metric` decide a cor do delta olhando o primeiro caractere.
- Tokens de cor exatos: fundo `#0B1B2B`, superfície `#12293F`, borda `#1E3A52`, texto `#E8F1F8`, texto fraco `#8AA6BC`, acento `#22D3EE`. Séries: dólar `#22D3EE`, Selic `#A78BFA`, IPCA `#FCD34D`. Médias móveis: 7 `#7C99B3`, 30 `#3E5D77`.
- Suíte atual: 24 testes. Ao final deste plano: **29**.

---

### Task 1: `formata_variacao` no catálogo

Única parte testável do redesign. Módulo puro: sem banco, sem rede, sem Streamlit.

**Files:**
- Modify: `db/series_catalog.py`
- Test: `tests/test_series_catalog.py`

**Interfaces:**
- Consumes: `Serie` e `SERIES`, já existentes no módulo.
- Produces: `formata_variacao(variacao_absoluta: float, variacao_percentual: float, serie: Serie) -> str | None`

- [ ] **Step 1: Write the failing test**

Adicionar ao final de `tests/test_series_catalog.py`:

```python
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
```

E completar o import no topo do arquivo:

```python
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
```

(substitui o bloco de import existente, acrescentando `formata_variacao`)

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv\Scripts\python.exe -m pytest tests/test_series_catalog.py -v`
Expected: FAIL na coleta — `ImportError: cannot import name 'formata_variacao' from 'db.series_catalog'`

- [ ] **Step 3: Write minimal implementation**

Em `db/series_catalog.py`, acrescentar `import math` logo abaixo de `from __future__ import annotations`:

```python
from __future__ import annotations

import math
from dataclasses import dataclass
```

E adicionar a função logo após `formata_valor`:

```python
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
    numero = (f"{valor:+.{casas}f}" if valor else f"{valor:.{casas}f}").replace(".", ",")
    return f"{numero}{sufixo}"
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv\Scripts\python.exe -m pytest tests/test_series_catalog.py -v`
Expected: PASS — 16 testes (11 antigos + 5 novos)

- [ ] **Step 5: Run the whole suite and the linter**

Run: `.venv\Scripts\python.exe -m pytest -q` → 29 testes passando
Run: `.venv\Scripts\python.exe -m ruff check .` → `All checks passed!`

- [ ] **Step 6: Commit**

```bash
git add db/series_catalog.py tests/test_series_catalog.py
git commit -m "feat(catalogo): variacao em p.p. para series medidas em %

O IPCA indo de 0,16% para 0,07% ao mes rende -56,25% na coluna
variacao_percentual. 'O IPCA caiu 56%' nao tem sentido economico -- a
leitura correta e -0,09 ponto percentual.

A regra sai da mesma condicao que o formata_valor ja usa (unidade
comecada em %), sem campo novo no catalogo. A funcao devolve sem seta e
sem cor: quem desenha isso e o st.metric."
```

---

### Task 2: Tema Navy — `config.toml` e `dashboard/estilo.py`

Não muda comportamento nenhum: só aparência. A verificação é visual, no Step 5.

**Files:**
- Create: `.streamlit/config.toml`
- Create: `dashboard/estilo.py`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `FUNDO`, `SUPERFICIE`, `BORDA`, `TEXTO`, `TEXTO_FRACO`, `ACENTO` — `str`
  - `COR_MM7: str`, `COR_MM30: str`
  - `cor_da_serie(codigo: int) -> str`
  - `TEMPLATE_PLOTLY: go.layout.Template`
  - `aplica_estilo() -> None`

- [ ] **Step 1: Criar o tema nativo**

Create `.streamlit/config.toml`:

```toml
# Tema do dashboard. Os valores repetem os tokens de dashboard/estilo.py
# porque o tema nativo do Streamlit so le TOML -- ao mudar um, mude o outro.
[theme]
base = "dark"
primaryColor = "#22D3EE"
backgroundColor = "#0B1B2B"
secondaryBackgroundColor = "#12293F"
textColor = "#E8F1F8"
font = "sans serif"
```

- [ ] **Step 2: Confirmar que o arquivo será versionado**

Run: `git check-ignore -v .streamlit/config.toml`
Expected: **sem saída** e código de saída 1 (nada o ignora). Se algo o ignorar, acrescentar `!.streamlit/config.toml` ao `.gitignore` — sem o tema versionado, quem clonar o projeto vê o Streamlit padrão.

- [ ] **Step 3: Criar o módulo de aparência**

Create `dashboard/estilo.py`:

```python
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
/* st.container(border=True) desenha so a borda; a superficie mais clara
   que separa o cartao do fundo vem daqui. */
div[data-testid="stVerticalBlockBorderWrapper"] {{
    background: {SUPERFICIE};
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
```

- [ ] **Step 4: Ligar o estilo no app**

Em `dashboard/app.py`, acrescentar o import logo abaixo do bloco que importa de `db.series_catalog`:

```python
from dashboard.estilo import aplica_estilo  # noqa: E402
```

**Importe só `aplica_estilo` nesta task.** As demais exportações do `estilo.py` só passam a ser usadas nas Tasks 3 e 4; trazê-las agora faria o `ruff` acusar `F401 imported but unused` e o Step 6 falharia.

E como **primeira linha** de `main()`, antes do `st.title`:

```python
def main() -> None:
    aplica_estilo()
    st.title("Indicadores Econômicos — Banco Central do Brasil")
```

- [ ] **Step 5: Verificar rodando o app**

Run: `.venv\Scripts\python.exe -m streamlit run dashboard/app.py --server.headless true`

Conferir em `http://localhost:8501`:
1. o fundo é azul-marinho escuro e o texto claro;
2. a sidebar aparece **mais clara** que o corpo — é o esperado, não um erro: o `secondaryBackgroundColor` pinta as duas coisas;
3. o topo da página não tem espaço vazio exagerado.

**Se o CSS dos KPIs não surtir efeito**, abrir o DevTools do navegador, inspecionar um `st.metric` e conferir o `data-testid` real desta versão do Streamlit; ajustar o seletor no `estilo.py`. Os testids usados aqui (`stMetricLabel`, `stMetricValue`, `stVerticalBlockBorderWrapper`) são internos e podem divergir.

- [ ] **Step 6: Run the whole suite and the linter**

Run: `.venv\Scripts\python.exe -m pytest -q` → 29 testes passando
Run: `.venv\Scripts\python.exe -m ruff check .` → `All checks passed!`

- [ ] **Step 7: Commit**

```bash
git add .streamlit/config.toml dashboard/estilo.py dashboard/app.py
git commit -m "feat(dashboard): tema Navy financeiro

Concentra aparencia em dashboard/estilo.py: tokens de cor, template do
Plotly e o CSS pontual. O app.py passa a responder so 'o que a tela
mostra'; trocar a paleta inteira mexe em estilo.py e config.toml, e em
mais lugar nenhum.

O CSS cobre apenas o que o tema nativo do Streamlit 1.36 nao alcanca --
o st.metric so ganhou border na 1.44 -- e cada regra leva um comentario
dizendo o que faz, porque os seletores miram estrutura interna."
```

---

### Task 3: Faixa de indicadores com minigráficos

O coração do redesign: os três indicadores sempre visíveis. Sem teste unitário — a lógica testável (`formata_variacao`, `formata_valor`) foi coberta na Task 1, e exercitar widgets de Streamlit exigiria máquina desproporcional ao ganho. A verificação é executar o app.

**Files:**
- Modify: `dashboard/app.py`

**Interfaces:**
- Consumes: `formata_variacao` (Task 1); `TEMPLATE_PLOTLY`, `cor_da_serie` (Task 2).
- Produces:
  - `JANELA_SPARKLINE: int = 90`
  - `serie_do_codigo(codigo: int) -> Serie`
  - `render_sparkline(df: pd.DataFrame, codigo: int) -> None`
  - `render_faixa_indicadores(codigos: list[int]) -> None`

- [ ] **Step 1: Completar os imports**

Em `dashboard/app.py`, o bloco que importa de `db.series_catalog` passa a incluir `formata_variacao`:

```python
from db.series_catalog import (  # noqa: E402
    DIARIA,
    SERIES,
    Serie,
    formata_valor,
    formata_variacao,
    nome_da_serie,
    opcoes_do_seletor,
    rotulo_janela,
)
```

E a linha `from dashboard.estilo import aplica_estilo` da Task 2 vira:

```python
from dashboard.estilo import (  # noqa: E402
    TEMPLATE_PLOTLY,
    aplica_estilo,
    cor_da_serie,
)
```

(`COR_MM7` e `COR_MM30` ficam para a Task 4, que é onde passam a ser usados — importá-los aqui faria o `ruff` acusar `F401`.)

- [ ] **Step 2: Extrair o fallback de série para uma função**

Hoje esse fallback está embutido no `main()`. A Task 3 passa a precisar dele em dois lugares, então vira função. Adicionar logo após `series_disponiveis`:

```python
JANELA_SPARKLINE = 90


def serie_do_codigo(codigo: int) -> Serie:
    """Serie do catalogo, com fallback para codigo presente no banco mas
    ausente do catalogo -- some-lo esconderia dados que existem."""
    return SERIES.get(codigo, Serie(nome_da_serie(codigo), "", DIARIA, 4))
```

- [ ] **Step 3: Escrever o minigráfico**

Adicionar após `serie_do_codigo`:

```python
def render_sparkline(df: pd.DataFrame, codigo: int) -> None:
    """Minigrafico de tendencia recente: sem eixos, sem legenda, sem hover.

    Mostra os ultimos JANELA_SPARKLINE registros, nao a serie inteira: dois
    anos de serie diaria num espaco de 48px viram um borrao. Numa serie
    mensal os 24 registros existentes cabem todos.
    """
    recorte = df.tail(JANELA_SPARKLINE)
    fig = go.Figure(
        go.Scatter(
            x=recorte["data"],
            y=recorte["valor"],
            mode="lines",
            line={"color": cor_da_serie(codigo), "width": 2},
            hoverinfo="skip",
        )
    )
    fig.update_layout(
        template=TEMPLATE_PLOTLY,
        height=48,
        margin={"l": 0, "r": 0, "t": 0, "b": 0},
        xaxis={"visible": False},
        yaxis={"visible": False},
        showlegend=False,
    )
    st.plotly_chart(fig, use_container_width=True, config={"displayModeBar": False})
```

- [ ] **Step 4: Escrever a faixa de indicadores**

Adicionar após `render_sparkline`:

```python
def render_faixa_indicadores(codigos: list[int]) -> None:
    """Faixa superior: cada indicador carregado, no seu valor mais recente.

    Nao obedece ao filtro de periodo de proposito. Um cartao rotulado como
    valor atual exibindo um numero de dois anos atras seria uma afirmacao
    falsa -- por isso a data de referencia aparece em cada cartao.

    Nao abre consulta nova: load_data ja e cacheada por 5 minutos.
    """
    for coluna, codigo in zip(st.columns(len(codigos)), codigos):
        df = load_data(codigo)
        if df.empty:
            continue
        serie = serie_do_codigo(codigo)
        ultimo = df.iloc[-1]
        variacao = formata_variacao(
            ultimo["variacao_absoluta"], ultimo["variacao_percentual"], serie
        )
        with coluna.container(border=True):
            st.metric(
                nome_da_serie(codigo),
                formata_valor(ultimo["valor"], serie),
                delta=variacao,
                # Sem valor anterior o delta some. Variacao exatamente zero
                # e a unica que comeca com "0" (as positivas levam "+"), e
                # precisa ficar neutra: o padrao do Streamlit pintaria de
                # verde um indicador que nao subiu.
                delta_color="off" if variacao and variacao.startswith("0") else "normal",
            )
            st.caption(f"em {ultimo['data'].strftime('%d/%m/%Y')}")
            render_sparkline(df, codigo)
```

- [ ] **Step 5: Chamar a faixa no `main()` e simplificar o seletor**

Em `main()`, substituir o bloco que vai do `codigo_serie = st.sidebar.selectbox(` até o fecha-parênteses do `serie = SERIES.get(...)` por:

```python
    render_faixa_indicadores(codigos)
    st.divider()

    codigo_serie = st.sidebar.selectbox(
        "Série", codigos, format_func=nome_da_serie,
    )
    serie = serie_do_codigo(codigo_serie)
```

- [ ] **Step 6: Verificar rodando o app**

Run: `.venv\Scripts\python.exe -m streamlit run dashboard/app.py --server.headless true`

Conferir em `http://localhost:8501`:
1. três cartões no topo, com moldura e fundo mais claro que a página;
2. dólar mostra `R$ 5,1639` com delta `+0,69%` em verde;
3. IPCA mostra `0,07 % a.m.` com delta `-0,09 p.p.` em vermelho — **e não −56,25%**;
4. Selic estável mostra `0,0000 p.p.` em cinza, não em verde;
5. cada cartão traz a data de referência e um minigráfico;
6. trocar a série no seletor **não** altera a faixa, só o gráfico de baixo.

- [ ] **Step 7: Run the whole suite and the linter**

Run: `.venv\Scripts\python.exe -m pytest -q` → 29 testes passando
Run: `.venv\Scripts\python.exe -m ruff check .` → `All checks passed!`

- [ ] **Step 8: Commit**

```bash
git add dashboard/app.py
git commit -m "feat(dashboard): faixa com os tres indicadores no topo

O painel mostrava um indicador por vez: um screenshot exibia o dolar e
nada mais, dando a impressao de um app de serie unica quando o pipeline
carrega tres.

A faixa nao obedece ao filtro de periodo, de proposito -- um cartao
rotulado como valor atual exibindo um numero de dois anos atras seria
falso. Por isso cada cartao traz a data de referencia.

Nao abre consulta nova: load_data ja e cacheada por 5 minutos."
```

---

### Task 4: Gráfico, tabela e sidebar no tema — e documentação

Fecha o redesign: o gráfico detalhado e a tabela passam a seguir a paleta, a sidebar ganha rodapé e os docs registram o que mudou.

**Files:**
- Modify: `dashboard/app.py`
- Modify: `README.md`
- Modify: `docs/IMPLEMENTATION_GUIDE.md`

**Interfaces:**
- Consumes: `TEMPLATE_PLOTLY`, `cor_da_serie`, `COR_MM7`, `COR_MM30` (Task 2); `serie_do_codigo` (Task 3).
- Produces: nada consumido por outras tasks.

- [ ] **Step 1: Encolher o `render_kpis` para o que a faixa não mostra**

> **Divergência consciente da spec.** A spec diz que "`render_chart` e `render_kpis` passam a usar `TEMPLATE_PLOTLY` e as cores por série", mas `render_kpis` não desenha gráfico nenhum — foi imprecisão do texto. O problema real só apareceu ao escrever o código: com a faixa da Task 3 exibindo último valor e variação, manter os quatro KPIs antigos **duplicaria os dois primeiros** na mesma tela. Removê-los todos perderia médias móveis e volatilidade, que não estão em lugar nenhum. A saída é encolher para as três métricas que a faixa não cobre.

Substituir `render_kpis` inteira por:

```python
def render_kpis(df: pd.DataFrame, serie: Serie) -> None:
    """Metricas da serie selecionada que a faixa do topo nao mostra.

    Ultimo valor e variacao ficaram na faixa; repeti-los aqui seria ruido.
    """
    ultimo = df.iloc[-1]
    col1, col2, col3 = st.columns(3)
    col1.metric(
        f"Média móvel {rotulo_janela(serie.periodicidade, 7)}",
        formata_valor(ultimo["media_movel_7d"], serie),
    )
    col2.metric(
        f"Média móvel {rotulo_janela(serie.periodicidade, 30)}",
        formata_valor(ultimo["media_movel_30d"], serie),
    )
    col3.metric(
        f"Volatilidade {rotulo_janela(serie.periodicidade, 30)}",
        formata_valor(ultimo["volatilidade_30d"], serie)
        if pd.notna(ultimo["volatilidade_30d"]) else "-",
    )
```

- [ ] **Step 2: Aplicar a paleta ao gráfico detalhado**

Substituir `render_chart` inteira por:

```python
def render_chart(df: pd.DataFrame, serie: Serie, codigo: int) -> None:
    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=df["data"], y=df["valor"], name="Valor", mode="lines",
        line={"color": cor_da_serie(codigo), "width": 2},
    ))
    fig.add_trace(go.Scatter(
        x=df["data"], y=df["media_movel_7d"],
        name=f"Média móvel {rotulo_janela(serie.periodicidade, 7)}", mode="lines",
        line={"color": COR_MM7, "width": 1.4, "dash": "dot"},
    ))
    fig.add_trace(go.Scatter(
        x=df["data"], y=df["media_movel_30d"],
        name=f"Média móvel {rotulo_janela(serie.periodicidade, 30)}", mode="lines",
        line={"color": COR_MM30, "width": 1.4, "dash": "dot"},
    ))
    fig.update_layout(
        template=TEMPLATE_PLOTLY,
        title=f"{serie.nome} — série histórica com médias móveis",
        xaxis_title=None,
        yaxis_title=serie.unidade,
        legend={"orientation": "h", "yanchor": "bottom", "y": 1.0, "xanchor": "left", "x": 0},
        legend_title="",
        height=420,
        hovermode="x unified",
    )
    st.plotly_chart(fig, use_container_width=True)
```

A legenda vai para cima na horizontal porque a vertical à direita rouba largura do gráfico; `hovermode="x unified"` mostra as três séries na mesma data num tooltip só.

- [ ] **Step 3: Formatar a tabela e acrescentar o rodapé da sidebar**

Em `main()`, substituir a chamada `render_chart(df_filtrado, serie)` por `render_chart(df_filtrado, serie, codigo_serie)`.

E substituir o bloco do expander por:

```python
    with st.expander("Ver tabela detalhada"):
        st.dataframe(
            df_filtrado.sort_values("data", ascending=False),
            use_container_width=True,
            hide_index=True,
            column_config={
                "data": st.column_config.DateColumn("Data", format="DD/MM/YYYY"),
                "valor": st.column_config.NumberColumn("Valor", format="%.4f"),
                "media_movel_7d": st.column_config.NumberColumn(
                    f"MM {rotulo_janela(serie.periodicidade, 7)}", format="%.4f"),
                "media_movel_30d": st.column_config.NumberColumn(
                    f"MM {rotulo_janela(serie.periodicidade, 30)}", format="%.4f"),
                "volatilidade_30d": st.column_config.NumberColumn(
                    f"Volatilidade {rotulo_janela(serie.periodicidade, 30)}", format="%.4f"),
                "variacao_absoluta": st.column_config.NumberColumn(
                    "Variação absoluta", format="%.4f"),
                "variacao_percentual": st.column_config.NumberColumn(
                    "Variação %", format="%.2f%%"),
            },
        )

    st.sidebar.divider()
    st.sidebar.caption(
        "**Fonte:** Sistema Gerenciador de Séries Temporais (SGS), "
        "Banco Central do Brasil."
    )
```

- [ ] **Step 4: Verificar rodando o app**

Run: `.venv\Scripts\python.exe -m streamlit run dashboard/app.py --server.headless true`

Conferir em `http://localhost:8501`:
1. o gráfico tem fundo transparente, grade discreta e legenda horizontal no topo;
2. a linha do dólar é ciano, a da Selic roxa, a do IPCA amarela;
3. passar o mouse mostra um tooltip único com as três linhas;
4. a tabela tem cabeçalhos em português e datas em `DD/MM/AAAA`;
5. o rodapé da sidebar cita a fonte dos dados;
6. escolher IPCA muda os rótulos para "meses" também na tabela.

- [ ] **Step 5: Run the whole suite and the linter**

Run: `.venv\Scripts\python.exe -m pytest -q` → 29 testes passando
Run: `.venv\Scripts\python.exe -m ruff check .` → `All checks passed!`

- [ ] **Step 6: Atualizar o README**

Na seção "Estrutura do projeto", acrescentar após a linha de `dashboard/app.py`:

```
├── dashboard/estilo.py           # tokens de cor, tema do Plotly e CSS
├── .streamlit/config.toml        # tema nativo do Streamlit
```

E na lista de camadas, substituir a linha de "Apresentação" por:

```markdown
- **Apresentação**: Streamlit + Plotly, com faixa dos três indicadores,
  gráfico detalhado da série escolhida e tabela filtrável. Tema próprio em
  `dashboard/estilo.py`.
```

- [ ] **Step 7: Atualizar o guia**

Em `docs/IMPLEMENTATION_GUIDE.md`, acrescentar ao final da seção `### 1.5 Dashboard` — ou seja, imediatamente **antes** da linha `## 2. Por que essas decisões técnicas`:

```markdown
### Aparência

O tema mora em dois arquivos, e só neles: `.streamlit/config.toml` (cores
base, lidas nativamente pelo Streamlit) e `dashboard/estilo.py` (tokens,
template do Plotly e o CSS pontual). Os valores de cor estão repetidos nos
dois porque o tema nativo só lê TOML — ao mudar um, mude o outro.

O CSS cobre apenas o que o Streamlit 1.36 não permite nativamente: o
`st.metric` só passou a aceitar `border` na 1.44, e a tipografia dos KPIs
não é configurável. Cada regra leva um comentário dizendo o que faz, porque
os seletores miram `data-testid` internos do Streamlit e podem desalinhar
num upgrade. Se isso acontecer, apagar a regra é seguro: nada quebra
funcionalmente sem ela.

Para trocar a paleta, edite os tokens em `estilo.py` e espelhe as quatro
cores base no `config.toml`.
```

- [ ] **Step 8: Commit e push**

```bash
git add dashboard/app.py README.md docs/IMPLEMENTATION_GUIDE.md
git commit -m "feat(dashboard): grafico, tabela e sidebar no tema Navy

O render_kpis encolhe de quatro para tres metricas: ultimo valor e
variacao passaram para a faixa do topo na tarefa anterior, e repeti-los
aqui seria ruido.

A legenda do grafico vai para o topo na horizontal -- a vertical a
direita roubava largura da area de dados. A tabela ganha cabecalhos em
portugues e formatacao de data, e a sidebar passa a citar a fonte.

Documenta que o tema mora em dois arquivos e por que os valores de cor
estao repetidos neles."
git push origin main
```

---

## Verificação final

- [ ] `.venv\Scripts\python.exe -m pytest -q` → 29 testes passando
- [ ] `.venv\Scripts\python.exe -m ruff check .` → `All checks passed!`
- [ ] Fundo azul-marinho, três cartões no topo com minigráfico e data
- [ ] IPCA exibe `-0,09 p.p.` e **não** `-56,25%`
- [ ] Selic estável aparece em cinza, não em verde
- [ ] Trocar de série no seletor não altera a faixa do topo
- [ ] CI verde após o push
