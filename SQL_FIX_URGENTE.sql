-- ============================================================================
-- FIX URGENTE — FASE 1: Ripristino funzionale immediato (Go-Live Ago 2026)
-- 1) relazione ambigua soci/iscrizioni_corsi  2) RLS blocca anon  3) anti-duplicati
-- Esegui questo script nel SQL Editor di Supabase (progetto di produzione)
-- La Fase 2 (migrazione scritture su API/service_role) è rimandata a Settembre.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- STEP 1: Diagnosi FK duplicate tra iscrizioni_corsi e soci
-- ----------------------------------------------------------------------------
SELECT conname, pg_get_constraintdef(oid) AS definizione
FROM pg_constraint
WHERE conrelid = 'iscrizioni_corsi'::regclass
  AND confrelid = 'soci'::regclass;

-- ----------------------------------------------------------------------------
-- STEP 2: Rimuove automaticamente le FK duplicate su socio_id, mantenendone una sola
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  keep_name text;
  r record;
BEGIN
  SELECT conname INTO keep_name
  FROM pg_constraint
  WHERE conrelid = 'iscrizioni_corsi'::regclass
    AND confrelid = 'soci'::regclass
    AND pg_get_constraintdef(oid) LIKE '%(socio_id)%'
  ORDER BY oid
  LIMIT 1;

  IF keep_name IS NULL THEN
    RAISE NOTICE 'Nessuna FK su socio_id trovata: verificare manualmente.';
    RETURN;
  END IF;

  FOR r IN
    SELECT conname
    FROM pg_constraint
    WHERE conrelid = 'iscrizioni_corsi'::regclass
      AND confrelid = 'soci'::regclass
      AND pg_get_constraintdef(oid) LIKE '%(socio_id)%'
      AND conname <> keep_name
  LOOP
    EXECUTE format('ALTER TABLE iscrizioni_corsi DROP CONSTRAINT %I', r.conname);
    RAISE NOTICE 'Rimossa FK duplicata: %', r.conname;
  END LOOP;

  RAISE NOTICE 'FK mantenuta: %', keep_name;
END $$;

-- ----------------------------------------------------------------------------
-- STEP 3: Policy RLS permissive per il ruolo anon (operatività client Fase 1)
-- L'app non usa Supabase Auth: tutte le richieste dal frontend viaggiano con
-- la chiave anon. Le policy basate su auth.uid() sono sempre false per anon
-- e bloccano ogni scrittura: vanno sostituite su tutte le tabelle coinvolte.
-- Lo script è idempotente: verifica l'esistenza della tabella prima di agire,
-- così copre anche 'pagamento_soci' se presente nel tuo schema.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  tbl text;
  tabelle text[] := ARRAY['soci', 'iscrizioni_corsi', 'pagamenti', 'presenze', 'pagamento_soci'];
  pol record;
BEGIN
  FOREACH tbl IN ARRAY tabelle LOOP
    IF to_regclass(tbl) IS NULL THEN
      RAISE NOTICE 'Tabella % non trovata, salto.', tbl;
      CONTINUE;
    END IF;

    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', tbl);

    -- Rimuove tutte le policy esistenti sulla tabella (vecchie regole auth.uid())
    FOR pol IN
      SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = tbl
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON %I', pol.policyname, tbl);
    END LOOP;

    EXECUTE format(
      'CREATE POLICY %I ON %I FOR SELECT TO anon, authenticated USING (true)',
      tbl || '_anon_select', tbl
    );
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR INSERT TO anon, authenticated WITH CHECK (true)',
      tbl || '_anon_insert', tbl
    );
    EXECUTE format(
      'CREATE POLICY %I ON %I FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true)',
      tbl || '_anon_update', tbl
    );

    RAISE NOTICE 'Policy anon applicate su tabella: %', tbl;
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- STEP 4: Indice anti-duplicati case/spazi-insensitive su iscrizioni_corsi
-- Nota: l'upsert dell'app usa onConflict 'socio_id,nome_corso' (match esatto),
-- che resta valido grazie all'indice univoco esistente (RT-01). Questo nuovo
-- indice è una barriera aggiuntiva a livello DB contro varianti maiuscole/
-- spazi dello stesso corso; se esistono già duplicati "quasi uguali", la
-- CREATE INDEX sottostante fallisce segnalandoli (da bonificare a parte).
-- ----------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS iscrizioni_corsi_socio_nome_norm_uidx
  ON iscrizioni_corsi (socio_id, LOWER(TRIM(nome_corso)));

-- ============================================================================
-- NOTA IMPORTANTE SULLA SICUREZZA (da chiudere in Fase 2 - Settembre)
-- ============================================================================
-- Queste policy tornano permissive quanto era prima di applicare
-- SQL_POLICY_PROD.sql: chiunque conosca la chiave anon (pubblica, presente
-- nel frontend) può leggere/scrivere su queste tabelle. Non è possibile fare
-- di meglio con RLS finché l'app non implementa un vero login Supabase Auth
-- (o valida le scritture lato server con una chiave service_role in una
-- funzione API, es. dentro api/), perché senza sessione autenticata
-- auth.uid() è sempre NULL e nessuna policy restrittiva può funzionare.
-- ============================================================================
