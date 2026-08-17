# 🔍 AUDIT TECNICO COMPLETO - REGISTRI DUPLICATI CORSI
**Data**: 17 Agosto 2026  
**Analisi**: Sistema ASD Fight Academy (Front-End, Back-End, Database Schema)  
**Problema**: Registri duplicati nella gestione corsi, iscrizioni, pagamenti e presenze

---

## 📋 SOMMARIO ESECUTIVO

Dopo audit completo del codice e schema database, ho identificato **DUE CLASSI DI PROBLEMI**:

1. **Bug Attivi di Codice (FE & BE)**: 🔴 **CRITICO**  
   - Double-submit vulnerabilities nei form (mancanza di disabilitazione pulsanti sincronizzata)
   - Logica di inserimento che usa `.insert()` anziché `.upsert()`
   - Race conditions tra verifica e inserimento dati

2. **Dati Sporchi nel Database**: 🟡 **PROBABILE**  
   - Vincoli UNIQUE mancanti sulle tabelle critiche
   - Schema insufficiente per prevenire duplicati lato DB

---

## 1️⃣ RISULTATI AUDIT CODICE (FE & BE)

### A. VULNERABILITÀ FRONT-END CRITICHE

#### 1.1 | iscrizione.html - Forma di Tesseramento
**Severità**: 🔴 CRITICA

**Funzione affetta**: `inviaDomanda(event)` (linee ~320-420)

**Il Problema**:
```javascript
async function inviaDomanda(e) {
    e.preventDefault();
    const btn = document.getElementById('submit-btn');
    btn.disabled = true;  // ← Protezione debole: race condition possibile
    btn.textContent = "Invio in corso...";
    
    // ... codice di invio dati ...
    
    // Problema: se la rete è lenta (>500ms), utente può cliccare due volte
    // e la seconda richiesta passa perché btn.disabled non è *realmente sincronizzato*
}
```

**Scenario di Exploit**:
1. Utente completa il form di iscrizione
2. Clicca "Invia Domanda di Tesseramento"
3. Se latenza rete > 500ms, utente può cliccare di nuovo **PRIMA** che il bottone sia veramente disabilitato
4. Due richieste simultanee → Due record in `soci` + Due record in `iscrizioni_corsi`

**Code Locations - Inserimenti senza UPSERT**:
- Linea ~353-370: `soci.insert()` per nuovo socio
- Linea ~377-405: `iscrizioni_corsi.insert()` per iscrizione corso (SENZA upsert)
- Linea ~310-340: `corsi.insert()` creazione corso automatica (SENZA upsert)

---

#### 1.2 | socio.html - Area Pagamenti
**Severità**: 🔴 ALTA

**Funzione affetta**: `inviaPagamentoAvanzato(tesseratoId, corsoSocio)` (linee ~220-260)

**Il Problema**:
```javascript
async function inviaPagamentoAvanzato(tesseratoId, corsoSocio) {
    // ... setup ...
    
    // MANCA DISABILITAZIONE PULSANTE!
    const { error } = await supabaseClient.from('pagamenti').insert(records);
    if (error) throw error;
    alert("Richiesta inviata!"); 
    location.reload();  // ← Riload solo DOPO che l'insert è andato a buon fine
}
```

**Scenario di Exploit**:
1. Utente invia pagamento (bonifico)
2. Durante l'upload file + invio, clicca "Conferma" di nuovo
3. Due richieste parallele → Due record di pagamento identici

**Code Locations**:
- Linea ~250: `.insert(records)` senza controllo di duplicati
- NO disabilitazione del pulsante durante l'invio

---

#### 1.3 | presenze.html - Registro Appello
**Severità**: 🟡 MEDIA

**Funzione affetta**: `salvaPresenze()` (linee ~170-200)

**Il Problema**:
```javascript
async function salvaPresenze() {
    const btn = document.getElementById('salva-btn');
    btn.disabled = true;
    
    const records = Array.from(presentiIds).map(socioId => ({
        socio_id: socioId,
        data_presenza: dataLezione,
        corso: corso
    }));
    
    // ← PROBLEMA: Nessun controllo se presenze per (socio_id, data, corso) già esiste
    const { error } = await supabaseClient
        .from('presenze')
        .insert(records);
}
```

