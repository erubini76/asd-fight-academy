-- ============================================================================
-- SCRIPT: AGGIUNTA VINCOLI UNIQUE TRAMITE UNIQUE INDEX
-- ============================================================================
-- Usa CREATE UNIQUE INDEX per tutti e tre (più affidabile di ALTER TABLE)
-- Data: 17 Agosto 2026

-- ============================================================================
-- PASSO 1: VINCOLO UNIQUE PER ISCRIZIONI_CORSI (se non esiste)
-- ============================================================================

DROP INDEX IF EXISTS idx_iscrizioni_corsi_unique_socio_corso;

CREATE UNIQUE INDEX idx_iscrizioni_corsi_unique_socio_corso 
ON iscrizioni_corsi (socio_id, nome_corso)
WHERE (socio_id IS NOT NULL AND nome_corso IS NOT NULL);

-- ============================================================================
-- PASSO 2: VINCOLO UNIQUE PER PAGAMENTI (se non esiste)
-- ============================================================================

DROP INDEX IF EXISTS idx_pagamenti_unique_socio_mese_anno_corso;

CREATE UNIQUE INDEX idx_pagamenti_unique_socio_mese_anno_corso 
ON pagamenti (socio_id, mese_riferimento, anno_riferimento, corso)
WHERE (socio_id IS NOT NULL AND mese_riferimento IS NOT NULL AND anno_riferimento IS NOT NULL AND corso IS NOT NULL);

-- ============================================================================
-- VERIFICA FINALE: MOSTRA TUTTI GLI INDICI CREATI
-- ============================================================================

SELECT 
    indexname,
    tablename,
    indexdef
FROM pg_indexes
WHERE tablename IN ('iscrizioni_corsi', 'pagamenti', 'presenze')
AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;
