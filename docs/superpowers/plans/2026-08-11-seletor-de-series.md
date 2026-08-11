# Seletor de Séries no Dashboard — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Permitir escolher entre dólar, Selic e IPCA no dashboard, por nome, com rótulos e unidades corretos para a periodicidade de cada série.

**Architecture:** Um catálogo em Python (`db/series_catalog.py`) vira a fonte única da verdade sobre quais séries o pipeline carrega e como cada uma é exibida. A ingestão ganha `--todas`, que itera esse catálogo. O dashboard monta um seletor a partir do cruzamento entre o que existe no banco e o catálogo. O SQL de transformação não muda.

**Tech Stack:** Python 3.11, SQLAlchemy 2, pandas, Streamlit, Plotly, pytest, ruff, PostgreSQL 16 em container.

## Global Constraints

- Interpretador: sempre `.venv\Scripts\python.exe` (o `python` puro pode ser o global).
- A suíte de testes **não pode** exigir banco nem rede — o CI roda sem Postgres.
- Arquivos gravados em UTF-8 **sem BOM**.
- Todo texto visível ao usuário em pt-BR **com acentuação**.
- `ruff check .` e `pytest` precisam passar antes de cada commit.
- Séries do catálogo, com valores exatos: `1` = Dólar comercial (venda), `R$`, diária, 4 casas; `11` = Selic, `% a.d.`, diária, 4 casas; `433` = IPCA, `% a.m.`, mensal, 2 casas.
- Endpoint por intervalo de datas (`--inicio`/`--fim`); `/ultimos/N` tem teto de 20 e não deve ser usado no fluxo padrão.

---

### Task 1: Catálogo de séries

Módulo puro: sem banco, sem rede, sem Streamlit. Tudo aqui é testável isoladamente.

**Files:**
- Create: `db/series_catalog.py`
- Test: `tests/test_series_catalog.py`

**Interfaces:**
- Consumes: nada.
- Produces:
  - `DIARIA: str = "diaria"`, `MENSAL: str = "mensal"`
  - `Serie` — dataclass congelada com `nome: str`, `unidade: str`, `periodicidade: str`, `decimais: int`
  - `SERIES: dict[int, Serie]`
  - `nome_da_serie(codigo: int) -> str`
  - `rotulo_janela(periodicidade: str, n: int) -> str`
  - `formata_valor(valor: float, serie: Serie) -> str`
  - `opcoes_do_seletor(codigos_no_banco: list[int]) -> list[int]`

- [ ] **Step 1: Write the failing test**

Create `tests/test_series_catalog.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv\Scripts\python.exe -m pytest tests/test_series_catalog.py -v`
Expected: FAIL na coleta — `ModuleNotFoundError: No module named 'db.series_catalog'`

- [ ] **Step 3: Write minimal implementation**

Create `db/series_catalog.py`:

```python
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


def opcoes_do_seletor(codigos_no_banco: list[int]) -> list[int]:
    """Ordena os codigos presentes no banco pela ordem do catalogo.

    Codigos que o catalogo nao conhece vao para o final, ordenados, em vez
    de sumirem da lista -- some-los esconderia dados que existem.
    """
    conhecidos = [c for c in SERIES if c in codigos_no_banco]
    desconhecidos = sorted(c for c in codigos_no_banco if c not in SERIES)
    return conhecidos + desconhecidos
```

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv\Scripts\python.exe -m pytest tests/test_series_catalog.py -v`
Expected: PASS — 11 testes

- [ ] **Step 5: Run the whole suite and the linter**

Run: `.venv\Scripts\python.exe -m pytest -q` → 21 testes passando (10 antigos + 11 novos)
Run: `.venv\Scripts\python.exe -m ruff check .` → `All checks passed!`

- [ ] **Step 6: Commit**

```bash
git add db/series_catalog.py tests/test_series_catalog.py
git commit -m "feat(catalogo): adiciona catalogo de series do SGS

Fonte unica da verdade sobre quais series o pipeline carrega e como cada
uma e exibida. Guarda nome, unidade, periodicidade e casas decimais.