**Scenario di Exploit**:
- Istruttore chiama l'appello, salva presenze
- Se clicca "Salva" due volte, crea presenze duplicate
- Manca anche `.upsert()` con `onConflict`

---

#### 1.4 | admin-contabilita.html - Gestione Pagamenti Presidente
**Severità**: 🟡 MEDIA

**Funzione affetta**: `salvaPagamentoRapido()` (linee ~290-310)

**Il Problema**:
```javascript
async function salvaPagamentoRapido() {
    const imp = document.getElementById('pay-amount').value;
    // ...
    if (currentSelection.existingPagId) {
        // UPDATE (ok)
        await supabaseClient.from('pagamenti')
            .update({ stato: 'Approvato', importo: imp, ... })
            .eq('id', currentSelection.existingPagId);
    } else {
        // INSERT SENZA UPSERT! (problema)
        await supabaseClient.from('pagamenti')
            .insert([{ socio_id, importo, mese, anno, ... }]);
    }
}
```

**Scenario di Exploit**:
- Presidente approva pagamenti da contabilità
- Doppio click → Duplica il pagamento

---

### B. SCHEMA DATABASE - VINCOLI MANCANTI

#### 1.5 | Tabella `iscrizioni_corsi`
**Severità**: 🔴 CRITICA

**Vincolo Mancante**:
```sql
-- DOVREBBE ESSERCI:
ALTER TABLE iscrizioni_corsi 
ADD CONSTRAINT unique_socio_corso_iscrizione 
UNIQUE (socio_id, nome_corso);

-- OPPURE (per permettere più iscrizioni nel tempo):
ALTER TABLE iscrizioni_corsi 
ADD CONSTRAINT unique_socio_corso_data 
UNIQUE (socio_id, nome_corso, DATE(data_iscrizione));
```

**Impatto**: Permette N record identici per lo stesso socio e corso

---

#### 1.6 | Tabella `pagamenti`
**Severità**: 🔴 CRITICA

**Vincolo Mancante**:
```sql
-- DOVREBBE ESSERCI:
ALTER TABLE pagamenti 
ADD CONSTRAINT unique_socio_pagamento_mensile 
UNIQUE (socio_id, mese_riferimento, anno_riferimento, corso);

-- OPPURE per iscrizione annuale:
ALTER TABLE pagamenti 
ADD CONSTRAINT unique_socio_iscrizione_annuale 
UNIQUE (socio_id) 
WHERE corso = 'Iscrizione Annuale' AND anno_riferimento = 2026;
```

**Impatto**: Permette pagamenti duplicati per lo stesso periodo

---

#### 1.7 | Tabella `presenze`
**Severità**: 🟡 MEDIA

**Vincolo Mancante**:
```sql
-- DOVREBBE ESSERCI:
ALTER TABLE presenze 
ADD CONSTRAINT unique_socio_data_corso 
UNIQUE (socio_id, DATE(data_presenza), corso);
```

**Impatto**: Permette presenze duplicate per la stessa lezione

---

#### 1.8 | Tabella `corsi`
**Severità**: 🟡 MEDIA

**Vincolo Mancante**:
```sql
-- DOVREBBE ESSERCI:
ALTER TABLE corsi 
ADD CONSTRAINT unique_nome_corso_insensitive 
UNIQUE (LOWER(TRIM(nome_corso)));
```

**Impatto**: Permette "Karate", "karate", "KARATE" come corsi diversi

---

## 2️⃣ SCRIPT SQL DI DIAGNOSI

Esegui questi query nel **Supabase Query Editor** per identificare esattamente i duplicati nel tuo database:

### 2.1 | Duplicati in `iscrizioni_corsi`

```sql
-- Query 1: Iscrizioni duplicate per lo stesso socio-corso
SELECT 
    socio_id,
    nome_corso,
    COUNT(*) as numero_duplicati,
    array_agg(id ORDER BY data_iscrizione DESC) as ids_record,
    array_agg(data_iscrizione ORDER BY data_iscrizione DESC) as date_iscrizione
FROM iscrizioni_corsi
GROUP BY socio_id, nome_corso
HAVING COUNT(*) > 1
ORDER BY numero_duplicati DESC;

-- Query 2: Elenco completo di soci con iscrizioni multiple
SELECT 
    ic.socio_id,
    s.nome,
    s.cognome,
    s.codice_fiscale,
    ic.nome_corso,
    ic.data_iscrizione,
    ic.stato,
    ic.id
FROM iscrizioni_corsi ic
JOIN soci s ON ic.socio_id = s.id
WHERE (ic.socio_id, ic.nome_corso) IN (
    SELECT socio_id, nome_corso 
    FROM iscrizioni_corsi 
    GROUP BY socio_id, nome_corso 
    HAVING COUNT(*) > 1
)
ORDER BY s.cognome, s.nome, ic.nome_corso, ic.data_iscrizione DESC;
```

