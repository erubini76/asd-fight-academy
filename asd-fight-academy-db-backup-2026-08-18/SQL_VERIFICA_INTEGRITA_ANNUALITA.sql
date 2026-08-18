-- ============================================================================
-- VERIFICA INTEGRITA ANNUALITA E STORICO - SOLO LETTURA
--
-- Questo script non modifica dati, tabelle, vincoli o indici.
-- Eseguire le sezioni 1-5 PRIMA della migrazione.
-- Eseguire nuovamente l'intero script DOPO la migrazione.
-- Un risultato diverso da zero va analizzato prima di procedere.
-- ============================================================================

-- 1. Presenza delle tabelle e tipo delle chiavi principali.
SELECT table_name, column_name, data_type, udt_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND ((table_name = 'soci' AND column_name = 'id')
    OR (table_name = 'iscrizioni_corsi' AND column_name = 'socio_id')
    OR (table_name = 'pagamenti' AND column_name = 'socio_id'))
ORDER BY table_name, column_name;

-- 2. Duplicati legacy socio/corso: devono essere zero prima della migrazione.
SELECT socio_id, LOWER(TRIM(nome_corso)) AS corso_normalizzato, COUNT(*) AS duplicati
FROM public.iscrizioni_corsi
WHERE socio_id IS NOT NULL AND nome_corso IS NOT NULL
GROUP BY socio_id, LOWER(TRIM(nome_corso))
HAVING COUNT(*) > 1
ORDER BY duplicati DESC;

-- 3. Iscrizioni legacy senza socio valido.
SELECT ic.*
FROM public.iscrizioni_corsi ic
LEFT JOIN public.soci s ON s.id = ic.socio_id
WHERE ic.socio_id IS NULL OR s.id IS NULL;

-- 4. Pagamenti senza socio valido.
SELECT p.id, p.socio_id, p.corso, p.tipo_pagamento, p.stato
FROM public.pagamenti p
LEFT JOIN public.soci s ON s.id = p.socio_id
WHERE p.socio_id IS NULL OR s.id IS NULL;

-- 5. Duplicati pagamento sulla chiave funzionale già prevista.
SELECT socio_id, mese_riferimento, anno_riferimento, corso, COUNT(*) AS duplicati
FROM public.pagamenti
WHERE socio_id IS NOT NULL
GROUP BY socio_id, mese_riferimento, anno_riferimento, corso
HAVING COUNT(*) > 1
ORDER BY duplicati DESC;

-- 6. Copertura della migrazione annuale (solo dopo la migrazione).
SELECT
  (SELECT COUNT(*) FROM public.iscrizioni_corsi) AS iscrizioni_legacy,
  (SELECT COUNT(*) FROM public.iscrizioni_annuali WHERE anno_accademico = '2026/2027') AS snapshot_2026_2027,
  (SELECT COUNT(*) FROM public.documenti_medici) AS documenti_medici,
  (SELECT COUNT(*) FROM public.storico_modifiche) AS modifiche_storico;

-- 7. Duplicati nella nuova tabella: devono essere zero.
SELECT socio_id, LOWER(TRIM(nome_corso)) AS corso_normalizzato,
       anno_accademico, COUNT(*) AS duplicati
FROM public.iscrizioni_annuali
GROUP BY socio_id, LOWER(TRIM(nome_corso)), anno_accademico
HAVING COUNT(*) > 1;

-- 8. Righe annuali senza socio o dati chiave.
SELECT ia.*
FROM public.iscrizioni_annuali ia
LEFT JOIN public.soci s ON s.id = ia.socio_id
WHERE s.id IS NULL
   OR ia.nome_corso IS NULL
   OR ia.anno_accademico IS NULL;

-- 9. Documenti medici senza socio o URL.
SELECT dm.*
FROM public.documenti_medici dm
LEFT JOIN public.soci s ON s.id = dm.socio_id
WHERE s.id IS NULL OR NULLIF(TRIM(dm.file_url), '') IS NULL;

-- 10. Pagamenti annuali non ancora classificati per stagione.
SELECT id, socio_id, corso, tipo_pagamento, anno_riferimento, anno_accademico, stato
FROM public.pagamenti
WHERE tipo_pagamento = 'Iscrizione Annuale'
  AND anno_accademico IS NULL
ORDER BY socio_id, id;

-- 11. Indici e vincoli rilevanti, per confronto prima/dopo.
SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('iscrizioni_corsi', 'iscrizioni_annuali', 'pagamenti', 'documenti_medici', 'storico_modifiche')
ORDER BY tablename, indexname;

-- 12. Foreign key rilevanti.
SELECT conrelid::regclass AS tabella, conname, pg_get_constraintdef(oid) AS definizione
FROM pg_constraint
WHERE contype = 'f'
  AND conrelid::regclass::text IN ('iscrizioni_annuali', 'documenti_medici', 'storico_modifiche')
ORDER BY tabella, conname;