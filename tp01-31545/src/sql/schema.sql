-- TP1 ISI - Sistema Inteligente de Comparação de Preços
-- Pode ser corrido várias vezes: só cria o que ainda não existe.
-- Princípio do sistema: os dados NUNCA são eliminados. Os triggers no fim deste ficheiro
-- recusam DELETE/TRUNCATE em todas as tabelas e guardam na tabela auditoria
-- a versão antiga de cada linha atualizada.

CREATE TABLE IF NOT EXISTS lojas (
    codigo          CHAR(2) PRIMARY KEY,          -- PT, ES, UK, US
    nome            VARCHAR(100) NOT NULL,
    pais            CHAR(2) NOT NULL,
    moeda           CHAR(3) NOT NULL,
    fora_ue         BOOLEAN NOT NULL DEFAULT FALSE  -- calculado a partir da API VATComply
);

CREATE TABLE IF NOT EXISTS produtos (
    ean          CHAR(13) PRIMARY KEY,
    titulo       VARCHAR(255) NOT NULL,
    fakestore_id INTEGER,
    categoria    VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS taxas_cambio (
    moeda    CHAR(3),
    taxa     NUMERIC(12,6) NOT NULL,              -- unidades da moeda por 1 EUR
    data     DATE,
    PRIMARY KEY (moeda, data)
);

CREATE TABLE IF NOT EXISTS taxas_iva (
    pais        CHAR(2),
    taxa_normal NUMERIC(5,2) NOT NULL,            -- em %, ex: 23.00
    membro_ue   BOOLEAN NOT NULL,
    data        DATE,
    PRIMARY KEY (pais, data)
);

CREATE TABLE IF NOT EXISTS historico_precos (
    id               BIGSERIAL PRIMARY KEY,
    ean              CHAR(13) REFERENCES produtos(ean),
    loja             CHAR(2)  REFERENCES lojas(codigo),
    preco_original   NUMERIC(10,2) NOT NULL,
    moeda            CHAR(3) NOT NULL,
    preco_eur        NUMERIC(10,2) NOT NULL,
    portes_original  NUMERIC(10,2) NOT NULL,      -- na moeda da loja (0 = grátis)
    portes_eur       NUMERIC(10,2) NOT NULL,
    direitos_eur     NUMERIC(10,2) NOT NULL DEFAULT 0,
    iva_import_eur   NUMERIC(10,2) NOT NULL DEFAULT 0,
    desalfand_eur    NUMERIC(10,2) NOT NULL DEFAULT 0,
    custo_total_eur  NUMERIC(10,2) NOT NULL,
    origem           VARCHAR(20),                 -- csv, json, xml, stream
    registado_em     TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS precos_alvo (
    id               SERIAL PRIMARY KEY,
    utilizador_email VARCHAR(255) NOT NULL,
    ean              CHAR(13) REFERENCES produtos(ean),
    preco_alvo_eur   NUMERIC(10,2) NOT NULL,
    origem_ficheiro  VARCHAR(10),
    UNIQUE (utilizador_email, ean)
);

CREATE TABLE IF NOT EXISTS alertas (
    id               SERIAL PRIMARY KEY,
    ean              CHAR(13) REFERENCES produtos(ean),
    loja             CHAR(2)  REFERENCES lojas(codigo),
    utilizador_email VARCHAR(255) NOT NULL,
    custo_total_eur  NUMERIC(10,2),
    preco_alvo_eur   NUMERIC(10,2),
    poupanca_pct     NUMERIC(5,2),
    enviado_em       TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS logs_execucao (
    id       SERIAL PRIMARY KEY,
    job      VARCHAR(100),
    estado   VARCHAR(20),                         -- OK, AVISO, ERRO
    mensagem TEXT,
    linhas   INTEGER,
    inicio   TIMESTAMP,
    fim      TIMESTAMP DEFAULT NOW()
);

-- Dados tal como vieram das fontes, antes de qualquer limpeza (camada "bruta")
CREATE TABLE IF NOT EXISTS precos_brutos (
    id            BIGSERIAL PRIMARY KEY,
    ean           TEXT,
    titulo        TEXT,
    preco_texto   TEXT,
    portes_texto  TEXT,
    loja          TEXT,
    origem        TEXT,
    extraido_em   TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Linhas rejeitadas pela validação, com o motivo
CREATE TABLE IF NOT EXISTS rejeitados (
    id             BIGSERIAL PRIMARY KEY,
    tabela_destino TEXT NOT NULL,                 -- historico_precos ou precos_alvo
    ean            TEXT,
    loja           TEXT,
    email          TEXT,
    valor_texto    TEXT,
    motivo         TEXT NOT NULL,
    rejeitado_em   TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Versões antigas das linhas alteradas (preenchida automaticamente pelos triggers)
CREATE TABLE IF NOT EXISTS auditoria (
    id             BIGSERIAL PRIMARY KEY,
    tabela         TEXT NOT NULL,
    operacao       TEXT NOT NULL,
    dados_antigos  JSONB,
    dados_novos    JSONB,
    alterado_em    TIMESTAMP NOT NULL DEFAULT NOW(),
    utilizador     TEXT NOT NULL DEFAULT current_user
);

-- =====================================================================
-- Proteção: os dados nunca são eliminados
-- =====================================================================

CREATE OR REPLACE FUNCTION fn_bloquear() RETURNS trigger AS $$
BEGIN
    RAISE EXCEPTION 'Operação % proibida na tabela %: os dados deste sistema nunca são eliminados nem alterados.',
        TG_OP, TG_TABLE_NAME;
END;
$$ LANGUAGE plpgsql;

-- Guarda a versão antiga e a nova de cada linha alterada
CREATE OR REPLACE FUNCTION fn_auditar() RETURNS trigger AS $$
BEGIN
    IF ROW(OLD.*) IS DISTINCT FROM ROW(NEW.*) THEN
        INSERT INTO auditoria (tabela, operacao, dados_antigos, dados_novos)
        VALUES (TG_TABLE_NAME, TG_OP, to_jsonb(OLD), to_jsonb(NEW));
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Tabelas de factos e registos: só se acrescentam linhas (sem UPDATE, DELETE nem TRUNCATE)
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['historico_precos','alertas','logs_execucao','precos_brutos','rejeitados','auditoria'] LOOP
        EXECUTE format('CREATE OR REPLACE TRIGGER trg_%s_so_acrescentar BEFORE UPDATE OR DELETE ON %I FOR EACH ROW EXECUTE FUNCTION fn_bloquear()', t, t);
        EXECUTE format('CREATE OR REPLACE TRIGGER trg_%s_sem_truncate BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear()', t, t);
    END LOOP;
END;
$$;

-- Tabelas de referência: podem ser atualizadas (DB Merge), mas cada alteração fica na auditoria; DELETE e TRUNCATE proibidos
DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY['lojas','produtos','precos_alvo','taxas_cambio','taxas_iva'] LOOP
        EXECUTE format('CREATE OR REPLACE TRIGGER trg_%s_sem_delete BEFORE DELETE ON %I FOR EACH ROW EXECUTE FUNCTION fn_bloquear()', t, t);
        EXECUTE format('CREATE OR REPLACE TRIGGER trg_%s_sem_truncate BEFORE TRUNCATE ON %I FOR EACH STATEMENT EXECUTE FUNCTION fn_bloquear()', t, t);
        EXECUTE format('CREATE OR REPLACE TRIGGER trg_%s_auditar AFTER UPDATE ON %I FOR EACH ROW EXECUTE FUNCTION fn_auditar()', t, t);
    END LOOP;
END;
$$;

-- Impede também apagar tabelas inteiras (DROP TABLE), por exemplo pela opção
-- "Remove existing table" do nó DB Writer do KNIME.
-- Para uma reinicialização deliberada em desenvolvimento: ALTER EVENT TRIGGER trg_sem_drop DISABLE;
CREATE OR REPLACE FUNCTION fn_bloquear_drop() RETURNS event_trigger AS $$
BEGIN
    RAISE EXCEPTION 'Comando % proibido: as tabelas deste sistema nunca são eliminadas.', TG_TAG;
END;
$$ LANGUAGE plpgsql;

DROP EVENT TRIGGER IF EXISTS trg_sem_drop;
CREATE EVENT TRIGGER trg_sem_drop ON ddl_command_start
    WHEN TAG IN ('DROP TABLE', 'DROP SCHEMA')
    EXECUTE FUNCTION fn_bloquear_drop();

-- Último custo total de cada produto em cada loja
CREATE OR REPLACE VIEW v_ultimo_preco AS
SELECT DISTINCT ON (ean, loja) ean, loja, preco_original, moeda, custo_total_eur, registado_em
FROM historico_precos
ORDER BY ean, loja, registado_em DESC;

-- Melhor loja (menor custo total) por produto, com poupança face à loja PT
CREATE OR REPLACE VIEW v_melhor_loja AS
SELECT p.ean, p.titulo, m.loja AS melhor_loja, m.custo_total_eur AS melhor_custo,
       pt.custo_total_eur AS custo_pt,
       ROUND((pt.custo_total_eur - m.custo_total_eur) / pt.custo_total_eur * 100, 2) AS poupanca_pct
FROM produtos p
JOIN LATERAL (SELECT loja, custo_total_eur FROM v_ultimo_preco u
              WHERE u.ean = p.ean ORDER BY custo_total_eur LIMIT 1) m ON TRUE
LEFT JOIN v_ultimo_preco pt ON pt.ean = p.ean AND pt.loja = 'PT';

-- Só preços positivos (portes podem ser 0 = grátis)
ALTER TABLE historico_precos DROP CONSTRAINT IF EXISTS chk_precos_positivos;
ALTER TABLE historico_precos ADD CONSTRAINT chk_precos_positivos
    CHECK (preco_original > 0 AND preco_eur > 0 AND portes_original >= 0 AND portes_eur >= 0 AND custo_total_eur > 0);
ALTER TABLE precos_alvo DROP CONSTRAINT IF EXISTS chk_alvo_positivo;
ALTER TABLE precos_alvo ADD CONSTRAINT chk_alvo_positivo CHECK (preco_alvo_eur > 0);