### 2.2 | Duplicati in `pagamenti`

```sql
-- Query 3: Pagamenti duplicati per lo stesso mese/anno/socio
SELECT 
    socio_id,
    mese_riferimento,
    anno_riferimento,
    corso,
    COUNT(*) as numero_duplicati,
    array_agg(id) as ids_record,
    array_agg(stato) as stati,
    array_agg(data_pagamento) as date_pagamento
FROM pagamenti
GROUP BY socio_id, mese_riferimento, anno_riferimento, corso
HAVING COUNT(*) > 1
ORDER BY numero_duplicati DESC;

-- Query 4: Dettagli pagamenti duplicati con dati socio
SELECT 
    p.socio_id,
    s.nome,
    s.cognome,
    p.mese_riferimento,
    p.anno_riferimento,
    p.corso,
    p.data_pagamento,
    p.stato,
    p.importo,
    p.id
FROM pagamenti p
JOIN soci s ON p.socio_id = s.id
WHERE (p.socio_id, p.mese_riferimento, p.anno_riferimento, p.corso) IN (
    SELECT socio_id, mese_riferimento, anno_riferimento, corso
    FROM pagamenti
    GROUP BY socio_id, mese_riferimento, anno_riferimento, corso
    HAVING COUNT(*) > 1
)
ORDER BY s.cognome, s.nome, p.anno_riferimento DESC, p.mese_riferimento DESC;
```

### 2.3 | Duplicati in `presenze`

```sql
-- Query 5: Presenze duplicate per lo stesso socio-data-corso
SELECT 
    socio_id,
    DATE(data_presenza) as data,
    corso,
    COUNT(*) as numero_duplicati,
    array_agg(id) as ids_record
FROM presenze
GROUP BY socio_id, DATE(data_presenza), corso
HAVING COUNT(*) > 1
ORDER BY numero_duplicati DESC;

-- Query 6: Dettagli presenze duplicate
SELECT 
    p.socio_id,
    s.nome,
    s.cognome,
    DATE(p.data_presenza) as data,
    p.corso,
    p.id,
    p.data_presenza
FROM presenze p
JOIN soci s ON p.socio_id = s.id
WHERE (p.socio_id, DATE(p.data_presenza), p.corso) IN (
    SELECT socio_id, DATE(data_presenza), corso
    FROM presenze
    GROUP BY socio_id, DATE(data_presenza), corso
    HAVING COUNT(*) > 1
)
ORDER BY s.cognome, s.nome, p.data_presenza DESC;
```

### 2.4 | Duplicati in `corsi` (case-insensitive)

```sql
-- Query 7: Corsi duplicati per variazioni case
SELECT 
    LOWER(TRIM(nome_corso)) as nome_normalizzato,
    COUNT(*) as numero_varianti,
    array_agg(DISTINCT nome_corso) as varianti,
    array_agg(id) as ids_record
FROM corsi
GROUP BY LOWER(TRIM(nome_corso))
HAVING COUNT(*) > 1
ORDER BY numero_varianti DESC;
```

### 2.5 | Discrepanze Corsi nelle Tabelle Collegate

```sql
-- Query 8: Corsi referenziati in iscrizioni_corsi che non esistono in corsi
SELECT DISTINCT 
    ic.nome_corso,
    COUNT(*) as numero_iscrizioni
FROM iscrizioni_corsi ic
WHERE ic.nome_corso NOT IN (SELECT nome_corso FROM corsi)
GROUP BY ic.nome_corso
ORDER BY numero_iscrizioni DESC;

-- Query 9: Corsi referenziati in presenze che non esistono in corsi
SELECT DISTINCT 
    p.corso,
    COUNT(*) as numero_presenze
FROM presenze p
WHERE p.corso NOT IN (SELECT nome_corso FROM corsi)
GROUP BY p.corso
ORDER BY numero_presenze DESC;

-- Query 10: Corsi referenziati in pagamenti che non esistono in corsi
SELECT DISTINCT 
    pa.corso,
    COUNT(*) as numero_pagamenti
FROM pagamenti pa
WHERE pa.corso NOT IN (SELECT nome_corso FROM corsi)
GROUP BY pa.corso
ORDER BY numero_pagamenti DESC;
```

