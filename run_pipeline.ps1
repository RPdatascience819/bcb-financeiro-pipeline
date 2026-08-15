# run_pipeline.ps1
# Atalho: roda ingestao + transformacao em sequencia.
# Uso: .\run_pipeline.ps1 [-Anos 2]
#
# Busca por intervalo de datas, e nao por "--ultimos N": o endpoint
# /ultimos/N da API do BCB aceita no maximo 20 valores, o que nao preenche
# a janela de 30 dias das metricas. O intervalo aceita ate 10 anos em
# series de periodicidade diaria.

param([int]$Anos = 2)

$ErrorActionPreference = "Stop"

# Caminho explicito para o interpretador do venv, em vez de "python" puro:
# o Activate.ps1 chamado sem dot-source ativa em escopo filho e morre ao
# voltar, entao "python" cairia no interpretador global -- que nao tem as
# dependencias e roda contra outro ambiente sem avisar.
$python = ".\.venv\Scripts\python.exe"

$fim = (Get-Date).ToString("dd/MM/yyyy")
$inicio = (Get-Date).AddYears(-$Anos).ToString("dd/MM/yyyy")

Write-Host "==> Ingestao de todas as series ($inicio ate $fim)" -ForegroundColor Cyan
& $python -m ingestion.fetch_data --todas --inicio $inicio --fim $fim
# $ErrorActionPreference nao intercepta codigo de saida de executavel nativo
# no PS 5.1 -- so age sobre erro de cmdlet. Sem esta checagem, uma ingestao
# que carrega 2 de 3 series (fetch_data sai com 1) seguiria para a
# transformacao e o script anunciaria "Pipeline concluido" mentindo.
if ($LASTEXITCODE -ne 0) {
    Write-Host "Ingestao falhou (codigo $LASTEXITCODE). Abortando." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host "==> Transformacao" -ForegroundColor Cyan
& $python -m transform.run_transform
if ($LASTEXITCODE -ne 0) {
    Write-Host "Transformacao falhou (codigo $LASTEXITCODE)." -ForegroundColor Red
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Pipeline concluido. Para abrir o dashboard:" -ForegroundColor Green
Write-Host "  streamlit run dashboard/app.py"