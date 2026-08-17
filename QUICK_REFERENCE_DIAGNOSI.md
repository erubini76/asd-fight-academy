# QUICK REFERENCE - Diagnostica Veloce Duplicati

## Copia & Incolla nel Supabase Query Editor

### ⚡ Test Ultra-Rapido (30 secondi)

```sql
-- Esegui questa singola query per vedere il damage report completo
SELECT 
    'iscrizioni_corsi' as tabella,
    COUNT(*) as num_duplicati,
    (SELECT COUNT(*) FROM iscrizioni_corsi) as totale_records
FROM (
    SELECT socio_id, nome_corso FROM iscrizioni_corsi 
    GROUP BY socio_id, nome_corso HAVING COUNT(*) > 1
) AS t
UNION ALL
SELECT 
    'pagamenti',
    COUNT(*),
    (SELECT COUNT(*) FROM pagamenti)
FROM (
    SELECT socio_id, mese_riferimento, anno_riferimento, corso 
    FROM pagamenti 
    GROUP BY socio_id, mese_riferimento, anno_riferimento, corso HAVING COUNT(*) > 1
) AS t
UNION ALL
SELECT 
    'presenze',
    COUNT(*),
    (SELECT COUNT(*) FROM presenze)
FROM (
    SELECT socio_id, DATE(data_presenza), corso 
    FROM presenze 
    GROUP BY socio_id, DATE(data_presenza), corso HAVING COUNT(*) > 1
) AS t;
```

**Risultato atteso se NO bug**: Tutte le righe mostrano `0` in `num_duplicati`

---

### 🎯 I 3 Query Essenziali

#### Query 1: Socio con Iscrizioni Multiple allo STESSO Corso
```sql
SELECT s.nome, s.cognome, ic.nome_corso, COUNT(*) as numero_record
FROM iscrizioni_corsi ic
JOIN soci s ON ic.socio_id = s.id
GROUP BY s.nome, s.cognome, ic.nome_corso
HAVING COUNT(*) > 1;
```

#### Query 2: Socio con Pagamenti Multiple lo STESSO Mese
```sql
SELECT s.nome, s.cognome, p.mese_riferimento, p.anno_riferimento, COUNT(*) as numero_record
FROM pagamenti p
JOIN soci s ON p.socio_id = s.id
GROUP BY s.nome, s.cognome, p.mese_riferimento, p.anno_riferimento
HAVING COUNT(*) > 1;
```

#### Query 3: Corsi con Varianti (Karate vs KARATE vs karate)
```sql
SELECT LOWER(nome_corso), array_agg(DISTINCT nome_corso), COUNT(DISTINCT nome_corso) as varianti
FROM corsi
GROUP BY LOWER(nome_corso)
HAVING COUNT(DISTINCT nome_corso) > 1;
```

---

### ✅ Verifica Vincoli UNIQUE (Sono già stati aggiunti?)

```sql
-- Se questa query restituisce 0 righe = mancano i vincoli
SELECT constraint_name, table_name
FROM information_schema.table_constraints
WHERE constraint_type = 'UNIQUE' 
  AND table_name IN ('iscrizioni_corsi', 'pagamenti', 'presenze', 'corsi');
```

---

### 📊 Statistiche Fedeltà Dati

```sql
-- Percentuale di purezza dati
SELECT 
    ROUND(100.0 * (total_records - duplicated_records) / total_records, 1) || '%' as data_purity
FROM (
    SELECT 
        (SELECT COUNT(*) FROM iscrizioni_corsi) +
        (SELECT COUNT(*) FROM pagamenti) +
        (SELECT COUNT(*) FROM presenze) as total_records,
        
        (SELECT COUNT(*) FROM (
            SELECT 1 FROM iscrizioni_corsi 
            GROUP BY socio_id, nome_corso HAVING COUNT(*) > 1
        ) x) +
        (SELECT COUNT(*) FROM (
            SELECT 1 FROM pagamenti 
            GROUP BY socio_id, mese_riferimento, anno_riferimento, corso HAVING COUNT(*) > 1
        ) y) +
        (SELECT COUNT(*) FROM (
            SELECT 1 FROM presenze 
            GROUP BY socio_id, DATE(data_presenza), corso HAVING COUNT(*) > 1
        ) z) as duplicated_records
) stats;
```

