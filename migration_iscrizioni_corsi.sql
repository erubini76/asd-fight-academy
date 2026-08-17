-- Migrazione e standardizzazione delle iscrizioni ai corsi
-- Source of truth: tabella iscrizioni_corsi
-- Eseguire nel SQL editor di Supabase dopo aver verificato il dataset.

BEGIN;

-- 1) Tabella canonica delle iscrizioni ai corsi.
create table if not exists iscrizioni_corsi (
  id uuid primary key default gen_random_uuid(),
  socio_id uuid not null references soci(id) on delete cascade,
  nome_corso varchar not null,
  data_iscrizione date not null default current_date,
  stato varchar not null default 'attiva'
);

-- 2) Indici utili per join e ricerca.
create index if not exists idx_iscrizioni_corsi_socio_id on iscrizioni_corsi(socio_id);
create index if not exists idx_iscrizioni_corsi_nome_corso on iscrizioni_corsi(nome_corso);

-- 3) Backfill sicuro: copiamo i corsi attualmente presenti in soci
--    in modo deduplicato per socio_id + nome_corso.
insert into iscrizioni_corsi (socio_id, nome_corso, data_iscrizione, stato)
select
  s.id,
  coalesce(nullif(trim(s.corso_scelto), ''), nullif(trim(s.corso), ''), 'Generale') as nome_corso,
  coalesce(s.data_iscrizione, current_date) as data_iscrizione,
  'attiva' as stato
from soci s
where coalesce(nullif(trim(s.corso_scelto), ''), nullif(trim(s.corso), '')) is not null
and not exists (
  select 1
  from iscrizioni_corsi i
  where i.socio_id = s.id
    and i.nome_corso = coalesce(nullif(trim(s.corso_scelto), ''), nullif(trim(s.corso), ''), 'Generale')
);

-- 4) Vista compatibile per i pannelli amministrativi.
create or replace view v_iscrizioni_tesserati as
select
  i.id,
  i.socio_id,
  s.nome,
  s.cognome,
  s.email,
  s.codice_fiscale,
  i.nome_corso,
  i.data_iscrizione,
  i.stato
from iscrizioni_corsi i
left join soci s on s.id = i.socio_id;

-- 5) Cleanup finale: dopo aver verificato che il front-end legge solo da iscrizioni_corsi,
--    puoi svuotare i campi legacy per evitare duplicazioni di memoria.
--    ESEGUIRE SOLO DOPO VALIDAZIONE COMPLETA DELLA UI.
--
-- update soci
-- set corso_scelto = null,
--     corso = null
-- where true;
--
-- alter table soci drop column if exists corso;
-- alter table soci drop column if exists corso_scelto;

COMMIT;