---

## 3️⃣ SCRIPT SQL DI BONIFICA

**⚠️ ATTENZIONE**: Esegui questi script solo DOPO aver salvato un backup del database!

### 3.1 | Pulizia `iscrizioni_corsi` - Mantieni il record più recente

```sql
-- Passo 1: Identifica i record da eliminare (mantieni il più recente per ogni socio-corso)
WITH duplicati AS (
    SELECT 
        socio_id,
        nome_corso,
        id,
        ROW_NUMBER() OVER (PARTITION BY socio_id, nome_corso ORDER BY data_iscrizione DESC, created_at DESC) as rn
    FROM iscrizioni_corsi
)
DELETE FROM iscrizioni_corsi
WHERE id IN (
    SELECT id FROM duplicati WHERE rn > 1
);

-- Passo 2: Aggiungi vincolo UNIQUE per prevenire futuri duplicati
ALTER TABLE iscrizioni_corsi 
ADD CONSTRAINT unique_socio_corso_iscrizione 
UNIQUE (socio_id, nome_corso);
```

### 3.2 | Pulizia `pagamenti` - Mantieni il record più recente

```sql
-- Passo 1: Identifica i pagamenti da eliminare (mantieni il più recente)
WITH pagamenti_duplicati AS (
    SELECT 
        socio_id,
        mese_riferimento,
        anno_riferimento,
        corso,
        id,
        ROW_NUMBER() OVER (
            PARTITION BY socio_id, mese_riferimento, anno_riferimento, corso 
            ORDER BY data_pagamento DESC, created_at DESC
        ) as rn
    FROM pagamenti
)
DELETE FROM pagamenti
WHERE id IN (
    SELECT id FROM pagamenti_duplicati WHERE rn > 1
);

-- Passo 2: Aggiungi vincolo UNIQUE
ALTER TABLE pagamenti 
ADD CONSTRAINT unique_socio_pagamento_mensile 
UNIQUE (socio_id, mese_riferimento, anno_riferimento, corso);
```

### 3.3 | Pulizia `presenze` - Mantieni il record più recente

```sql
-- Passo 1: Identifica le presenze da eliminare
WITH presenze_duplicati AS (
    SELECT 
        socio_id,
        DATE(data_presenza) as data,
        corso,
        id,
        ROW_NUMBER() OVER (
            PARTITION BY socio_id, DATE(data_presenza), corso 
            ORDER BY data_presenza DESC, created_at DESC
        ) as rn
    FROM presenze
)
DELETE FROM presenze
WHERE id IN (
    SELECT id FROM presenze_duplicati WHERE rn > 1
);

-- Passo 2: Aggiungi vincolo UNIQUE
ALTER TABLE presenze 
ADD CONSTRAINT unique_socio_data_corso 
UNIQUE (socio_id, DATE(data_presenza), corso);
```

### 3.4 | Pulizia `corsi` - Consolida varianti case e normalizza

