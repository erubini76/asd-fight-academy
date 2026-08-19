# Sessione Di Test Virtuale - Go-Live 2026/2027

## Scopo

Verificare in modo controllato i flussi principali dell'app prima della pubblicazione.

Questa sessione usa tesserati di prova e non deve modificare o cancellare dati reali senza consenso dell'Amministratore. Ogni test che crea dati deve usare un codice fiscale, email e nominativo riconoscibili come test.

## Precondizioni

- La migrazione annualita e storico e stata eseguita con esito positivo.
- Le policy di [SQL_POLICY_ANNUALITA_GO_LIVE.sql](SQL_POLICY_ANNUALITA_GO_LIVE.sql) sono attive.
- Le tabelle `iscrizioni_annuali`, `documenti_medici` e `consensi_tesseramento` sono leggibili dal frontend.
- La stagione corrente, alla data del test, e `2026/2027`.
- Nessun test deve usare dati sanitari reali: caricare solo PDF o immagini fittizi.
- Predisporre un file fittizio `certificato-test.pdf` e una ricevuta fittizia `ricevuta-test.pdf`.

## Dati Di Test

| Codice | Profilo | Email | Corso | Consenso Foto |
|---|---|---|---|---|
| T-ADULTO | Tesserato maggiorenne | `test.adulto@example.invalid` | Ninjutsu Adulti/Ragazzi | Si |
| T-MINORE | Tesserato minorenne | `test.minore@example.invalid` | Ninjutsu Bambini | No |
| T-DOPPIO | Tesserato in due corsi | `test.doppio@example.invalid` | Ninjutsu Bambini + Vietvodao Adulti/Ragazzi | Si |
| T-RINNOVO | Tesserato gia presente | usare un record di test esistente | corso gia registrato | invariato |

Usare codici fiscali fittizi e non riconducibili a persone reali. Annotare gli ID restituiti da Supabase nella tabella risultati della sessione.

## Criteri Di Blocco

Interrompere la sessione e non pubblicare se accade uno dei casi seguenti:

- un nuovo tesseramento sovrascrive una riga di annualita precedente;
- una quota annuale di una stagione aggiorna una stagione diversa;
- un istruttore riesce a gestire un corso non assegnato;
- il Registro Presenze include tesserati di una stagione precedente;
- il certificato precedente viene cancellato invece di essere disattivato;
- le query di controllo integrita restituiscono duplicati, record orfani o consensi incompleti;
- una pagina mostra errore JavaScript o dati vuoti non giustificati.

## Test Funzionali

### TF-01 - Nuovo Tesseramento Maggiorenne

**Profilo:** `T-ADULTO`.

1. Aprire `iscrizione.html` senza sessione amministratore.
2. Verificare che l'anno accademico sia `2026/2027` e non sia modificabile.
3. Compilare tutti i dati obbligatori del maggiorenne.
4. Selezionare un corso e allegare il certificato di prova con una scadenza futura.
5. Accettare privacy e foto/video.
6. Inviare la domanda.

**Risultato atteso:**

- viene creato un profilo in `soci`;
- viene creata una riga in `iscrizioni_annuali` per `T-ADULTO + corso + 2026/2027`, stato `In Attesa`;
- vengono creati due eventi in `consensi_tesseramento`;
- viene creato un documento attivo in `documenti_medici`;
- la relazione legacy in `iscrizioni_corsi` continua a esistere per compatibilita;
- nessun record di una stagione precedente viene modificato.

### TF-02 - Nuovo Tesseramento Minorenne

**Profilo:** `T-MINORE`.

1. Inserire una data di nascita che renda il tesserato minorenne.
2. Verificare che la sezione tutore si renda obbligatoria.
3. Compilare nome, cognome e codice fiscale del tutore.
4. Accettare privacy e lasciare non selezionata la liberatoria foto/video.
5. Inviare la domanda.

**Risultato atteso:**

- la domanda non puo essere inviata senza i dati obbligatori del tutore;
- l'evento privacy ha stato `dato`;
- l'evento foto/video ha stato `negato`;
- il Registro Unificato mostra Privacy verde e Foto gialla;
- l'Area Tesserati mostra i dati del tutore e `Consenso non dato` per foto/video.

### TF-03 - Rinnovo E Aggiornamento Anagrafica

**Profilo:** `T-RINNOVO`.

1. Recuperare i dati tramite email e codice fiscale.
2. Modificare solo telefono o indirizzo.
3. Inviare per la stagione corrente e un corso gia presente in quella stagione.