As janelas do SQL contam linhas (ROWS BETWEEN N PRECEDING), nao dias.
rotulo_janela() traduz isso para a unidade de tempo certa: 7 linhas sao
7 dias numa serie diaria e 7 meses numa mensal."
```

---

### Task 2: Flag `--todas` na ingestão

**Files:**
- Modify: `ingestion/fetch_data.py`
- Modify: `run_pipeline.ps1`
- Test: `tests/test_ingestion.py`

**Interfaces:**
- Consumes: `SERIES` e `nome_da_serie` de `db.series_catalog` (Task 1).
- Produces:
  - `PAUSA_ENTRE_SERIES: float = 3.0`
  - `run_todas(inicio: str | None, fim: str | None, ultimos: int | None, pausa: float = PAUSA_ENTRE_SERIES) -> tuple[int, int]` — devolve `(sucessos, falhas)`
  - `parse_args` passa a aceitar `--todas` (bool), mutuamente exclusiva com `--serie`

**Nota sobre os testes:** mockar apenas `requests.get` **não** basta. `run()` chama `ensure_raw_table()` antes do fetch, o que abre conexão com o Postgres — a suíte quebraria no CI. Os testes mockam `ingestion.fetch_data.run` inteira, isolando a lógica de orquestração, que é o que esta task adiciona.

- [ ] **Step 1: Write the failing test**

Adicionar ao final de `tests/test_ingestion.py`:

```python
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
```

E completar os imports no topo do arquivo:

```python
from db.series_catalog import SERIES  # noqa: E402
from ingestion.fetch_data import (  # noqa: E402
    IngestionError,
    build_url,
    fetch_series,
    parse_args,
    run_todas,
)
```

(substitui a linha `from ingestion.fetch_data import IngestionError, build_url, fetch_series`)

- [ ] **Step 2: Run test to verify it fails**

Run: `.venv\Scripts\python.exe -m pytest tests/test_ingestion.py -v`
Expected: FAIL na coleta — `ImportError: cannot import name 'run_todas'`

- [ ] **Step 3: Write minimal implementation**

Em `ingestion/fetch_data.py`, adicionar `import time` junto aos demais imports da biblioteca padrão e o import do catálogo logo abaixo do import de `db.connection`:

```python
from db.connection import get_engine  # noqa: E402
from db.series_catalog import SERIES, nome_da_serie  # noqa: E402
```

Adicionar a constante junto às outras do módulo:

```python
PAUSA_ENTRE_SERIES = 3.0
```

Adicionar a função logo após `run()`:

```python
def run_todas(
    inicio: str | None,
    fim: str | None,
    ultimos: int | None,
    pausa: float = PAUSA_ENTRE_SERIES,
) -> tuple[int, int]:
    """Ingere todas as series do catalogo. Devolve (sucessos, falhas).

    Uma serie que falha nao derruba as demais: o SGS limita requisicoes por
    IP e tres chamadas em sequencia sao exatamente o padrao que dispara o
    bloqueio. Carregar duas de tres e avisar e melhor que perder as tres.

    A pausa entre series existe pelo mesmo motivo; os testes passam 0.
    """
    codigos = list(SERIES)
    sucessos = 0
    falhas = 0

    for posicao, codigo in enumerate(codigos):
        try:
            total = run(codigo, inicio, fim, ultimos)
            logger.info("Serie %d (%s): %d linhas.", codigo, nome_da_serie(codigo), total)
            sucessos += 1
        except IngestionError as exc:
            logger.error("Serie %d (%s) falhou: %s", codigo, nome_da_serie(codigo), exc)
            falhas += 1
        if posicao < len(codigos) - 1:
            time.sleep(pausa)

    return sucessos, falhas
```

Em `parse_args`, trocar a definição de `--serie` por um grupo mutuamente exclusivo:

```python
    grupo = parser.add_mutually_exclusive_group()
    grupo.add_argument("--serie", type=int, default=int(os.environ.get("BCB_SERIES_CODE", 1)),
                       help="Codigo da serie SGS (default: 1 = dolar comercial, venda).")
    grupo.add_argument("--todas", action="store_true",
                       help="Ingere todas as series do catalogo (db/series_catalog.py).")
```

Substituir o bloco `if __name__ == "__main__":` por:

```python
if __name__ == "__main__":
    args = parse_args()
    if args.todas:
        sucessos, falhas = run_todas(args.inicio, args.fim, args.ultimos)
        logger.info("Ingestao concluida: %d de %d series carregadas.", sucessos, sucessos + falhas)
        sys.exit(1 if falhas else 0)
    total = run(args.serie, args.inicio, args.fim, args.ultimos)
    logger.info("Ingestao concluida: %d linhas processadas.", total)
