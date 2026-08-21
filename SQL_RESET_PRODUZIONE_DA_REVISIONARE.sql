-- ============================================================================
-- RESET SELETTIVO PRODUZIONE - FIGHT ACADEMY
-- STATO: DA REVISIONARE. NON ESEGUIRE SENZA BACKUP E CONSENSO ESPLICITO.
--
-- Obiettivo:
-- - mantenere il solo account presidente kawasemidojo@gmail.com;
-- - mantenere corsi e configurazioni di corso;
-- - eliminare tesserati, istruttori test, presenze, pagamenti, annualita,
--   documenti, consensi, stati contabili e notifiche applicative.
--
-- Storage NON viene cancellato da questo script: vedere istruzioni a fondo file.
-- Il blocco di conferma causa ROLLBACK per default.
-- ============================================================================

BEGIN;

-- BLOCCO DI SICUREZZA: lasciare questo valore invariato durante la revisione.
-- Solo dopo consenso esplicito sostituire NON_CONFERMATO con:
-- CONFERMO_RESET_PRODUZIONE_FIGHT_ACADEMY
SELECT set_config('app.reset_confirmation', 'NON_CONFERMATO', true);

DO $$
DECLARE
  admin_count integer;
BEGIN
  IF current_setting('app.reset_confirmation', true) <> 'CONFERMO_RESET_PRODUZIONE_FIGHT_ACADEMY' THEN
    RAISE EXCEPTION 'RESET BLOCCATO: rileggi lo script, fai backup e sostituisci il token di conferma solo dopo approvazione esplicita.';
  END IF;

  IF to_regclass('public.istruttori_corsi') IS NULL THEN
    RAISE EXCEPTION 'Tabella istruttori_corsi assente.';
  END IF;

  SELECT COUNT(*) INTO admin_count
  FROM public.istruttori_corsi
  WHERE lower(trim(email)) = 'kawasemidojo@gmail.com'
    AND ruolo = 'presidente';

  IF admin_count <> 1 THEN
    RAISE EXCEPTION 'Reset annullato: atteso esattamente un presidente kawasemidojo@gmail.com, trovati % record.', admin_count;
  END IF;
END $$;

-- Snapshot del solo amministratore da conservare. Se l'account ha un socio_id,
-- il relativo profilo soci viene preservato per non rompere la relazione login.
CREATE TEMP TABLE reset_admin AS
SELECT id AS istruttore_id, socio_id
FROM public.istruttori_corsi
WHERE lower(trim(email)) = 'kawasemidojo@gmail.com'
  AND ruolo = 'presidente';

-- 1. Azzerare stato contabile e riferimenti agli istruttori test.
-- Mantiene soglie e percentuali dei corsi, ma annulla l'istruttore principale.
DELETE FROM public.contabilita_mesi;
UPDATE public.corsi_config_contabile
SET istruttore_principale_id = NULL,
    aggiornato_da = 'reset produzione',
    aggiornato_il = now()
WHERE istruttore_principale_id IS NOT NULL
  AND istruttore_principale_id <> (SELECT istruttore_id FROM reset_admin);

-- 2. Eliminare prima i dati dipendenti dai tesserati.
-- Le DELETE opzionali sono eseguite soltanto se le tabelle esistono.
DO $$
BEGIN
  IF to_regclass('public.storico_modifiche') IS NOT NULL THEN
    EXECUTE 'DELETE FROM public.storico_modifiche';
  END IF;

  IF to_regclass('public.consensi_tesseramento') IS NOT NULL THEN
    EXECUTE 'DELETE FROM public.consensi_tesseramento
             WHERE socio_id IS DISTINCT FROM (SELECT socio_id FROM reset_admin)';
  END IF;

  IF to_regclass('public.documenti_medici') IS NOT NULL THEN
    EXECUTE 'DELETE FROM public.documenti_medici
             WHERE socio_id IS DISTINCT FROM (SELECT socio_id FROM reset_admin)';
  END IF;

  IF to_regclass('public.pagamento_soci') IS NOT NULL THEN
    EXECUTE 'DELETE FROM public.pagamento_soci';
  END IF;
