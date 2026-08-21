const REQUIRED_CONFIRMATION = 'ELIMINA';

function escapeFilter(value) {
  return encodeURIComponent(String(value).trim());
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Metodo non consentito' });
  }

  const { socioId, adminEmail, password, confirmation } = req.body || {};
  const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY } = process.env;

  if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return res.status(500).json({ error: 'Variabili Supabase non configurate su Vercel' });
  }
  if (!socioId || !adminEmail || !password || confirmation !== REQUIRED_CONFIRMATION) {
    return res.status(400).json({ error: 'Conferma o credenziali mancanti' });
  }

  const headers = {
    apikey: SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
    'Content-Type': 'application/json'
  };
  const restUrl = `${SUPABASE_URL}/rest/v1`;

  const getRows = async (path) => {
    const response = await fetch(`${restUrl}/${path}`, { headers });
    const body = await response.json();
    if (!response.ok) throw new Error(body.message || body.error || 'Errore lettura Supabase');
    return body;
  };

  const deleteRows = async (table, optional = false) => {
    const response = await fetch(`${restUrl}/${table}?socio_id=eq.${escapeFilter(socioId)}`, {
      method: 'DELETE',
      headers: { ...headers, Prefer: 'return=minimal' }
    });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      if (optional && body.code === 'PGRST205') return;
      throw new Error(`Errore eliminazione ${table}: ${body.message || JSON.stringify(body).slice(0, 300)}`);
    }
  };

  try {
    const admins = await getRows(`istruttori_corsi?select=id,ruolo,password_accesso&email=eq.${escapeFilter(adminEmail)}&limit=1`);
    const admin = admins[0];
    if (!admin || admin.ruolo !== 'presidente' || admin.password_accesso !== password) {
      return res.status(403).json({ error: 'Password amministratore non valida' });
    }

    const [soci, pagamenti, presenze, iscrizioniApprovate] = await Promise.all([
      getRows(`soci?select=id,nome,cognome&id=eq.${escapeFilter(socioId)}&limit=1`),
      getRows(`pagamenti?select=id&socio_id=eq.${escapeFilter(socioId)}&limit=1`),
      getRows(`presenze?select=id&socio_id=eq.${escapeFilter(socioId)}&limit=1`),
      getRows(`iscrizioni_annuali?select=id&socio_id=eq.${escapeFilter(socioId)}&stato=eq.Approvato&limit=1`)
    ]);

    if (!soci[0]) return res.status(404).json({ error: 'Tesserato non trovato' });
    if (pagamenti.length > 0 || presenze.length > 0 || iscrizioniApprovate.length > 0) {
      return res.status(409).json({
        error: 'Non eliminabile: il tesserato ha pagamenti, presenze o un’iscrizione approvata. Correggi i dati con la matita o archivia la pratica.'
      });
    }

    await deleteRows('consensi_tesseramento');
    await deleteRows('documenti_medici');
    await deleteRows('iscrizioni_annuali');
    await deleteRows('iscrizioni_corsi');
    await deleteRows('storico_modifiche', true);

    const response = await fetch(`${restUrl}/soci?id=eq.${escapeFilter(socioId)}`, {
      method: 'DELETE',
      headers: { ...headers, Prefer: 'return=representation' }
    });
    const deleted = await response.json();
    if (!response.ok || !deleted.length) {
      throw new Error('Il tesserato non è stato eliminato: potrebbero esistere altri dati collegati da verificare.');
    }

    return res.status(200).json({ success: true, message: 'Tesserato eliminato definitivamente' });
  } catch (err) {
    console.error('Errore eliminazione tesserato:', err.message);
    return res.status(500).json({ error: err.message });
  }
};
