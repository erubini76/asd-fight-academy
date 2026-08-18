-- ============================================================================
-- MIGRAZIONE ANNUALITA E STORICO - ASD FIGHT ACADEMY
--
-- Scopo:
--   1) conservare le iscrizioni per anno accademico;
--   2) conservare tutti i certificati medici caricati;
--   3) predisporre lo storico delle modifiche;
--   4) mantenere intatte le tabelle e i dati legacy esistenti.
--
-- IMPORTANTE:
--   - Eseguire prima SQL_VERIFICA_INTEGRITA_ANNUALITA.sql.
--   - Eseguire questo script nel SQL Editor Supabase con una transazione.
--   - Questo script NON elimina dati, indici o vincoli legacy.
--   - L'applicazione dovra essere aggiornata in un secondo momento per usare
--     iscrizioni_annuali e documenti_medici per le nuove iscrizioni.
-- ============================================================================

BEGIN;

-- Preflight: fermarsi se il database non ha ancora la struttura attesa.
DO $$
BEGIN
  IF to_regclass('public.soci') IS NULL THEN
    RAISE EXCEPTION 'Migrazione annullata: tabella public.soci assente';
  END IF;
  IF to_regclass('public.iscrizioni_corsi') IS NULL THEN
    RAISE EXCEPTION 'Migrazione annullata: tabella public.iscrizioni_corsi assente';
  END IF;
  IF to_regclass('public.pagamenti') IS NULL THEN
    RAISE EXCEPTION 'Migrazione annullata: tabella public.pagamenti assente';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'soci'
      AND column_name = 'id' AND udt_name = 'uuid'
  ) THEN
    RAISE EXCEPTION 'Migrazione annullata: public.soci.id non e di tipo uuid';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM (VALUES
      ('privacy_accettata'),
      ('liberatoria_immagini'),
      ('scadenza_certificato_medico'),
      ('certificato_medico_url'),
      ('stato_approvazione')
    ) AS richiesti(column_name)
    WHERE NOT EXISTS (
      SELECT 1 FROM information_schema.columns c
      WHERE c.table_schema = 'public'
        AND c.table_name = 'soci'
        AND c.column_name = richiesti.column_name
    )
  ) THEN
    RAISE EXCEPTION 'Migrazione annullata: uno o piu campi richiesti della tabella soci sono assenti';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'iscrizioni_corsi'
      AND column_name = 'socio_id'
  ) OR NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'iscrizioni_corsi'
      AND column_name = 'nome_corso'
  ) THEN
    RAISE EXCEPTION 'Migrazione annullata: campi iscrizioni_corsi mancanti';
  END IF;
END $$;

-- 1. Una domanda annuale per socio, corso e stagione.
CREATE TABLE IF NOT EXISTS public.iscrizioni_annuali (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  socio_id uuid NOT NULL REFERENCES public.soci(id),
  nome_corso text NOT NULL,
  anno_accademico text NOT NULL,
  stato text NOT NULL DEFAULT 'In Attesa',
  privacy_accettata boolean,
  liberatoria_immagini boolean,
  scadenza_certificato_medico date,
  certificato_medico_url text,
  data_invio timestamptz NOT NULL DEFAULT now(),
  data_approvazione timestamptz,
  approvata_da text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT iscrizioni_annuali_anno_chk
    CHECK (anno_accademico ~ '^[0-9]{4}/[0-9]{4}$'),
  CONSTRAINT iscrizioni_annuali_unique_key
    UNIQUE (socio_id, nome_corso, anno_accademico)
);

CREATE INDEX IF NOT EXISTS iscrizioni_annuali_socio_idx
  ON public.iscrizioni_annuali (socio_id);
CREATE INDEX IF NOT EXISTS iscrizioni_annuali_anno_idx
  ON public.iscrizioni_annuali (anno_accademico);
CREATE INDEX IF NOT EXISTS iscrizioni_annuali_corso_idx
  ON public.iscrizioni_annuali (nome_corso);