```sql
-- Passo 1: Identifica la variante più comune (o più recente) per ogni corso
WITH corsi_consolidati AS (
    SELECT 
        LOWER(TRIM(nome_corso)) as nome_normalizzato,
        id,
        nome_corso,
        ROW_NUMBER() OVER (PARTITION BY LOWER(TRIM(nome_corso)) ORDER BY created_at ASC) as rn
    FROM corsi
)
-- Passo 2: Aggiorna tutte le referenze alle varianti duplicate verso la variante principale
UPDATE iscrizioni_corsi ic
SET nome_corso = (
    SELECT nome_corso 
    FROM corsi_consolidati 
    WHERE LOWER(TRIM(corsi_consolidati.nome_corso)) = LOWER(TRIM(ic.nome_corso))
    AND rn = 1
)
WHERE LOWER(TRIM(nome_corso)) IN (
    SELECT LOWER(TRIM(nome_corso)) 
    FROM corsi 
    GROUP BY LOWER(TRIM(nome_corso)) 
    HAVING COUNT(*) > 1
);

UPDATE presenze p
SET corso = (
    SELECT nome_corso 
    FROM corsi_consolidati 
    WHERE LOWER(TRIM(corsi_consolidati.nome_corso)) = LOWER(TRIM(p.corso))
    AND rn = 1
)
WHERE LOWER(TRIM(corso)) IN (
    SELECT LOWER(TRIM(nome_corso)) 
    FROM corsi 
    GROUP BY LOWER(TRIM(nome_corso)) 
    HAVING COUNT(*) > 1
);

UPDATE pagamenti pa
SET corso = (
    SELECT nome_corso 
    FROM corsi_consolidati 
    WHERE LOWER(TRIM(corsi_consolidati.nome_corso)) = LOWER(TRIM(pa.corso))
    AND rn = 1
)
WHERE LOWER(TRIM(corso)) IN (
    SELECT LOWER(TRIM(nome_corso)) 
    FROM corsi 
    GROUP BY LOWER(TRIM(nome_corso)) 
    HAVING COUNT(*) > 1
);

-- Passo 3: Elimina le varianti duplicate
DELETE FROM corsi
WHERE id NOT IN (
    SELECT id 
    FROM corsi_consolidati 
    WHERE rn = 1
);

-- Passo 4: Aggiungi vincolo UNIQUE case-insensitive
ALTER TABLE corsi 
ADD CONSTRAINT unique_nome_corso_insensitive 
UNIQUE (LOWER(TRIM(nome_corso)));
```

### 3.5 | Verifica Completezza Dati (Post-Bonifica)

```sql
-- Query di verifica: Conferma che non ci sono più duplicati
SELECT 
    'iscrizioni_corsi' as tabella,
    COUNT(*) as numero_duplicati
FROM (
    SELECT socio_id, nome_corso, COUNT(*) as cnt
    FROM iscrizioni_corsi
    GROUP BY socio_id, nome_corso
    HAVING COUNT(*) > 1
) AS t
UNION ALL
SELECT 
    'pagamenti' as tabella,
    COUNT(*) as numero_duplicati
FROM (
    SELECT socio_id, mese_riferimento, anno_riferimento, corso, COUNT(*) as cnt
    FROM pagamenti
    GROUP BY socio_id, mese_riferimento, anno_riferimento, corso
    HAVING COUNT(*) > 1
) AS t
UNION ALL
SELECT 
    'presenze' as tabella,
    COUNT(*) as numero_duplicati
FROM (
    SELECT socio_id, DATE(data_presenza), corso, COUNT(*) as cnt
    FROM presenze
    GROUP BY socio_id, DATE(data_presenza), corso
    HAVING COUNT(*) > 1
) AS t;
```

---

## 4️⃣ PATCH DI CODICE CORRETTIVE

### 4.1 | FIX: iscrizione.html - Prevenzione Double-Submit

**File**: [public/iscrizione.html](public/iscrizione.html)  
**Linee da sostituire**: ~320-430

**PRIMA** (vulnerabile):
```javascript
async function inviaDomanda(e) {
    e.preventDefault();
    const btn = document.getElementById('submit-btn');
    btn.disabled = true;
    btn.textContent = "Invio in corso...";
    
    // ... long async operation ...
    
    // Problema: race condition tra clic e disabilitazione
}
```

