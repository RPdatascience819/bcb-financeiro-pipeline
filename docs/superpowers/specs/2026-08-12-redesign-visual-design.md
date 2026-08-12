# Redesign visual do dashboard

Data: 12/08/2026
Status: aprovado, aguardando plano de implementação

## Problema

O dashboard funciona, mas nunca recebeu tratamento visual: não existe
`.streamlit/config.toml`, não há CSS, o Plotly usa o template de fábrica. É o
tema padrão do Streamlit sem uma linha de customização.

Isso importa porque o projeto é **portfólio**. Quem o avalia costuma olhar um
screenshot no GitHub ou no LinkedIn por poucos segundos, e a tela atual tem duas
fraquezas nesse cenário:

1. **Mostra um indicador por vez.** Um screenshot do painel exibe um gráfico do
   dólar e nada mais — a impressão é de um app de série única, quando o pipeline
   carrega três.
2. **Parece o exemplo do tutorial.** Tipografia, cores e espaçamento são os
   padrões que qualquer pessoa reconhece como "Streamlit sem customizar".

## Decisões tomadas

### Layout híbrido: os três indicadores + o detalhe de um

A tela ganha uma faixa superior com os três indicadores sempre visíveis (rótulo,
valor atual, variação e minigráfico), e abaixo mantém o gráfico detalhado da
série escolhida no seletor.

**Alternativas descartadas:**

- **Repaginar sem mudar a estrutura** (uma série por vez, só mais bonito): mais
  barato, mas não resolve a fraqueza principal — o screenshot continuaria
  contando a história de um indicador só.
- **Panorama com as três séries lado a lado, sem seletor**: densidade máxima,
  mas cada gráfico ficaria pequeno, as escalas são incomparáveis (R$ contra %
  ao dia contra % ao mês) e o seletor recém-construído perderia a função.

O híbrido preserva o seletor com propósito claro — **escolher o que detalhar** —
e é o único que mostra profundidade analítica e cobertura ao mesmo tempo.

### A faixa de KPIs ignora o filtro de período

O filtro de datas age apenas no gráfico detalhado e na tabela. A faixa mostra
sempre os valores mais recentes, com a data de referência ao lado.

**Por quê:** quem filtra 2024 quer ver o gráfico daquele intervalo; um cartão
rotulado como o valor atual exibindo um número de dois anos atrás seria uma
afirmação falsa. A data ao lado remove qualquer ambiguidade.

### Paleta Navy financeiro

Escuro azul-marinho em vez de escuro neutro — a família de cor que terminais de
mercado usam, o que reforça a associação com o domínio dos dados.

**Alternativas descartadas:** grafite neutro (mais comum em portfólio de dados,
diferencia menos) e claro institucional (mais credível em impressão, menos
impacto numa timeline de imagens).

Tokens:

| Papel | Hex | Uso |
|---|---|---|
| Fundo | `#0B1B2B` | corpo da página |
| Superfície | `#12293F` | cards, sidebar |
| Borda | `#1E3A52` | contornos |
| Texto | `#E8F1F8` | valores e títulos |
| Texto secundário | `#8AA6BC` | rótulos, legendas, eixos |
| Acento | `#22D3EE` | destaque, série do dólar |
| Alta | `#34D399` | variação positiva |
| Baixa | `#FB7185` | variação negativa |

Cores por série no gráfico: dólar `#22D3EE`, Selic `#A78BFA`, IPCA `#FCD34D`.
Médias móveis: 7 períodos `#7C99B3`, 30 períodos `#3E5D77`.

### Variação em pontos percentuais para séries medidas em %

A coluna `variacao_percentual` calcula a variação relativa. Para o dólar isso é
correto e informativo. Para o IPCA é enganoso: de 0,16% para 0,07% ao mês, a
coluna registra **−56,25%**, e "o IPCA caiu 56%" é uma frase sem sentido
econômico. A leitura correta é **−0,09 ponto percentual**.

Regra: séries cuja unidade começa com `%` (Selic e IPCA) exibem a variação
**absoluta**, sufixada com `p.p.`; as demais (dólar) exibem a **percentual**.