END $$;

DELETE FROM public.presenze
WHERE socio_id IS DISTINCT FROM (SELECT socio_id FROM reset_admin);

DELETE FROM public.pagamenti
WHERE socio_id IS DISTINCT FROM (SELECT socio_id FROM reset_admin);

DELETE FROM public.iscrizioni_annuali
WHERE socio_id IS DISTINCT FROM (SELECT socio_id FROM reset_admin);

DELETE FROM public.iscrizioni_corsi
WHERE socio_id IS DISTINCT FROM (SELECT socio_id FROM reset_admin);

-- 3. Eliminare istruttori di test dopo avere rimosso il riferimento contabile.
DELETE FROM public.istruttori_corsi
WHERE id <> (SELECT istruttore_id FROM reset_admin);

-- 4. Eliminare tutti i tesserati, eccetto l'eventuale profilo collegato al
-- presidente. Se socio_id del presidente e' NULL, vengono eliminati tutti.
DELETE FROM public.soci
WHERE id IS DISTINCT FROM (SELECT socio_id FROM reset_admin);

-- 5. Verifica dentro la transazione: ogni risultato deve essere zero salvo
-- istruttori_corsi (1 presidente), corsi e corsi_config_contabile.
SELECT 'istruttori_non_admin' AS controllo, COUNT(*) AS residui
FROM public.istruttori_corsi
WHERE id <> (SELECT istruttore_id FROM reset_admin)
UNION ALL
SELECT 'soci_non_admin', COUNT(*)
FROM public.soci
WHERE id IS DISTINCT FROM (SELECT socio_id FROM reset_admin)
UNION ALL
SELECT 'presenze', COUNT(*) FROM public.presenze
UNION ALL
SELECT 'pagamenti', COUNT(*) FROM public.pagamenti
UNION ALL
SELECT 'iscrizioni_corsi', COUNT(*) FROM public.iscrizioni_corsi
UNION ALL
SELECT 'iscrizioni_annuali', COUNT(*) FROM public.iscrizioni_annuali
UNION ALL
SELECT 'contabilita_mesi', COUNT(*) FROM public.contabilita_mesi;

SELECT id, nome, email, ruolo, corsi_competenze, corsi_disabilitati
FROM public.istruttori_corsi
WHERE id = (SELECT istruttore_id FROM reset_admin);

SELECT id, nome_corso, categoria, quota_mensile, istruttore, orari
FROM public.corsi
ORDER BY nome_corso;

SELECT nome_corso, categoria, soglia_alunni, perc_istruttore_sotto,
       perc_istruttore_sopra, istruttore_principale_id
FROM public.corsi_config_contabile
ORDER BY nome_corso;

-- NON fare COMMIT senza aver letto i risultati delle SELECT precedenti.
-- In SQL Editor, dopo revisione dei risultati:
--   COMMIT;   -- per applicare definitivamente il reset
-- oppure
--   ROLLBACK; -- per annullare tutto

-- ============================================================================
-- PULIZIA STORAGE DA ESEGUIRE SEPARATAMENTE, DOPO COMMIT E SOLO SE CONFERMATA
-- ============================================================================
-- Da Supabase Storage Dashboard o API server-side, eliminare gli oggetti nei
-- bucket seguenti, lasciando INTEGRO il bucket regolamenti:
--   1) certificati_medici
--   2) ricevute_pagamenti
-- Non eliminare il bucket regolamenti né il file:
--   regolamenti/Anno associativo 2026-27.pdf
-- L'eliminazione dei soli record DB non cancella automaticamente gli oggetti
-- fisici Storage: verificare che i due bucket siano vuoti dopo la pulizia.