**DOPO** (sicuro con double-submit protection):
```javascript
let isSubmitting = false;  // ← Flag di stato globale

async function inviaDomanda(e) {
    e.preventDefault();
    
    // ← PROTEZIONE: Rifiuta invii multipli
    if (isSubmitting) {
        console.warn("Invio già in corso, rifiuto doppio click");
        return;
    }
    
    isSubmitting = true;
    const btn = document.getElementById('submit-btn');
    btn.disabled = true;
    btn.textContent = "Invio in corso...";

    const fileInput = document.getElementById('file_medico');
    const file = fileInput.files[0];
    const scadenzaMedico = document.getElementById('scadenza_medico').value;
    const cf = document.getElementById('codice_fiscale').value.trim().toUpperCase();

    let fileUrl = null;

    try {
        // ... resto del codice rimane uguale ...
        
        // ← CAMBIO CRITICO: Usa UPSERT per soci se codice_fiscale esiste già
        const { data: existingRecord, error: existingError } = await supabaseClient
            .from('soci')
            .select('id')
            .eq('codice_fiscale', cf)
            .maybeSingle();

        if (existingError && existingError.code !== 'PGRST116') throw existingError;

        const nuovoCorso = document.getElementById('corso').value;
        const formData = { /* ... */ };
        let socioId = existingRecord?.id;

        // UPSERT: Se esiste, aggiorna; se no, crea
        const { data: socioData, error: socioError } = await supabaseClient
            .from('soci')
            .upsert(
                [{ ...formData, id: socioId }],
                { onConflict: 'id' }
            )
            .select('id')
            .single();

        if (socioError) throw socioError;
        socioId = socioData?.id;

        // ← CAMBIO CRITICO: Usa UPSERT per iscrizioni_corsi
        const corsoId = await trovaCorsoIdPerNome(nuovoCorso);
        if (!corsoId) throw new Error('Corso non trovato');

        const tabellaRelazione = await trovaTabellaRelazione();
        const relazionePayload = {
            socio_id: socioId,
            nome_corso: nuovoCorso,
            data_iscrizione: new Date().toISOString().slice(0, 10),
            stato: 'attiva'
        };

        // UPSERT con onConflict su (socio_id, nome_corso)
        const { error: relazioneError } = await supabaseClient
            .from(tabellaRelazione)
            .upsert(
                [relazionePayload],
                { onConflict: 'socio_id,nome_corso' }
            );

        if (relazioneError) throw relazioneError;

        // ... resto del codice ...
        
        alert("Registrazione completata con successo!");
        location.href = 'socio.html';
    } catch (err) {
        console.error(err);
        alert("Errore durante la registrazione: " + (err.message || 'Errore sconosciuto'));
    } finally {
        btn.disabled = false;
        btn.textContent = "Invia Domanda di Ammissione";
        isSubmitting = false;  // ← Rilascia il flag
    }
}
```

---

### 4.2 | FIX: socio.html - Double-Submit Protection

**File**: [public/socio.html](public/socio.html)  
**Linee da sostituire**: ~220-260

**PRIMA**:
```javascript
async function inviaPagamentoAvanzato(tesseratoId, corsoSocio) {
    const tipo = document.getElementById(`tipo_paga_${tesseratoId}`).value;
    const metodo = document.getElementById(`metodo_${tesseratoId}`).value;
    // ... setup ...
    const { error } = await supabaseClient.from('pagamenti').insert(records);
}
```

