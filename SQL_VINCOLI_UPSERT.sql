-- ============================================================================
-- SCRIPT: AGGIUNTA VINCOLI UNIQUE PER SUPPORTARE UPSERT
-- ============================================================================
-- Questo script AGGIUNGE i vincoli UNIQUE necessari per l'UPSERT
-- Deve essere eseguito PRIMA che il codice frontend possa usare .upsert()
-- Data: 17 Agosto 2026

-- ============================================================================
-- PASSO 1: VINCOLO UNIQUE PER ISCRIZIONI_CORSI
-- ============================================================================

-- Verifica se il vincolo esiste già
-- SELECT constraint_name FROM information_schema.table_constraints 
-- WHERE table_name='iscrizioni_corsi' AND constraint_type='UNIQUE';

ALTER TABLE iscrizioni_corsi 
ADD CONSTRAINT unique_socio_corso_iscrizione 
UNIQUE (socio_id, nome_corso);

-- ============================================================================
-- PASSO 2: VINCOLO UNIQUE PER PAGAMENTI
-- ============================================================================

ALTER TABLE pagamenti 
ADD CONSTRAINT unique_socio_pagamento_mensile 
UNIQUE (socio_id, mese_riferimento, anno_riferimento, corso);

-- ============================================================================
-- PASSO 3: VINCOLO UNIQUE PER PRESENZE (con INDEX su espressione DATE)
-- ============================================================================

-- PostgreSQL non supporta UNIQUE con funzioni, quindi usiamo CREATE UNIQUE INDEX
CREATE UNIQUE INDEX idx_presenze_unique_socio_data_corso 
ON presenze (socio_id, DATE(data_presenza), corso)
WHERE (data_presenza IS NOT NULL);

-- ============================================================================
-- VERIFICA FINALE
-- ============================================================================

-- Mostra i vincoli creati
SELECT 
    constraint_name,
    table_name,
    column_name
FROM information_schema.constraint_column_usage
WHERE table_name IN ('iscrizioni_corsi', 'pagamenti')
AND constraint_name LIKE 'unique_%'
ORDER BY table_name, constraint_name;

-- Verifica indici creati
SELECT 
    indexname,
    tablename
FROM pg_indexes
WHERE tablename IN ('iscrizioni_corsi', 'pagamenti', 'presenze')
AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;
