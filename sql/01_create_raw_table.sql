-- 01_create_raw_table.sql
-- Camada RAW: espelha a resposta da API do BCB praticamente sem tratamento.
-- Esta tabela tambem eh criada automaticamente pelo ingestion/fetch_data.py,
-- mas o script fica aqui para deixar o contrato de dados explicito e versionado.

CREATE SCHEMA IF NOT EXISTS raw;

CREATE TABLE IF NOT EXISTS raw.serie_bcb (
    codigo_serie   INTEGER        NOT NULL,
    data           DATE           NOT NULL,
    valor          NUMERIC(18, 6) NOT NULL,
    carregado_em   TIMESTAMPTZ    NOT NULL,
    PRIMARY KEY (codigo_serie, data)
);

COMMENT ON TABLE raw.serie_bcb IS
    'Dados brutos de series temporais do BCB (SGS), carregados via ingestion/fetch_data.py.';
