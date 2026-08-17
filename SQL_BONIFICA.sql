-- ============================================================================
-- SCRIPT DI BONIFICA E PREVENZIONE DUPLICATI
-- ============================================================================
-- ⚠️ ATTENZIONE: Esegui questi script SOLO DOPO BACKUP del database!
-- Data: 17 Agosto 2026

-- ============================================================================
-- FASE 1: BACKUP RECORDS DUPLICATI (FACOLTATIVO - Per Audit Trail)
-- ============================================================================

-- Se vuoi conservare un log dei record eliminati, esegui questo prima della bonifica:
-- CREATE TABLE IF NOT EXISTS _backup_duplicati AS
-- SELECT 'iscrizioni_corsi' as tabella, to_jsonb(ic.*) as record_data, NOW() as deleted_at
-- FROM iscrizioni_corsi ic
-- WHERE (ic.socio_id, ic.nome_corso) IN (
--     SELECT socio_id, nome_corso FROM iscrizioni_corsi GROUP BY socio_id, nome_corso HAVING COUNT(*) > 1
-- );

-- ============================================================================
-- FASE 2: BONIFICA ISCRIZIONI_CORSI
-- ============================================================================

-- Passo 1: Elimina iscrizioni duplicate (mantieni la più recente)
WITH duplicati AS (
    SELECT 
        socio_id,
        nome_corso,
        id,
        ROW_NUMBER() OVER (PARTITION BY socio_id, nome_corso ORDER BY data_iscrizione DESC) as rn
    FROM iscrizioni_corsi
)
DELETE FROM iscrizioni_corsi
WHERE id IN (
    SELECT id FROM duplicati WHERE rn > 1
);

-- Passo 2: Aggiungi vincolo UNIQUE per prevenire futuri duplicati
ALTER TABLE iscrizioni_corsi 
ADD CONSTRAINT unique_socio_corso_iscrizione 
UNIQUE (socio_id, nome_corso);

-- ============================================================================
-- FASE 3: BONIFICA PAGAMENTI
-- ============================================================================

-- Passo 1: Elimina pagamenti duplicati (mantieni il più recente)
WITH pagamenti_duplicati AS (
    SELECT 
        socio_id,
        mese_riferimento,
        anno_riferimento,
        corso,
        id,
        ROW_NUMBER() OVER (
            PARTITION BY socio_id, mese_riferimento, anno_riferimento, corso 
            ORDER BY data_pagamento DESC
        ) as rn
    FROM pagamenti
)
DELETE FROM pagamenti
WHERE id IN (
    SELECT id FROM pagamenti_duplicati WHERE rn > 1
);

-- Passo 2: Aggiungi vincolo UNIQUE
ALTER TABLE pagamenti 
ADD CONSTRAINT unique_socio_pagamento_mensile 
UNIQUE (socio_id, mese_riferimento, anno_riferimento, corso);

-- ============================================================================
-- FASE 4: BONIFICA PRESENZE
-- ============================================================================

-- Passo 1: Elimina presenze duplicate (mantieni la più recente)
WITH presenze_duplicati AS (
    SELECT 
        socio_id,
        DATE(data_presenza) as data,
        corso,
        id,
        ROW_NUMBER() OVER (
            PARTITION BY socio_id, DATE(data_presenza), corso 
            ORDER BY data_presenza DESC
        ) as rn
    FROM presenze
)
DELETE FROM presenze
WHERE id IN (
    SELECT id FROM presenze_duplicati WHERE rn > 1
);

-- Passo 2: Aggiungi indice UNIQUE (PostgreSQL richiede indice con espressione per DATE)
CREATE UNIQUE INDEX idx_presenze_unique_socio_data_corso 
ON presenze (socio_id, DATE(data_presenza), corso);

-- ============================================================================
-- FASE 5: BONIFICA CORSI (Consolidamento Varianti Case-Insensitive)
-- ============================================================================

-- Passo 1: Identifica variante principale per ogni corso (più recente per ID)
WITH corsi_consolidati AS (
    SELECT 
        LOWER(TRIM(nome_corso)) as nome_normalizzato,
        id,
        nome_corso,
        ROW_NUMBER() OVER (PARTITION BY LOWER(TRIM(nome_corso)) ORDER BY id ASC) as rn
    FROM corsi
)
-- Passo 2: Aggiorna iscrizioni_corsi verso la variante principale
UPDATE iscrizioni_corsi ic
SET nome_corso = (
    SELECT nome_corso 
    FROM corsi_consolidati cc
    WHERE LOWER(TRIM(cc.nome_corso)) = LOWER(TRIM(ic.nome_corso))
    AND cc.rn = 1
    LIMIT 1
)
WHERE LOWER(TRIM(nome_corso)) IN (
    SELECT LOWER(TRIM(nome_corso)) 
    FROM corsi 
    GROUP BY LOWER(TRIM(nome_corso)) 
    HAVING COUNT(*) > 1
);

