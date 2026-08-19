-- Eseguire una sola volta nel SQL Editor di Supabase prima del deploy.
-- Separa la richiesta di incarico istruttore dall'iscrizione al corso come praticante.

ALTER TABLE public.iscrizioni_annuali
  ADD COLUMN IF NOT EXISTS richiesta_istruttore boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS stato_richiesta_istruttore text NOT NULL DEFAULT 'Nessuna'
    CHECK (stato_richiesta_istruttore IN ('Nessuna', 'In attesa', 'Confermata', 'Rifiutata'));

ALTER TABLE public.istruttori_corsi
  ADD COLUMN IF NOT EXISTS attivo boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS corsi_disabilitati text[] NOT NULL DEFAULT '{}';

UPDATE public.iscrizioni_annuali
SET stato_richiesta_istruttore = 'Nessuna'
WHERE stato_richiesta_istruttore IS NULL;

UPDATE public.istruttori_corsi
SET attivo = true
WHERE attivo IS NULL;

UPDATE public.istruttori_corsi
SET corsi_disabilitati = '{}'
WHERE corsi_disabilitati IS NULL;

SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('iscrizioni_annuali', 'istruttori_corsi')
  AND column_name IN ('richiesta_istruttore', 'stato_richiesta_istruttore', 'attivo', 'corsi_disabilitati')
ORDER BY table_name, column_name;