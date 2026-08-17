-- ============================================================================
-- SCRIPT DI DIAGNOSI - REGISTRI DUPLICATI NEL DATABASE
-- ============================================================================
-- Esegui questi query nel Supabase Query Editor per identificare i duplicati
-- Data: 17 Agosto 2026

-- ============================================================================
-- PARTE 1: ISCRIZIONI_CORSI - Identificazione Duplicati
-- ============================================================================

-- Query 1: Iscrizioni duplicate per lo stesso socio-corso
SELECT 
    socio_id,
    nome_corso,
    COUNT(*) as numero_duplicati,
    array_agg(id ORDER BY data_iscrizione DESC) as ids_record,
    array_agg(data_iscrizione ORDER BY data_iscrizione DESC) as date_iscrizione
FROM iscrizioni_corsi
GROUP BY socio_id, nome_corso
HAVING COUNT(*) > 1
ORDER BY numero_duplicati DESC;

-- Query 2: Elenco completo di soci con iscrizioni multiple
SELECT 
    ic.socio_id,
    s.nome,
    s.cognome,
    s.codice_fiscale,
    ic.nome_corso,
    ic.data_iscrizione,
    ic.stato,
    ic.id
FROM iscrizioni_corsi ic
JOIN soci s ON ic.socio_id = s.id
WHERE (ic.socio_id, ic.nome_corso) IN (
    SELECT socio_id, nome_corso 
    FROM iscrizioni_corsi 
    GROUP BY socio_id, nome_corso 
    HAVING COUNT(*) > 1
)
ORDER BY s.cognome, s.nome, ic.nome_corso, ic.data_iscrizione DESC;

-- ============================================================================
-- PARTE 2: PAGAMENTI - Identificazione Duplicati
-- ============================================================================

-- Query 3: Pagamenti duplicati per lo stesso mese/anno/socio
SELECT 
    socio_id,
    mese_riferimento,
    anno_riferimento,
    corso,
    COUNT(*) as numero_duplicati,
    array_agg(id) as ids_record,
    array_agg(stato) as stati,
    array_agg(data_pagamento) as date_pagamento
FROM pagamenti
GROUP BY socio_id, mese_riferimento, anno_riferimento, corso
HAVING COUNT(*) > 1
ORDER BY numero_duplicati DESC;

-- Query 4: Dettagli pagamenti duplicati con dati socio
SELECT 
    p.socio_id,
    s.nome,
    s.cognome,
    p.mese_riferimento,
    p.anno_riferimento,
    p.corso,
    p.data_pagamento,
    p.stato,
    p.importo,
    p.id
FROM pagamenti p
JOIN soci s ON p.socio_id = s.id
WHERE (p.socio_id, p.mese_riferimento, p.anno_riferimento, p.corso) IN (
    SELECT socio_id, mese_riferimento, anno_riferimento, corso
    FROM pagamenti
    GROUP BY socio_id, mese_riferimento, anno_riferimento, corso
    HAVING COUNT(*) > 1
)
ORDER BY s.cognome, s.nome, p.anno_riferimento DESC, p.mese_riferimento DESC;

-- ============================================================================
-- PARTE 3: PRESENZE - Identificazione Duplicati
-- ============================================================================

-- Query 5: Presenze duplicate per lo stesso socio-data-corso
SELECT 
    socio_id,
    DATE(data_presenza) as data,
    corso,
    COUNT(*) as numero_duplicati,
    array_agg(id) as ids_record
FROM presenze
GROUP BY socio_id, DATE(data_presenza), corso
HAVING COUNT(*) > 1
ORDER BY numero_duplicati DESC;

-- Query 6: Dettagli presenze duplicate
SELECT 
    p.socio_id,
    s.nome,
    s.cognome,
    DATE(p.data_presenza) as data,
    p.corso,
    p.id,
    p.data_presenza
FROM presenze p
JOIN soci s ON p.socio_id = s.id
WHERE (p.socio_id, DATE(p.data_presenza), p.corso) IN (
    SELECT socio_id, DATE(data_presenza), corso
    FROM presenze
    GROUP BY socio_id, DATE(data_presenza), corso
    HAVING COUNT(*) > 1
)
ORDER BY s.cognome, s.nome, p.data_presenza DESC;

-- ============================================================================
-- PARTE 4: CORSI - Identificazione Duplicati (Case-Insensitive)
-- ============================================================================

-- Query 7: Corsi duplicati per variazioni case
SELECT 
    LOWER(TRIM(nome_corso)) as nome_normalizzato,
    COUNT(*) as numero_varianti,
    array_agg(DISTINCT nome_corso) as varianti,
    array_agg(id) as ids_record
FROM corsi
GROUP BY LOWER(TRIM(nome_corso))
HAVING COUNT(*) > 1
ORDER BY numero_varianti DESC;

-- ============================================================================
-- PARTE 5: DISCREPANZE REFERENZIALI
-- ============================================================================

-- Query 8: Corsi referenziati in iscrizioni_corsi che non esistono in corsi
SELECT DISTINCT 
    ic.nome_corso,
    COUNT(*) as numero_iscrizioni
FROM iscrizioni_corsi ic
WHERE ic.nome_corso NOT IN (SELECT nome_corso FROM corsi)
GROUP BY ic.nome_corso
ORDER BY numero_iscrizioni DESC;

-- Query 9: Corsi referenziati in presenze che non esistono in corsi
SELECT DISTINCT 
    p.corso,
    COUNT(*) as numero_presenze
FROM presenze p
WHERE p.corso NOT IN (SELECT nome_corso FROM corsi)
GROUP BY p.corso
ORDER BY numero_presenze DESC;

-- Query 10: Corsi referenziati in pagamenti che non esistono in corsi
SELECT DISTINCT 
    pa.corso,
    COUNT(*) as numero_pagamenti
FROM pagamenti pa
WHERE pa.corso NOT IN (SELECT nome_corso FROM corsi)
GROUP BY pa.corso
ORDER BY numero_pagamenti DESC;

-- ============================================================================
-- PARTE 6: STATISTICHE GENERALI
-- ============================================================================

-- Query 11: Riepilogo complessivo dei potenziali problemi
SELECT 
    'iscrizioni_corsi' as tabella,
    COUNT(*) as numero_problemi
FROM (
    SELECT socio_id, nome_corso, COUNT(*) as cnt
    FROM iscrizioni_corsi
    GROUP BY socio_id, nome_corso
    HAVING COUNT(*) > 1
) AS t
UNION ALL
SELECT 
    'pagamenti' as tabella,
    COUNT(*) as numero_problemi
FROM (
    SELECT socio_id, mese_riferimento, anno_riferimento, corso, COUNT(*) as cnt
    FROM pagamenti
    GROUP BY socio_id, mese_riferimento, anno_riferimento, corso
    HAVING COUNT(*) > 1
) AS t
UNION ALL
SELECT 
    'presenze' as tabella,
    COUNT(*) as numero_problemi
FROM (
    SELECT socio_id, DATE(data_presenza), corso, COUNT(*) as cnt
    FROM presenze
    GROUP BY socio_id, DATE(data_presenza), corso
    HAVING COUNT(*) > 1
) AS t
UNION ALL
SELECT 
    'corsi' as tabella,
    COUNT(*) as numero_problemi
FROM (
    SELECT LOWER(TRIM(nome_corso)), COUNT(*) as cnt
    FROM corsi
    GROUP BY LOWER(TRIM(nome_corso))
    HAVING COUNT(*) > 1
) AS t;