A condição sai de `serie.unidade.startswith("%")` — exatamente a mesma que
`formata_valor` já usa. **Nenhum campo novo no catálogo.**

**Alternativas descartadas:** manter percentual para tudo (o KPI do IPCA
anunciaria −56,25%) e usar absoluta para tudo (o dólar perderia a noção de
magnitude relativa, que é justamente o que se lê nele).

### Sidebar mantida

Os controles continuam na sidebar, agora tematizada e com um rodapé indicando a
fonte dos dados.

**Alternativa descartada:** eliminar a sidebar e pôr os controles na tela. Renderia
uma tela que parece menos "Streamlit padrão" e devolveria ~15% de largura, mas
custaria mais código e não escala se o catálogo crescer.

### CSS pontual, isolado num só arquivo

Base no `config.toml` nativo; CSS injetado apenas onde o nativo não alcança.

**Por que não só nativo:** o Streamlit 1.36 não aceita `border` no `st.metric`
(chegou na 1.44) e não permite controlar o tamanho tipográfico dos KPIs. O teto
estético sem CSS é visivelmente mais baixo.

**Por que não CSS pesado:** depender extensamente de classes internas do
Streamlit cria manutenção que, num portfólio de engenharia de dados, é código
que você terá de explicar sem que ele demonstre a competência anunciada.

## Arquitetura

```
.streamlit/config.toml   tema nativo (base dark + tokens). Versionado.
dashboard/estilo.py      NOVO: tokens, CSS pontual, template Plotly
db/series_catalog.py     ganha formata_variacao() — pura, testável
dashboard/app.py         estrutura e dados; importa aparência de estilo.py
```

A fronteira: **`estilo.py` responde "como se parece", `app.py` responde "o que
mostra"**. Trocar a paleta inteira deve exigir mexer em um arquivo só.

O motivo de separar: `app.py` tem hoje ~160 linhas e já acumula consulta,
formatação e desenho. Aparência é uma quarta preocupação; solta ali, o arquivo
cresce até virar aquele que ninguém quer abrir.

## Componentes

### 1. `db/series_catalog.py` — nova função

```python
formata_variacao(
    variacao_absoluta: float,
    variacao_percentual: float,
    serie: Serie,
) -> str | None
```

- Série em `%` → `f"{variacao_absoluta:.{decimais}f} p.p."`, vírgula decimal.
- Demais → `f"{variacao_percentual:.2f}%"`, vírgula decimal.
- Sinal `+` explícito quando positivo; `-` ASCII quando negativo (ver abaixo).
- Qualquer entrada `NaN` → `None` (primeira linha da série não tem anterior).

**Sem seta e sem cor.** Quem desenha isso é o `st.metric` nativamente.

### 2. `dashboard/estilo.py` (novo)

- Constantes de cor com os tokens da tabela acima.
- `TEMPLATE_PLOTLY`: template Plotly em Navy — fundo transparente, grade
  `#1E3A52` discreta, texto dos eixos em `#8AA6BC`, sem linha de eixo pesada.
- `CSS`: string aplicada uma vez via `st.markdown(..., unsafe_allow_html=True)`.
  Cobre apenas tipografia dos KPIs, superfície dos cards e espaçamento do topo.
  **Cada regra leva um comentário dizendo o que faz**, para poder ser removida
  isoladamente se um upgrade do Streamlit a quebrar.
- `aplica_estilo()`: aplica o CSS. Chamada uma vez no início do `main()`.

### 3. `dashboard/app.py`

- `render_faixa_indicadores()` — percorre as séries devolvidas por
  `series_disponiveis()` e monta um `st.columns(n)` com um
  `st.container(border=True)` por série, contendo `st.metric` (valor via
  `formata_valor`, delta via `formata_variacao`) e um minigráfico.
  Séries presentes no banco mas ausentes do catálogo entram na faixa com o
  mesmo objeto `Serie` de fallback que o seletor já usa — some-las esconderia
  dados que existem. Com o catálogo atual são sempre três colunas; se ele
  crescer muito, a faixa fica apertada — aceito, porque o catálogo é código e
  cresce por decisão, não em runtime.
