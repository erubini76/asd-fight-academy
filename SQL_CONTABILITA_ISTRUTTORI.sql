-- ============================================================================
-- MIGRAZIONE CONTABILITA ISTRUTTORI - ASD FIGHT ACADEMY
--
-- Scopo:
--   1) configurare soglie/percentuali di riparto Istruttore/Palestra per corso;
--   2) tracciare lo stato mensile (OPEN/LOCKED) del conguaglio per corso;
--   3) permettere un override manuale (quota fissa o percentuale ad hoc) da Admin.
--
-- Eseguire nel SQL Editor Supabase. Non modifica tabelle esistenti (soci,
-- pagamenti, corsi, istruttori_corsi, presenze) se non per lettura.
-- ============================================================================

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.corsi') IS NULL THEN
    RAISE EXCEPTION 'Migrazione annullata: tabella public.corsi assente';
  END IF;
  IF to_regclass('public.istruttori_corsi') IS NULL THEN
    RAISE EXCEPTION 'Migrazione annullata: tabella public.istruttori_corsi assente';
  END IF;
END $$;

-- 1. Configurazione soglie/percentuali e istruttore principale per corso.
CREATE TABLE IF NOT EXISTS public.corsi_config_contabile (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome_corso text NOT NULL UNIQUE,
  categoria text NOT NULL DEFAULT 'Adulti',
  soglia_alunni integer NOT NULL DEFAULT 7,
  perc_istruttore_sotto numeric(5,2) NOT NULL DEFAULT 50,
  perc_istruttore_sopra numeric(5,2) NOT NULL DEFAULT 60,
  istruttore_principale_id bigint REFERENCES public.istruttori_corsi(id) ON DELETE SET NULL,
  aggiornato_da text,
  aggiornato_il timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT corsi_config_contabile_perc_chk
    CHECK (perc_istruttore_sotto BETWEEN 0 AND 100 AND perc_istruttore_sopra BETWEEN 0 AND 100)
);

-- 2. Stato mensile del conguaglio per corso (lock + override).
CREATE TABLE IF NOT EXISTS public.contabilita_mesi (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome_corso text NOT NULL,
  mese integer NOT NULL CHECK (mese BETWEEN 1 AND 12),
  anno integer NOT NULL,
  stato text NOT NULL DEFAULT 'OPEN' CHECK (stato IN ('OPEN', 'LOCKED')),
  is_custom_override boolean NOT NULL DEFAULT false,
  tipo_override text CHECK (tipo_override IN ('fisso', 'percentuale')),
  valore_override numeric(10,2),
  bloccato_da text,
  bloccato_il timestamptz,
  notificato_il timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT contabilita_mesi_unique_key UNIQUE (nome_corso, mese, anno)
);

CREATE INDEX IF NOT EXISTS contabilita_mesi_corso_idx
  ON public.contabilita_mesi (nome_corso, anno, mese);

-- 3. Seed configurazione di default a partire dai corsi esistenti.
--    Adulti e Altri: soglia 7 alunni, 50%/60%. Bambini: soglia 5 alunni, 50%/60%.
INSERT INTO public.corsi_config_contabile (nome_corso, categoria, soglia_alunni, perc_istruttore_sotto, perc_istruttore_sopra)
SELECT
  c.nome_corso,
  COALESCE(c.categoria, 'Adulti'),
  CASE WHEN COALESCE(c.categoria, 'Adulti') = 'Bambini' THEN 5 ELSE 7 END,
  50,
  60
FROM public.corsi c
ON CONFLICT (nome_corso) DO NOTHING;

-- 4. RLS: stesso pattern temporaneo go-live delle altre tabelle applicative,
--    perche il frontend usa la chiave anon senza Supabase Auth. Il controllo
--    "solo Admin" per le modifiche resta applicativo (come per le altre
--    funzioni riservate al presidente in admin.html/admin-contabilita.html).
DO $$
DECLARE
  tbl text;
  tabelle text[] := ARRAY['corsi_config_contabile', 'contabilita_mesi'];
  pol record;
BEGIN
  FOREACH tbl IN ARRAY tabelle LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', tbl);

    FOR pol IN
      SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = tbl
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', pol.policyname, tbl);
    END LOOP;

    EXECUTE format('CREATE POLICY %I ON public.%I FOR SELECT TO anon, authenticated USING (true)', tbl || '_go_live_select', tbl);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR INSERT TO anon, authenticated WITH CHECK (true)', tbl || '_go_live_insert', tbl);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR UPDATE TO anon, authenticated USING (true) WITH CHECK (true)', tbl || '_go_live_update', tbl);
    EXECUTE format('CREATE POLICY %I ON public.%I FOR DELETE TO anon, authenticated USING (true)', tbl || '_go_live_delete', tbl);
  END LOOP;
END $$;

COMMIT;

-- Verifica finale
SELECT * FROM public.corsi_config_contabile ORDER BY nome_corso;
SELECT tablename, policyname, cmd FROM pg_policies
WHERE schemaname = 'public' AND tablename IN ('corsi_config_contabile', 'contabilita_mesi')
ORDER BY tablename, policyname;