```

(`sys` já está importado no módulo.)

- [ ] **Step 4: Run test to verify it passes**

Run: `.venv\Scripts\python.exe -m pytest tests/test_ingestion.py -v`
Expected: PASS — 9 testes (6 antigos + 3 novos)

- [ ] **Step 5: Apontar o run_pipeline.ps1 para `--todas`**

Em `run_pipeline.ps1`, trocar a linha da ingestão:

```powershell
python -m ingestion.fetch_data --todas --inicio $inicio --fim $fim
```

E o cabeçalho da mensagem:

```powershell
Write-Host "==> Ingestao de todas as series ($inicio ate $fim)" -ForegroundColor Cyan
```

- [ ] **Step 6: Run the whole suite and the linter**

Run: `.venv\Scripts\python.exe -m pytest -q` → 24 testes passando
Run: `.venv\Scripts\python.exe -m ruff check .` → `All checks passed!`

- [ ] **Step 7: Commit**

```bash
git add ingestion/fetch_data.py tests/test_ingestion.py run_pipeline.ps1
git commit -m "feat(ingestao): adiciona --todas para carregar o catalogo inteiro

A lista de series a carregar mora no catalogo, nao no run_pipeline.ps1 --
duplica-la no script criaria uma segunda fonte da verdade sobre quais
series o projeto conhece.

Falha em uma serie nao derruba as demais e o processo termina com codigo
!= 0 se alguma falhou. Ha uma pausa de 3s entre series: tres chamadas em
sequencia sao exatamente o padrao que dispara o limite por IP do SGS."
```

---

### Task 3: Seletor de séries no dashboard

Esta task é wiring de Streamlit. Não há teste unitário: a lógica testável
(ordenação, rótulos, formatação) já está coberta na Task 1, e exercitar
widgets de Streamlit exigiria máquina de teste desproporcional ao ganho. A
verificação é executar o app contra o banco, no Step 4.

**Files:**
- Modify: `dashboard/app.py`

**Interfaces:**
- Consumes: `SERIES`, `nome_da_serie`, `rotulo_janela`, `formata_valor`, `opcoes_do_seletor` de `db.series_catalog` (Task 1).
- Produces: nada consumido por outras tasks.

- [ ] **Step 1: Importar o catálogo**

Logo abaixo de `from db.connection import get_engine`:

```python
from db.series_catalog import (  # noqa: E402
    DIARIA,
    SERIES,
    Serie,
    formata_valor,
    nome_da_serie,
    opcoes_do_seletor,
    rotulo_janela,
)
```

`Serie` e `DIARIA` entram aqui porque uma série presente no banco mas ausente
do catálogo ainda precisa de um objeto `Serie` para os formatadores
funcionarem (ver Step 3).

- [ ] **Step 2: Consultar quais séries existem no banco**

Adicionar após `load_data`:

```python
@st.cache_data(ttl=300)
def series_disponiveis() -> list[int]:
    """Codigos de serie que existem na tabela de metricas."""
    engine = get_engine()
    query = text("SELECT DISTINCT codigo_serie FROM analytics.serie_bcb_metrics")
    with engine.connect() as conn:
        codigos = [linha[0] for linha in conn.execute(query)]
    return opcoes_do_seletor(codigos)
```

- [ ] **Step 3: Trocar o campo numérico pelo seletor e usar os rótulos**

Substituir `render_kpis` por uma versão que recebe a série:

```python
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
```

Substituir `render_chart` por:

```python
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
```

Em `main()`, substituir a linha do `number_input` por:

```python
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
```

Trocar as duas chamadas no fim de `main()`:

```python
    render_kpis(df_filtrado, serie)
    render_chart(df_filtrado, serie)
```

E o `st.warning` de série sem dados, que agora só ocorre em corrida com o
cache, por:

```python
        st.warning("Nenhum dado encontrado para essa série.")
```

- [ ] **Step 4: Verificar rodando o app**

Run: `.venv\Scripts\python.exe -m streamlit run dashboard/app.py --server.headless true`

Conferir na tela:
1. o sidebar mostra **Série** com um seletor, não um campo numérico;
2. as opções aparecem por nome (só a que estiver carregada, até a Task 4 rodar);
3. os KPIs mostram a unidade (`R$ 5,1285`);
4. o rótulo diz "Média móvel 7 dias".

- [ ] **Step 5: Rodar suíte e linter**

Run: `.venv\Scripts\python.exe -m pytest -q` → 24 testes passando
Run: `.venv\Scripts\python.exe -m ruff check .` → `All checks passed!`

- [ ] **Step 6: Commit**

```bash
git add dashboard/app.py
git commit -m "feat(dashboard): troca o codigo da serie por um seletor com nomes