**DOPO**:
```javascript
let isProcessingPayment = false;  // ← Flag globale

async function inviaPagamentoAvanzato(tesseratoId, corsoSocio) {
    // ← Rifiuta invii multipli
    if (isProcessingPayment) {
        console.warn("Pagamento già in elaborazione");
        return;
    }
    isProcessingPayment = true;

    const btn = document.querySelector(`button[onclick="inviaPagamentoAvanzato('${tesseratoId}', '${corsoSocio.replace(/'/g, "\\'")}')" ]`);
    if (btn) { btn.disabled = true; btn.textContent = "Elaborazione..."; }

    try {
        const tipo = document.getElementById(`tipo_paga_${tesseratoId}`).value;
        const metodo = document.getElementById(`metodo_${tesseratoId}`).value;
        const file = document.getElementById(`filePaga_${tesseratoId}`).files[0];
        let url = null;

        if (metodo === 'bonifico') {
            if (!file) { alert("Allega ricevuta."); return; }
            const fileName = `p_${tesseratoId}_${Date.now()}.${file.name.split('.').pop()}`;
            const { error: e } = await supabaseClient.storage.from('ricevute_pagamenti').upload(fileName, file);
            if (e) { alert(e.message); return; }
            url = supabaseClient.storage.from('ricevute_pagamenti').getPublicUrl(fileName).data.publicUrl;
        }

        // ← Setup records ...
        const baseRecord = { 
            socio_id: tesseratoId, 
            metodo, 
            ricevuta_url: url, 
            stato: 'In attesa di verifica', 
            data_pagamento: new Date().toISOString().split('T')[0], 
            importo: 0, 
            importo_totale: 0, 
            corso: corsoSocio || 'Generale' 
        };
        const records = [];

        if (tipo === 'Mensilità' || tipo === 'Tranche') {
            const startM = parseInt(document.getElementById(`mese_${tesseratoId}`).value);
            const startA = parseInt(document.getElementById(`anno_${tesseratoId}`).value);
            const num = tipo === 'Tranche' ? parseInt(document.getElementById(`num_mesi_${tesseratoId}`).value) : 1;
            for(let i=0; i<num; i++) {
                let m = startM + i, a = startA;
                if(m > 12) { m -= 12; a++; }
                records.push({ 
                    ...baseRecord, 
                    mese_riferimento: m, 
                    anno_riferimento: a, 
                    tipo_pagamento: 'Mensilità', 
                    periodo_riferimento: `Mese ${m}/${a}` 
                });
            }
        } else {
            records.push({ 
                ...baseRecord, 
                corso: tipo === 'Iscrizione Annuale' ? 'Iscrizione Annuale' : corsoSocio, 
                tipo_pagamento: tipo, 
                periodo_riferimento: tipo === 'Iscrizione Annuale' ? 'A.A. 2026/2027' : 'Ingresso' 
            });
        }

        // ← CAMBIO CRITICO: Usa UPSERT con onConflict
        const { error } = await supabaseClient.from('pagamenti').upsert(records, {
            onConflict: 'socio_id,mese_riferimento,anno_riferimento,corso'
        });
        
        if (error) throw error;
        alert("Richiesta inviata!");
        location.reload();
    } catch (e) {
        alert(e.message);
    } finally {
        isProcessingPayment = false;
        if (btn) { btn.disabled = false; btn.textContent = "Conferma Operazione"; }
    }
}
```

---

### 4.3 | FIX: presenze.html - Double-Submit Protection

**File**: [public/presenze.html](public/presenze.html)  
**Linee da sostituire**: ~170-200

**PRIMA**:
```javascript
async function salvaPresenze() {
    const btn = document.getElementById('salva-btn');
    btn.disabled = true;
    
    const records = Array.from(presentiIds).map(socioId => ({
        socio_id: socioId,
        data_presenza: dataLezione,
        corso: corso
    }));
    
    const { error } = await supabaseClient.from('presenze').insert(records);
}
```

**DOPO**:
```javascript
let isSavingPresenze = false;

async function salvaPresenze() {
    // ← Rifiuta salvataggi multipli
    if (isSavingPresenze) {
        console.warn("Salvataggio presenze già in corso");
        return;
    }
    isSavingPresenze = true;

    const btn = document.getElementById('salva-btn');
    btn.disabled = true;
    btn.innerHTML = '<i class="fa-solid fa-spinner fa-spin mr-2"></i> SALVATAGGIO...';

    const corso = document.getElementById('corso-select').value;
    const dataLezione = document.getElementById('data-lezione').value;
    
    if (presentiIds.size === 0) {
        if (!confirm("Nessun presente selezionato. Vuoi salvare un appello senza presenti?")) {
            isSavingPresenze = false;
            btn.disabled = false;
            btn.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i> SALVA PRESENZE';
            return;
        }
    }

    const records = Array.from(presentiIds).map(socioId => ({
        socio_id: socioId,
        data_presenza: dataLezione,
        corso: corso
    }));

    try {
        if (records.length > 0) {
            // ← CAMBIO CRITICO: Usa UPSERT con onConflict
            const { error } = await supabaseClient
                .from('presenze')
                .upsert(records, {
                    onConflict: 'socio_id,data_presenza,corso'
                });
            
            if (error) throw error;
        }

        alert("Presenze salvate correttamente!");
        location.reload();
    } catch (err) {
        alert("Errore nel salvataggio: " + err.message);
    } finally {
        isSavingPresenze = false;
        btn.disabled = false;
        btn.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i> SALVA PRESENZE';
    }
}
```

---

### 4.4 | FIX: admin-contabilita.html - UPSERT for Payments

**File**: [public/admin-contabilita.html](public/admin-contabilita.html)  
**Linee da sostituire**: ~290-310

**PRIMA**:
```javascript
async function salvaPagamentoRapido() {
    const imp = document.getElementById('pay-amount').value;
    const met = document.getElementById('pay-method').value;
    if (!imp && !currentSelection.existingPagId) return;
    try {
        if (currentSelection.existingPagId) {
            await supabaseClient.from('pagamenti').update({ ... }).eq('id', currentSelection.existingPagId);
        } else {
            await supabaseClient.from('pagamenti').insert([{ ... }]);
        }
    }
}
```

**DOPO**:
```javascript
let isSavingPayment = false;

