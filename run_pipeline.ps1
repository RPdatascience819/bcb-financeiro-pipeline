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

$fim = (Get-Date).ToString("dd/MM/yyyy")
$inicio = (Get-Date).AddYears(-$Anos).ToString("dd/MM/yyyy")

Write-Host "==> Ingestao ($inicio ate $fim)" -ForegroundColor Cyan
python -m ingestion.fetch_data --inicio $inicio --fim $fim

Write-Host "==> Transformacao" -ForegroundColor Cyan
python -m transform.run_transform

Write-Host ""
Write-Host "Pipeline concluido. Para abrir o dashboard:" -ForegroundColor Green
Write-Host "  streamlit run dashboard/app.py"