- **Nenhuma consulta nova.** Reusa `load_data(codigo)`, já cacheada por 5 min,
  e lê `iloc[-1]`. Custo de rede adicional: zero.
- `render_sparkline(df, serie)` — figura Plotly pequena, eixos e legenda
  ocultos, sem interação, altura fixa. Alimentada pelos dados já em memória.
  **Janela: os últimos 90 registros**, não a série inteira. Em dois anos de série
  diária a linha inteira vira um borrão ilegível num espaço de 40px de altura;
  90 pontos mostram tendência recente, que é o que um minigráfico comunica. Numa
  série mensal os 24 registros existentes cabem todos, então o corte não a afeta.
- `render_chart` e `render_kpis` passam a usar `TEMPLATE_PLOTLY` e as cores por
  série.
- A tabela do expander ganha `column_config` para formatar datas e números.
- Rodapé da sidebar: fonte dos dados e data da última atualização.

### 4. `.streamlit/config.toml`

```toml
[theme]
base = "dark"
primaryColor = "#22D3EE"
backgroundColor = "#0B1B2B"
secondaryBackgroundColor = "#12293F"
textColor = "#E8F1F8"
font = "sans serif"
```

## Restrições conhecidas do Streamlit 1.36

Levantadas antes do design, condicionam a implementação:

1. **`st.metric` não aceita `border`** — o parâmetro chegou na 1.44. Os cards
   usam `st.container(border=True)`.
2. **`secondaryBackgroundColor` pinta a sidebar e as superfícies ao mesmo
   tempo.** Como a sidebar fica com a mesma cor dos cards (`#12293F`), ela
   aparecerá **mais clara** que o fundo, não mais escura como no mockup. Aceito:
   diferenciar exigiria CSS adicional sem ganho proporcional.
3. **`font` aceita apenas `sans serif`, `serif` ou `monospace`.** Fonte própria
   exigiria carregar webfont por CSS — fora de escopo.
4. **`st.metric` decide a cor do delta pelo primeiro caractere** ser `-`. Por
   isso o sinal negativo é hífen ASCII e não o menos tipográfico `−`. Para
   variação zero (Selic estável) o app passa `delta_color="off"`, senão o
   Streamlit pintaria de verde um valor que não subiu.

## Testes

Apenas `formata_variacao` é testável de verdade — pura, sem banco, sem rede, sem
Streamlit. Casos:

1. Dólar (unidade `R$`) devolve variação percentual com vírgula e `%`.
2. IPCA (unidade `% a.m.`) devolve variação absoluta com `p.p.`, e **não** os
   −56,25% da coluna percentual.
3. Selic com variação zero devolve `0,0000 p.p.` (sem sinal).
4. Entrada `NaN` devolve `None`.
5. Valor positivo leva `+` explícito; negativo leva hífen ASCII.

Layout, CSS e tema não têm teste automatizado: exercitar widgets de Streamlit
exigiria máquina de teste desproporcional ao ganho. A verificação é executar o
app, como na entrega anterior.

A suíte continua **sem depender de banco nem de rede**, como exige o CI.

## Riscos assumidos

1. **Verde/vermelho indicam direção, não juízo.** O dólar subindo aparece em
   verde, o que é economicamente ruim para o leitor brasileiro. É a convenção de
   painéis financeiros, e a alternativa (colorir por sentimento) exigiria decidir
   o que é "bom" para cada série — subjetivo e frágil.
2. **O CSS mira estrutura interna do Streamlit.** Mesmo pontual, pode desalinhar
   num upgrade. Mitigação: cada regra é isolada e comentada; o conserto é
   apagá-la, sem quebra funcional.
3. **Três figuras Plotly extras** por render. Volume atual (504 pontos por série
   diária) torna o custo irrelevante; num volume muito maior, os minigráficos
   passariam a merecer amostragem.

## Fora de escopo

- Comparar séries no mesmo gráfico (escalas incomparáveis).
- Fonte própria via webfont.
- Janelas de tempo próprias por periodicidade — descartado na rodada anterior e
  não reaberto aqui.
- Qualquer mudança em ingestão, SQL ou catálogo além da `formata_variacao`.