async function salvaPagamentoRapido() {
    // ← Rifiuta salvataggi multipli
    if (isSavingPayment) {
        console.warn("Salvataggio pagamento già in corso");
        return;
    }
    isSavingPayment = true;

    try {
        const imp = document.getElementById('pay-amount').value;
        const met = document.getElementById('pay-method').value;
        
        if (!imp && !currentSelection.existingPagId) {
            alert("Inserisci un importo.");
            return;
        }

        const paymentRecord = {
            socio_id: currentSelection.socioId,
            importo: parseFloat(imp) || 0,
            importo_totale: parseFloat(imp) || 0,
            mese_riferimento: currentSelection.mese,
            anno_riferimento: currentSelection.anno,
            data_pagamento: new Date().toISOString().split('T')[0],
            metodo: met,
            stato: 'Approvato',
            corso: currentSelection.tipo,
            tipo_pagamento: currentSelection.tipo,
            periodo_riferimento: currentSelection.mese === 0 ? 'Annuale' : `${currentSelection.mese}/${currentSelection.anno}`
        };

        // ← CAMBIO CRITICO: Usa UPSERT al posto di INSERT/UPDATE
        const { error } = await supabaseClient
            .from('pagamenti')
            .upsert(
                [paymentRecord],
                { 
                    onConflict: 'socio_id,mese_riferimento,anno_riferimento,corso'
                }
            );
        
        if (error) throw error;
        
        closeModal();
        caricaDatiContabili();
    } catch (err) {
        alert("Errore: " + err.message);
    } finally {
        isSavingPayment = false;
    }
}
```

---

## 5️⃣ PIANO DI IMPLEMENTAZIONE CONSIGLIATO

### Fase 1: Database Integrity (Immediato)
1. Esegui le query di diagnosi (Sezione 2) per misurare l'entità del problema
2. Esegui gli script di bonifica (Sezione 3) per pulire i dati
3. Aggiungi i vincoli UNIQUE per prevenire futuri duplicati

### Fase 2: Patch del Codice (Entro 24 ore)
1. Implementa le correzioni front-end (Sezione 4.1-4.4)
2. Testa ogni modulo con doppi-click
3. Verifica che i vincoli UNIQUE del database prevengono ancora i duplicati

### Fase 3: Deployment & Monitoring (Post-fix)
1. Deploy delle correzioni su Vercel
2. Monitora Supabase per errori di UNIQUE constraint violation
3. Aggiungi logging degli errori di UPSERT per tracciare tentativi di duplicazione

---

## 📊 MATRICE SEVERITÀ

| Componente | Severità | Causa | Fix Priorità |
|-----------|----------|-------|------|
| iscrizioni_corsi | 🔴 CRITICA | Double-submit + No UPSERT | **1** |
| pagamenti | 🔴 CRITICA | No UPSERT + No unique constraint | **1** |
| presenze | 🟡 MEDIA | No UPSERT | **2** |
| corsi | 🟡 MEDIA | Case-sensitivity + No unique constraint | **3** |
| Pulsanti form | 🔴 CRITICA | Race condition con disabilitazione | **1** |

---

## ✅ CHECKLIST POST-AUDIT

- [ ] Esecuzione Query di Diagnosi (Sezione 2)
- [ ] Esecuzione Script di Bonifica (Sezione 3)
- [ ] Implementazione Patch Codice (Sezione 4)
- [ ] Test doppi-click su tutti i form
- [ ] Verifica vincoli UNIQUE in Supabase
- [ ] Monitoring Logs per UNIQUE violations
- [ ] Documentazione changeset nel repository

---

## 📝 NOTE FINALI

1. **Root Cause**: Combinazione di vulnerabilità lato client (race conditions) + mancanza di vincoli lato server
2. **Quick Win**: Aggiungere vincoli UNIQUE risolve immediatamente il problema anche senza fix codice
3. **Long Term**: Implementare UPSERT nei form garantisce idempotenza e resilienza a network glitches
4. **Testing**: Simula lentezza di rete (DevTools > Network throttle) e doppi-click per verificare fix