-- Snapshot iniziale: i record legacy vengono considerati 2026/2027.
-- ON CONFLICT evita duplicati se lo script viene rieseguito.
INSERT INTO public.iscrizioni_annuali (
  socio_id, nome_corso, anno_accademico, stato,
  privacy_accettata, liberatoria_immagini,
  scadenza_certificato_medico, certificato_medico_url,
  data_invio, created_at, updated_at
)
SELECT
  ic.socio_id,
  ic.nome_corso,
  '2026/2027',
  COALESCE(s.stato_approvazione, 'In Attesa'),
  s.privacy_accettata,
  s.liberatoria_immagini,
  s.scadenza_certificato_medico,
  s.certificato_medico_url,
  COALESCE(ic.data_iscrizione::timestamptz, now()),
  COALESCE(ic.data_iscrizione::timestamptz, now()),
  now()
FROM public.iscrizioni_corsi ic
JOIN public.soci s ON s.id = ic.socio_id
WHERE ic.socio_id IS NOT NULL
  AND ic.nome_corso IS NOT NULL
ON CONFLICT (socio_id, nome_corso, anno_accademico) DO NOTHING;

-- 2. Storico dei certificati: il certificato attualmente collegato al socio
-- diventa il primo documento noto. I vecchi file eventualmente presenti nello
-- Storage, ma senza URL nel database, non sono ricostruibili automaticamente.
CREATE TABLE IF NOT EXISTS public.documenti_medici (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  socio_id uuid NOT NULL REFERENCES public.soci(id),
  iscrizione_annuale_id uuid REFERENCES public.iscrizioni_annuali(id),
  file_url text NOT NULL,
  nome_file text,
  scadenza date,
  caricato_il timestamptz NOT NULL DEFAULT now(),
  caricato_da text,
  attivo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS documenti_medici_socio_idx
  ON public.documenti_medici (socio_id);
CREATE INDEX IF NOT EXISTS documenti_medici_attivo_idx
  ON public.documenti_medici (socio_id, attivo);

INSERT INTO public.documenti_medici (
  socio_id, iscrizione_annuale_id, file_url, scadenza, caricato_il, attivo
)
SELECT
  s.id,
  ia.id,
  s.certificato_medico_url,
  s.scadenza_certificato_medico,
  now(),
  true
FROM public.soci s
LEFT JOIN public.iscrizioni_annuali ia
  ON ia.socio_id = s.id AND ia.anno_accademico = '2026/2027'
WHERE NULLIF(TRIM(s.certificato_medico_url), '') IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.documenti_medici dm
    WHERE dm.socio_id = s.id AND dm.file_url = s.certificato_medico_url
  );

-- 3. Campo anno sui pagamenti. Nullable per non rompere pagamenti legacy non
-- classificabili; i nuovi pagamenti dovranno valorizzarlo sempre.
ALTER TABLE public.pagamenti
  ADD COLUMN IF NOT EXISTS anno_accademico text;

UPDATE public.pagamenti
SET anno_accademico = '2026/2027'
WHERE anno_accademico IS NULL
  AND tipo_pagamento = 'Iscrizione Annuale'
  AND (anno_riferimento IS NULL OR anno_riferimento = 2026);

CREATE INDEX IF NOT EXISTS pagamenti_anno_accademico_idx
  ON public.pagamenti (socio_id, anno_accademico, corso);

-- 4. Audit generico: non registra ancora automaticamente le modifiche. Serve
-- come base stabile per il successivo trigger/applicativo di audit.
CREATE TABLE IF NOT EXISTS public.storico_modifiche (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  socio_id uuid REFERENCES public.soci(id),
  iscrizione_annuale_id uuid REFERENCES public.iscrizioni_annuali(id),
  utente_email text,
  utente_nome text,
  campo text NOT NULL,
  valore_precedente text,
  valore_nuovo text,
  motivo text,
  modificato_il timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS storico_modifiche_socio_idx
  ON public.storico_modifiche (socio_id, modificato_il DESC);
CREATE INDEX IF NOT EXISTS storico_modifiche_iscrizione_idx
  ON public.storico_modifiche (iscrizione_annuale_id, modificato_il DESC);

COMMIT;

-- Dopo l'esecuzione lanciare SQL_VERIFICA_INTEGRITA_ANNUALITA.sql.