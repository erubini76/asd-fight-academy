-- ============================================================================
-- MIGRAZIONE ANNUALITA E STORICO - ASD FIGHT ACADEMY
--
-- Scopo:
--   1) conservare le iscrizioni per anno accademico;
--   2) conservare i certificati medici per stagione;
--   3) conservare prova versionata di privacy e liberatoria foto/video;
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
  anno_accademico text NOT NULL,
  file_url text NOT NULL,
  nome_file text,
  scadenza date,
  caricato_il timestamptz NOT NULL DEFAULT now(),
  caricato_da text,
  attivo boolean NOT NULL DEFAULT true,
  conservare_fino_al date NOT NULL,
  eliminato_il timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS documenti_medici_socio_idx
  ON public.documenti_medici (socio_id);
CREATE INDEX IF NOT EXISTS documenti_medici_attivo_idx
  ON public.documenti_medici (socio_id, attivo);
CREATE UNIQUE INDEX IF NOT EXISTS documenti_medici_unico_attivo_per_stagione_uidx
  ON public.documenti_medici (socio_id, anno_accademico)
  WHERE attivo AND eliminato_il IS NULL;

INSERT INTO public.documenti_medici (
  socio_id, anno_accademico, file_url, scadenza, caricato_il, attivo,
  conservare_fino_al
)
SELECT
  s.id,
  '2026/2027',
  s.certificato_medico_url,
  s.scadenza_certificato_medico,
  now(),
  true,
  DATE '2037-08-31'
FROM public.soci s
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

-- 4. Eventi di consenso: la prova di privacy e liberatoria foto/video non puo
-- essere affidata al solo booleano corrente salvato nella tabella soci.
CREATE TABLE IF NOT EXISTS public.consensi_tesseramento (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  socio_id uuid NOT NULL REFERENCES public.soci(id),
  anno_accademico text NOT NULL,
  tipo text NOT NULL,
  stato text NOT NULL,
  versione_testo text NOT NULL,
  canale text NOT NULL DEFAULT 'modulo_web',
  registrato_il timestamptz NOT NULL DEFAULT now(),
  revoca_di uuid REFERENCES public.consensi_tesseramento(id),
  CONSTRAINT consensi_tesseramento_tipo_chk
    CHECK (tipo IN ('presa_visione_privacy', 'foto_video')),
  CONSTRAINT consensi_tesseramento_stato_chk
    CHECK (stato IN ('dato', 'negato', 'revocato'))
);

CREATE INDEX IF NOT EXISTS consensi_tesseramento_socio_idx
  ON public.consensi_tesseramento (socio_id, anno_accademico, registrato_il DESC);

-- Snapshot iniziale dei valori correnti. La versione iniziale dovra essere
-- sostituita con la versione reale dei testi prima dell'uso in produzione.
INSERT INTO public.consensi_tesseramento (
  socio_id, anno_accademico, tipo, stato, versione_testo
)
SELECT s.id, '2026/2027', 'presa_visione_privacy',
       CASE WHEN s.privacy_accettata THEN 'dato' ELSE 'negato' END,
       'legacy-2026-2027-da-verificare'
FROM public.soci s
WHERE NOT EXISTS (
  SELECT 1 FROM public.consensi_tesseramento c
  WHERE c.socio_id = s.id
    AND c.anno_accademico = '2026/2027'
    AND c.tipo = 'presa_visione_privacy'
);

INSERT INTO public.consensi_tesseramento (
  socio_id, anno_accademico, tipo, stato, versione_testo
)
SELECT s.id, '2026/2027', 'foto_video',
       CASE WHEN s.liberatoria_immagini THEN 'dato' ELSE 'negato' END,
       'legacy-2026-2027-da-verificare'
FROM public.soci s
WHERE NOT EXISTS (
  SELECT 1 FROM public.consensi_tesseramento c
  WHERE c.socio_id = s.id
    AND c.anno_accademico = '2026/2027'
    AND c.tipo = 'foto_video'
);

COMMIT;

-- Dopo l'esecuzione lanciare SQL_VERIFICA_INTEGRITA_ANNUALITA.sql.