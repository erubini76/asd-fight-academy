-- ============================================================================
-- SCRIPT: POLICY RLS PRODUZIONE
-- ============================================================================
-- Questo script è pensato per un ambiente di produzione reale.
-- Non usare patch permissive tipo 'TO anon USING (true)' su database di produzione.
-- Data: 17 Agosto 2026

-- ============================================================================
-- 1) ABILITAZIONE RLS
-- ============================================================================
ALTER TABLE iscrizioni_corsi ENABLE ROW LEVEL SECURITY;
ALTER TABLE pagamenti ENABLE ROW LEVEL SECURITY;
ALTER TABLE presenze ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- 2) POLICY PER iscrizioni_corsi
-- ============================================================================
-- Gli utenti autenticati possono leggere e inserire solo le proprie iscrizioni.
DROP POLICY IF EXISTS "utenti_possono_leggere_le_proprie_iscrizioni" ON iscrizioni_corsi;
DROP POLICY IF EXISTS "utenti_possono_inserire_le_proprie_iscrizioni" ON iscrizioni_corsi;

CREATE POLICY "utenti_possono_leggere_le_proprie_iscrizioni"
ON iscrizioni_corsi
FOR SELECT
TO authenticated
USING (socio_id = auth.uid());

CREATE POLICY "utenti_possono_inserire_le_proprie_iscrizioni"
ON iscrizioni_corsi
FOR INSERT
TO authenticated
WITH CHECK (socio_id = auth.uid());

-- ============================================================================
-- 3) POLICY PER pagamenti
-- ============================================================================
DROP POLICY IF EXISTS "utenti_possono_leggere_i_propri_pagamenti" ON pagamenti;
DROP POLICY IF EXISTS "utenti_possono_inserire_i_propri_pagamenti" ON pagamenti;

CREATE POLICY "utenti_possono_leggere_i_propri_pagamenti"
ON pagamenti
FOR SELECT
TO authenticated
USING (socio_id = auth.uid());

CREATE POLICY "utenti_possono_inserire_i_propri_pagamenti"
ON pagamenti
FOR INSERT
TO authenticated
WITH CHECK (socio_id = auth.uid());

-- ============================================================================
-- 4) POLICY PER presenze
-- ============================================================================
DROP POLICY IF EXISTS "utenti_possono_leggere_le_proprie_presenze" ON presenze;
DROP POLICY IF EXISTS "utenti_possono_inserire_le_proprie_presenze" ON presenze;

CREATE POLICY "utenti_possono_leggere_le_proprie_presenze"
ON presenze
FOR SELECT
TO authenticated
USING (socio_id = auth.uid());

CREATE POLICY "utenti_possono_inserire_le_proprie_presenze"
ON presenze
FOR INSERT
TO authenticated
WITH CHECK (socio_id = auth.uid());

-- ============================================================================
-- 5) POLICY ADMIN (se hai una tabella profiles con ruolo admin)
-- ============================================================================
-- Se sul tuo schema esiste una tabella profiles con la colonna ruolo, puoi
-- abilitare anche il ruolo admin in modo controllato.

-- Esempio:
-- CREATE POLICY "admin_gestisce_tutto_iscrizioni_corsi"
-- ON iscrizioni_corsi
-- FOR ALL
-- TO authenticated
-- USING (
--   EXISTS (
--     SELECT 1 FROM profiles p
--     WHERE p.id = auth.uid() AND p.ruolo = 'admin'
--   )
-- )
-- WITH CHECK (
--   EXISTS (
--     SELECT 1 FROM profiles p
--     WHERE p.id = auth.uid() AND p.ruolo = 'admin'
--   )
-- );

-- ============================================================================
-- 6) NOTE IMPORTANTI
-- ============================================================================
-- Questo script è pensato per ambiente di produzione e non contiene workaround
-- di test tipo 'TO anon WITH CHECK (true)'.
-- In ambiente di test, invece, può essere necessario un diverso setup
-- temporaneo, ma vanno mantenuti separati da un database o da script dedicati.
