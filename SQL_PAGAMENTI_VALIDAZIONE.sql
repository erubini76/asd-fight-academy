-- Traccia chi ha validato una quota annuale.
ALTER TABLE public.pagamenti
  ADD COLUMN IF NOT EXISTS validato_da_email text,
  ADD COLUMN IF NOT EXISTS validato_da_nome text,
  ADD COLUMN IF NOT EXISTS validato_il timestamptz;

-- Le quote annuali gia approvate prima dell'introduzione dei campi
-- restano valide, ma non possono avere un validatore ricostruito.