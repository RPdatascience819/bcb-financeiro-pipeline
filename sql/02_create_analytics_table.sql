-- 02_create_analytics_table.sql
-- Camada ANALYTICS: transforma a serie bruta em uma tabela pronta para
-- consumo no dashboard, com media movel, variacao diaria e variacao
-- percentual em relacao ao dia anterior.
--
-- Executado por transform/run_transform.py apos cada carga incremental.
-- Usa DROP + CREATE (materializacao completa) porque o volume de uma
-- serie temporal diaria do BCB e pequeno; para volumes maiores, trocar
-- por uma estrategia incremental (INSERT ... WHERE data > ultima_data).

CREATE SCHEMA IF NOT EXISTS analytics;

DROP TABLE IF EXISTS analytics.serie_bcb_metrics;

CREATE TABLE analytics.serie_bcb_metrics AS
WITH base AS (
    SELECT
        codigo_serie,
        data,
        valor
    FROM raw.serie_bcb
),
com_janela AS (
    SELECT
        codigo_serie,
        data,
        valor,
        LAG(valor) OVER (PARTITION BY codigo_serie ORDER BY data)        AS valor_dia_anterior,
        AVG(valor) OVER (
            PARTITION BY codigo_serie
            ORDER BY data
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )                                                                AS media_movel_7d,
        AVG(valor) OVER (
            PARTITION BY codigo_serie
            ORDER BY data
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        )                                                                AS media_movel_30d,
        STDDEV_SAMP(valor) OVER (
            PARTITION BY codigo_serie
            ORDER BY data
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        )                                                                AS volatilidade_30d
    FROM base
)
SELECT
    codigo_serie,
    data,
    valor,
    ROUND(media_movel_7d, 4)  AS media_movel_7d,
    ROUND(media_movel_30d, 4) AS media_movel_30d,
    ROUND(volatilidade_30d, 4) AS volatilidade_30d,
    ROUND(valor - valor_dia_anterior, 4) AS variacao_absoluta,
    CASE
        WHEN valor_dia_anterior IS NULL OR valor_dia_anterior = 0 THEN NULL
        ELSE ROUND(100.0 * (valor - valor_dia_anterior) / valor_dia_anterior, 4)
    END AS variacao_percentual
FROM com_janela
ORDER BY codigo_serie, data;

ALTER TABLE analytics.serie_bcb_metrics ADD PRIMARY KEY (codigo_serie, data);

COMMENT ON TABLE analytics.serie_bcb_metrics IS
    'Serie do BCB com medias moveis (7d/30d), volatilidade e variacao diaria, pronta para o dashboard.';