---

## Interpretazione Risultati

| Scenario | Risultato Query | Significato | Azione |
|----------|-----------------|-------------|--------|
| Nessun duplicato | `0 0 0` | ✅ Database OK | Nessuna |
| Pochi duplicati | `2 1 0` | ⚠️ Piccolo problema | Esegui SQL_BONIFICA.sql |
| Molti duplicati | `50+ 30+ 20+` | 🔴 CRITICO | SUBITO bonifica + fix code |
| Data purity < 90% | `< 90%` | 🔴 CRITICO | Bonifica + vincoli UNIQUE |

---

## 🎬 Step-By-Step Esecuzione

### Passo 1: Diagnosi (2 minuti)
```
1. Apri Supabase Dashboard
2. SQL Editor → Nuova query
3. Copia-incolla "Test Ultra-Rapido" sopra
4. Click "Run"
5. Nota i numeri
```

### Passo 2: Se c'è danno (10 minuti)
```
1. Vai al file SQL_BONIFICA.sql (nella tua cartella repo)
2. Copia TUTTO il contenuto
3. Supabase SQL Editor → Nuova query
4. Incolla
5. Click "Run" (⚠️ Assicurati di avere backup!)
```

### Passo 3: Verifica (2 minuti)
```
1. Esegui di nuovo il "Test Ultra-Rapido"
2. Se tutte le righe mostrano 0 = ✅ Successo!
3. Se ancora valori > 0 = Contattare developer
```

---

## 🚨 Se Hai Dubbi

### "Ho eseguito SQL_DIAGNOSI.sql e vedo duplicati. Devo eseguire SQL_BONIFICA.sql?"

**SÌ** - Procedure:
1. Backup Supabase (Settings > Backups > Download snapshot)
2. Aspetta che il backup finisca
3. Esegui SQL_BONIFICA.sql
4. Verifica risultato con Test Ultra-Rapido

### "SQL_BONIFICA.sql dice 'Constraint already exists', cosa faccio?"

**NIENTE** - Significa che il vincolo è già lì. Continua, la procedura è idempotente.

### "Ho eliminato accidentalmente un record durante bonifica, posso recuperarlo?"

**SÌ** - Se hai fatto il backup:
1. Supabase Dashboard > Backups
2. Restore dal punto pre-bonifica
3. Riprova bonifica

### "Quanti record dovrebbero essere eliminati?"

**Dipende** dal tuo utilizzo:
- Nessun duplicato = 0 cancellati
- Uso intenso con doppi-click = 10-50+ cancellati
- Non è un'indicazione di qualità, solo di frequenza di errori

---

## 📱 Monitoraggio Post-Fix

Dopo aver eseguito SQL_BONIFICA.sql:

### Alert da configurare in Supabase
```
Settings > Alerts > Aggiungi custom alert:

Tipo: Database Error
Condizione: Error message contiene "duplicate key" OR "UNIQUE violation"
Azione: Notifica email admin

Significato: Se scatta = bug nel codice ancora presente
```

### Log da monitorare
```
1. Supabase > Logs
2. Filtra per tabella = "iscrizioni_corsi"
3. Se vedi "23505" error = duplicate key violation = BUG CODE RIMASTO
```

---

## 🎯 Metrica di Successo

**Prima Fix**:
- N record duplicati nel database
- Utenti segnalano "Mi è stato addebitato due volte!"
- Istruttori vedono presenze doppie

**Dopo Fix**:
- 0 record duplicati
- Doppio-click = niente accade (idempotente)
- Database rifiuta duplicati con vincolo UNIQUE

---

**Generato**: 17 Agosto 2026 | Senior Full-Stack Engineer Audit