**Risultato atteso:**

- `soci` contiene il nuovo dato anagrafico corrente;
- non vengono create copie storiche di telefono o indirizzo;
- non viene creato un duplicato di `iscrizioni_annuali` per stessa combinazione tesserato, corso e stagione;
- lo stato annuale gia approvato non viene riportato automaticamente a `In Attesa`.

### TF-04 - Tesserato In Due Corsi

**Profilo:** `T-DOPPIO`.

1. Creare o rinnovare il primo corso della stagione.
2. Creare o rinnovare il secondo corso della stessa stagione.
3. Accedere a `socio.html`.

**Risultato atteso:**

- esistono due righe `iscrizioni_annuali` con stesso tesserato e stessa stagione, ma corsi diversi;
- l'Area Tesserati mostra due schede, una per corso;
- Registro Presenze e Contabilita separano i corsi;
- non compare una terza scheda duplicata.

### TF-05 - Caricamento Certificato E Storico

**Profilo:** `T-ADULTO`.

1. Accedere a `socio.html`.
2. Caricare un secondo certificato fittizio con una nuova scadenza.
3. Verificare il record precedente in `documenti_medici`.

**Risultato atteso:**

- il nuovo documento e `attivo = true`;
- il documento precedente della stessa stagione diventa `attivo = false`;
- i file precedenti non vengono cancellati;
- `soci` e `iscrizioni_annuali` mostrano URL e scadenza correnti;
- l'istruttore vede solo stato e scadenza nella pagina Scadenze;
- l'Amministratore vede il collegamento al documento nel Registro Unificato.

### TF-06 - Quota Annuale E Approvazione

**Profilo:** `T-ADULTO`.

1. Da `socio.html`, inviare una quota annuale con bonifico e ricevuta fittizia.
2. Accedere come Amministratore a `admin.html`.
3. Provare ad approvare prima di inserire una Tessera ASI valida.
4. Inserire una data ASI futura.
5. Approvare il tesseramento dopo la verifica della quota.

**Risultato atteso:**

- il pagamento ha `anno_accademico = 2026/2027`;
- senza quota approvata o con ASI assente/scaduta viene mostrata una motivazione e lo stato non cambia;
- l'approvazione agisce solo sulla riga di `iscrizioni_annuali` per corso e stagione;
- vengono salvati `data_approvazione` e `approvata_da`;
- non viene modificato lo stato di annualita di altri corsi o anni;
- la chiamata email non blocca il refresh se l'invio e configurato correttamente.

### TF-07 - Mensilita E Contabilita

**Profilo:** `T-DOPPIO`.

1. Inserire una mensilita per il primo corso e una per il secondo.
2. Aprire `admin-contabilita.html` come istruttore del primo corso.
3. Selezionare anno accademico `2026` e il primo corso.
4. Ripetere per il secondo corso con l'istruttore autorizzato.

**Risultato atteso:**

- ogni pagamento ha il corretto `anno_accademico`;
- il totale istruttore include solo gli incassi del proprio corso;
- una quota o mensilita dell'altro corso non compare nel totale;
- la vista anno solare continua ad aggregare i pagamenti per data reale;
- una quota 2027/2028 non puo aggiornare una quota 2026/2027.

### TF-08 - Registro Presenze

**Profilo:** `T-ADULTO` e `T-DOPPIO`.

1. Accedere come istruttore assegnato a un corso.
2. Aprire `presenze.html`.
3. Selezionare il corso e registrare una presenza.
4. Provare a usare un corso non assegnato, se disponibile.

**Risultato atteso:**

- la lista comprende solo i tesserati iscritti nella stagione corrente;
- un istruttore non puo selezionare o gestire un corso fuori competenza;
- il salvataggio crea presenze solo per corso e data selezionati;
- i tesserati della stagione precedente non compaiono nel registro corrente.

### TF-09 - Scadenze E Visibilita Documenti

**Profilo:** tesserato con certificato assente, scaduto e in scadenza.

1. Accedere come istruttore a `admin-scadenze.html`.
2. Verificare corsi, stato e date mostrati.
3. Accedere come Amministratore al Registro Unificato.

**Risultato atteso:**

- Scadenze usa il documento attivo della stagione corrente;
- istruttore vede nome, contatti, corso, stato e data, ma nessun collegamento PDF;
- Amministratore vede il collegamento al certificato corrente;
- un documento disattivato non determina lo stato operativo della stagione.