O campo numerico exigia saber de cabeca que Selic e a serie 11, e aceitava
codigos que levavam a lugar nenhum -- o dashboard so le, entao uma serie
nao ingerida produzia 'nenhum dado encontrado', que parece bug.

O seletor lista apenas o que existe no banco, por nome. Os rotulos das
janelas passam a respeitar a periodicidade da serie e os valores exibem a
unidade."
```

---

### Task 4: Carregar as três séries e atualizar a documentação

**Files:**
- Modify: `README.md`
- Modify: `docs/IMPLEMENTATION_GUIDE.md`

**Interfaces:**
- Consumes: `--todas` (Task 2) e o seletor (Task 3).
- Produces: nada.

- [ ] **Step 1: Rodar o pipeline completo**

Run: `. .\.venv\Scripts\Activate.ps1; .\run_pipeline.ps1`

Expected: log com "Serie 1 (Dólar comercial (venda)): N linhas", o mesmo para 11 e 433, e "Ingestao concluida: 3 de 3 series carregadas."

- [ ] **Step 2: Verificar no banco**

```bash
.venv\Scripts\python.exe -c "import sys; sys.path.insert(0,'.'); from db.connection import get_engine; from sqlalchemy import text; c=get_engine().connect(); print(c.execute(text('SELECT codigo_serie, count(*) FROM analytics.serie_bcb_metrics GROUP BY 1 ORDER BY 1')).all())"
```

Expected: três linhas, com as séries 1, 11 e 433. A 433 terá bem menos
registros que as outras — ela é mensal, e isso é o esperado, não um erro.

- [ ] **Step 3: Conferir o dashboard com as três séries**

Abrir `http://localhost:8501` e confirmar:
1. o seletor lista as três séries por nome;
2. ao escolher IPCA, o rótulo muda para "Média móvel 7 **meses**";
3. o valor do IPCA aparece como `0,24 % a.m.` e o do dólar como `R$ 5,1285`.

- [ ] **Step 4: Atualizar o README**

Na seção "Como rodar", após o bloco de código, acrescentar:

```markdown
O `run_pipeline.ps1` carrega todas as séries do catálogo
(`db/series_catalog.py`): dólar comercial, Selic e IPCA. No dashboard, o
seletor do sidebar troca entre elas pelo nome.
```

Na "Estrutura do projeto", acrescentar após a linha de `db/connection.py`:

```
├── db/series_catalog.py          # séries conhecidas: nome, unidade, periodicidade
```

- [ ] **Step 5: Atualizar o guia**

Em `docs/IMPLEMENTATION_GUIDE.md`, na seção 1.3, substituir o bloco de
alternativas de execução pelo que reflete o catálogo:

```markdown
```powershell
# todas as series do catalogo (dolar, Selic, IPCA)
python -m ingestion.fetch_data --todas --inicio 01/01/2024 --fim 31/12/2025

# uma serie especifica
python -m ingestion.fetch_data --serie 11 --inicio 01/01/2024 --fim 31/12/2025
```

Para acrescentar uma série ao projeto, basta adicioná-la a `SERIES` em
`db/series_catalog.py` — a ingestão e o seletor do dashboard passam a
enxergá-la automaticamente. Informe a periodicidade correta: as janelas do
SQL contam linhas, então é ela que define se "7" significa 7 dias ou 7 meses.
```

- [ ] **Step 6: Commit e push**

```bash
git add README.md docs/IMPLEMENTATION_GUIDE.md
git commit -m "docs: documenta o catalogo de series e o seletor do dashboard"
git push origin main
```

---

## Verificação final

- [ ] `.venv\Scripts\python.exe -m pytest -q` → 24 testes passando
- [ ] `.venv\Scripts\python.exe -m ruff check .` → `All checks passed!`
- [ ] Banco com as três séries em `analytics.serie_bcb_metrics`
- [ ] Dashboard troca entre as três séries e muda o rótulo de dias para meses no IPCA
- [ ] CI verde após o push
