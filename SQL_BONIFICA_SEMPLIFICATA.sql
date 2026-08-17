-- ============================================================================
-- SCRIPT DI BONIFICA SEMPLIFICATA - SOLO ELIMINAZIONE DUPLICATI
-- ============================================================================
-- Elimina i 31 duplicati SENZA aggiungere vincoli
-- Esegui uno step alla volta per identificare eventuali errori
-- Data: 17 Agosto 2026

-- ============================================================================
-- STEP 1: ELIMINA DUPLICATI ISCRIZIONI_CORSI (12 record)
-- ============================================================================

DELETE FROM iscrizioni_corsi
WHERE id IN (
    WITH ranked AS (
        SELECT 
            id,
            ROW_NUMBER() OVER (PARTITION BY socio_id, nome_corso ORDER BY data_iscrizione DESC) as rn
        FROM iscrizioni_corsi
    )
    SELECT id FROM ranked WHERE rn > 1
);

-- Verifica risultato
SELECT 'Iscrizioni eliminate' as step, COUNT(*) as duplicati_rimasti
FROM (
    SELECT socio_id, nome_corso, COUNT(*) 
    FROM iscrizioni_corsi 
    GROUP BY socio_id, nome_corso 
    HAVING COUNT(*) > 1
) t;

-- ============================================================================
-- STEP 2: ELIMINA DUPLICATI PAGAMENTI (5 record)
-- ============================================================================

DELETE FROM pagamenti
WHERE id IN (
    WITH ranked AS (
        SELECT 
            id,
            ROW_NUMBER() OVER (PARTITION BY socio_id, mese_riferimento, anno_riferimento, corso ORDER BY data_pagamento DESC) as rn
        FROM pagamenti
    )
    SELECT id FROM ranked WHERE rn > 1
);

-- Verifica risultato
SELECT 'Pagamenti eliminati' as step, COUNT(*) as duplicati_rimasti
FROM (
    SELECT socio_id, mese_riferimento, anno_riferimento, corso, COUNT(*) 
    FROM pagamenti 
    GROUP BY socio_id, mese_riferimento, anno_riferimento, corso 
    HAVING COUNT(*) > 1
) t;

-- ============================================================================
-- STEP 3: ELIMINA DUPLICATI PRESENZE (14 record)
-- ============================================================================

DELETE FROM presenze
WHERE id IN (
    WITH ranked AS (
        SELECT 
            id,
            ROW_NUMBER() OVER (PARTITION BY socio_id, DATE(data_presenza), corso ORDER BY data_presenza DESC) as rn
        FROM presenze
    )
    SELECT id FROM ranked WHERE rn > 1
);

-- Verifica risultato
SELECT 'Presenze eliminate' as step, COUNT(*) as duplicati_rimasti
FROM (
    SELECT socio_id, DATE(data_presenza), corso, COUNT(*) 
    FROM presenze 
    GROUP BY socio_id, DATE(data_presenza), corso 
    HAVING COUNT(*) > 1
) t;

-- ============================================================================
-- VERIFICA FINALE: Conferma che tutti i 31 duplicati sono stati eliminati
-- ============================================================================

SELECT 
    tabella,
    numero_duplicati,
    CASE 
        WHEN numero_duplicati = 0 THEN '✅ OK'
        ELSE '❌ ERRORE'
    END as stato
FROM (
    SELECT 'iscrizioni_corsi' as tabella, COUNT(*) as numero_duplicati
    FROM (
        SELECT socio_id, nome_corso, COUNT(*) as cnt
        FROM iscrizioni_corsi
        GROUP BY socio_id, nome_corso
        HAVING COUNT(*) > 1
    ) t
    UNION ALL
    SELECT 'pagamenti', COUNT(*)
    FROM (
        SELECT socio_id, mese_riferimento, anno_riferimento, corso, COUNT(*) as cnt
        FROM pagamenti
        GROUP BY socio_id, mese_riferimento, anno_riferimento, corso
        HAVING COUNT(*) > 1
    ) t
    UNION ALL
    SELECT 'presenze', COUNT(*)
    FROM (
        SELECT socio_id, DATE(data_presenza), corso, COUNT(*) as cnt
        FROM presenze
        GROUP BY socio_id, DATE(data_presenza), corso
        HAVING COUNT(*) > 1
    ) t
) results
ORDER BY numero_duplicati DESC;