### TF-10 - Eccezione Stagione Per Amministratore

1. Accedere a `admin.html` come Amministratore.
2. Aprire `iscrizione.html` nella stessa sessione browser.
3. Verificare che il selettore stagione sia abilitato.
4. Selezionare una stagione diversa e inviare un tesseramento di prova.

**Risultato atteso:**

- senza sessione Amministratore il selettore e bloccato;
- con sessione Amministratore sono disponibili stagione precedente, corrente e successiva;
- l'annualita, i consensi, il certificato e il pagamento annuale sono collegati alla stagione selezionata;
- il default resta la stagione proposta dal 1 agosto.

### TF-11 - Regressione Dati Legacy

1. Accedere con un tesserato esistente migrato.
2. Verificare Registro Unificato, Area Tesserati, Contabilita, Scadenze e Presenze.
3. Rieseguire le sezioni 6-11 di `SQL_VERIFICA_INTEGRITA_ANNUALITA.sql`.

**Risultato atteso:**

- 13 annualita iniziali, 4 documenti attivi e 24 consensi rimangono disponibili;
- non compaiono duplicati o record orfani;
- le pagine non restituiscono liste vuote per errore di policy;
- le relazioni legacy restano intatte per compatibilita.

## Verifiche SQL Dopo I Test

Eseguire le sezioni 6-11 di [SQL_VERIFICA_INTEGRITA_ANNUALITA.sql](SQL_VERIFICA_INTEGRITA_ANNUALITA.sql).

Controlli aggiuntivi:

```sql
-- Un solo certificato attivo per tesserato e stagione.
SELECT socio_id, anno_accademico, COUNT(*) AS certificati_attivi
FROM public.documenti_medici
WHERE attivo = true AND eliminato_il IS NULL
GROUP BY socio_id, anno_accademico
HAVING COUNT(*) > 1;

-- Nessuna annualita duplicata.
SELECT socio_id, nome_corso, anno_accademico, COUNT(*) AS duplicati
FROM public.iscrizioni_annuali
GROUP BY socio_id, nome_corso, anno_accademico
HAVING COUNT(*) > 1;

-- Pagamenti annuali senza stagione: deve restituire zero righe.
SELECT id, socio_id, tipo_pagamento, anno_accademico
FROM public.pagamenti
WHERE tipo_pagamento = 'Iscrizione Annuale'
  AND anno_accademico IS NULL;
```

## Esito Sessione

### Esecuzione Automatica API/Database - 19 Agosto 2026

Eseguita una sessione con tesserato fittizio e pulizia automatica finale. Marker usato: `TST28212810`. Il record di test e tutti i relativi record figli sono stati rimossi dopo il collaudo.

| Controllo | Esito |
|---|---|
| Creazione profilo tesserato | PASS |
| Due corsi nella stessa stagione | PASS |
| Stesso corso in due stagioni | PASS |
| Vincolo duplicato tesserato/corso/stagione | PASS - HTTP 409 |
| Eventi privacy e foto/video | PASS |
| Primo certificato attivo | PASS |
| Storico certificati con un solo attivo | PASS |
| Quota annuale classificata per stagione | PASS |
| Presenza per corso | PASS |
| Lettura via API anon delle nuove tabelle | PASS |
| Pulizia dei dati di test | PASS |

La sessione automatica ha coperto la persistenza e i vincoli del database. Non sono stati eseguiti click browser, upload binari reali, login interattivi o invii email reali perche nel container non sono presenti browser o strumenti Playwright/Puppeteer.

| Area | Esito | Note |
|---|---|---|
| TF-01 Nuovo maggiorenne | Da eseguire | |
| TF-02 Minorenne | Da eseguire | |
| TF-03 Rinnovo anagrafica | Da eseguire | |
| TF-04 Due corsi | Da eseguire | |
| TF-05 Certificato storico | Da eseguire | |
| TF-06 Quota e approvazione | Da eseguire | |
| TF-07 Contabilita | Da eseguire | |
| TF-08 Presenze | Da eseguire | |
| TF-09 Scadenze | Da eseguire | |
| TF-10 Eccezione stagione | Da eseguire | |
| TF-11 Regressione legacy | Da eseguire | |

## Regola Di Chiusura

La sessione e superata solo se tutti i test critici TF-01, TF-04, TF-05, TF-06, TF-07, TF-08, TF-09 e TF-11 hanno esito positivo, le query SQL non rilevano anomalie e non si verificano errori JavaScript nelle pagine coinvolte.
