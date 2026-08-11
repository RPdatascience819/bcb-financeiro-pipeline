# run_pipeline.ps1
# Atalho: roda ingestao + transformacao em sequencia.
# Uso: .\run_pipeline.ps1 [-Ultimos 500]

param([int]$Ultimos = 500)

$ErrorActionPreference = "Stop"

Write-Host "==> Ingestao (ultimos $Ultimos valores)" -ForegroundColor Cyan
python -m ingestion.fetch_data --ultimos $Ultimos

Write-Host "==> Transformacao" -ForegroundColor Cyan
python -m transform.run_transform

Write-Host ""
Write-Host "Pipeline concluido. Para abrir o dashboard:" -ForegroundColor Green
Write-Host "  streamlit run dashboard/app.py"