-- Passo 3: Aggiorna presenze verso la variante principale
UPDATE presenze p
SET corso = (
    SELECT nome_corso 
    FROM corsi_consolidati cc
    WHERE LOWER(TRIM(cc.nome_corso)) = LOWER(TRIM(p.corso))
    AND cc.rn = 1
    LIMIT 1
)
WHERE LOWER(TRIM(corso)) IN (
    SELECT LOWER(TRIM(nome_corso)) 
    FROM corsi 
    GROUP BY LOWER(TRIM(nome_corso)) 
    HAVING COUNT(*) > 1
);

-- Passo 4: Aggiorna pagamenti verso la variante principale
UPDATE pagamenti pa
SET corso = (
    SELECT nome_corso 
    FROM corsi_consolidati cc
    WHERE LOWER(TRIM(cc.nome_corso)) = LOWER(TRIM(pa.corso))
    AND cc.rn = 1
    LIMIT 1
)
WHERE LOWER(TRIM(corso)) IN (
    SELECT LOWER(TRIM(nome_corso)) 
    FROM corsi 
    GROUP BY LOWER(TRIM(nome_corso)) 
    HAVING COUNT(*) > 1
);

-- Passo 5: Elimina le varianti duplicate di corsi
DELETE FROM corsi
WHERE id NOT IN (
    SELECT id 
    FROM corsi_consolidati 
    WHERE rn = 1
);

-- Passo 6: Aggiungi indice UNIQUE case-insensitive (PostgreSQL richiede indice con espressione)
CREATE UNIQUE INDEX idx_corsi_unique_nome_insensitive 
ON corsi (LOWER(TRIM(nome_corso)));

-- ============================================================================
-- FASE 6: VERIFICA POST-BONIFICA
-- ============================================================================

-- Query di verifica: Conferma che non ci sono più duplicati
SELECT 
    'iscrizioni_corsi' as tabella,
    COUNT(*) as numero_duplicati
FROM (
    SELECT socio_id, nome_corso, COUNT(*) as cnt
    FROM iscrizioni_corsi
    GROUP BY socio_id, nome_corso
    HAVING COUNT(*) > 1
) AS t
UNION ALL
SELECT 
    'pagamenti' as tabella,
    COUNT(*) as numero_duplicati
FROM (
    SELECT socio_id, mese_riferimento, anno_riferimento, corso, COUNT(*) as cnt
    FROM pagamenti
    GROUP BY socio_id, mese_riferimento, anno_riferimento, corso
    HAVING COUNT(*) > 1
) AS t
UNION ALL
SELECT 
    'presenze' as tabella,
    COUNT(*) as numero_duplicati
FROM (
    SELECT socio_id, DATE(data_presenza), corso, COUNT(*) as cnt
    FROM presenze
    GROUP BY socio_id, DATE(data_presenza), corso
    HAVING COUNT(*) > 1
) AS t
UNION ALL
SELECT 
    'corsi' as tabella,
    COUNT(*) as numero_duplicati
FROM (
    SELECT LOWER(TRIM(nome_corso)), COUNT(*) as cnt
    FROM corsi
    GROUP BY LOWER(TRIM(nome_corso))
    HAVING COUNT(*) > 1
) AS t;

-- ============================================================================
-- FASE 7: VERIFICA INTEGRITÀ REFERENZIALE POST-BONIFICA
-- ============================================================================

-- Verifica che non rimangono orfani in iscrizioni_corsi
SELECT COUNT(*) as orphaned_iscrizioni
FROM iscrizioni_corsi ic
WHERE ic.socio_id NOT IN (SELECT id FROM soci);

-- Verifica che non rimangono orfani in presenze
SELECT COUNT(*) as orphaned_presenze
FROM presenze p
WHERE p.socio_id NOT IN (SELECT id FROM soci);

-- Verifica che non rimangono orfani in pagamenti
SELECT COUNT(*) as orphaned_pagamenti
FROM pagamenti pa
WHERE pa.socio_id NOT IN (SELECT id FROM soci);

-- ============================================================================
-- NOTE IMPORTANTI
-- ============================================================================
-- Se hai vincoli UNIQUE nel tuo schema, ti potrebbe dareconflitti
-- durante l'esecuzione. In tal caso:
-- 1. Commenta la sezione "ADD CONSTRAINT"
-- 2. Verifica che i vincoli già esistono con:
--    SELECT constraint_name FROM information_schema.table_constraints 
--    WHERE table_name = 'nome_tabella'
-- 3. Se non esistono, aggiungili DOPO la bonifica

