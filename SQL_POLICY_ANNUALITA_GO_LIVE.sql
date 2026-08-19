-- ============================================================================
-- POLICY TEMPORANEE GO-LIVE - ANNUALITA, DOCUMENTI E CONSENSI
--
-- Necessarie per il frontend attuale, che usa la chiave anon Supabase.
-- Coerenti con SQL_FIX_URGENTE.sql: operativita temporanea lato client.
-- Da sostituire nella fase sicurezza server-side con sessioni verificate,
-- Storage privato e policy basate su ruoli/autorizzazioni.
-- ============================================================================

DO $$
DECLARE
  tbl text;
  tabelle text[] := ARRAY[
    'iscrizioni_annuali',
    'documenti_medici',
    'consensi_tesseramento'
  ];
  pol record;
BEGIN
  FOREACH tbl IN ARRAY tabelle LOOP
    IF to_regclass('public.' || tbl) IS NULL THEN
      RAISE EXCEPTION 'Tabella public.% non trovata: eseguire prima la migrazione annualita', tbl;
    END IF;

    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);

    FOR pol IN
      SELECT policyname
      FROM pg_policies
      WHERE schemaname = 'public' AND tablename = tbl
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, tbl);
    END LOOP;

    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT TO anon, authenticated USING (true)',
      tbl || '_go_live_select', tbl
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR INSERT TO anon, authenticated WITH CHECK (true)',
      tbl || '_go_live_insert', tbl
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true)',
      tbl || '_go_live_update', tbl
    );
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR DELETE TO anon, authenticated USING (true)',
      tbl || '_go_live_delete', tbl
    );
  END LOOP;
END $$;

-- Verifica: dopo l'esecuzione devono comparire 4 policy per ciascuna tabella.
SELECT tablename, policyname, cmd
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('iscrizioni_annuali', 'documenti_medici', 'consensi_tesseramento')
ORDER BY tablename, policyname;