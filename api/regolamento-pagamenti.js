const REGOLAMENTO_BUCKET = 'regolamenti';
const REGOLAMENTO_FILE = 'Anno associativo 2026-27.pdf';

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Metodo non consentito' });
  }

  const { socioId, email, codiceFiscale } = req.body || {};
  if (!socioId || !email || !codiceFiscale) {
    return res.status(400).json({ error: 'Dati di accesso mancanti' });
  }

  try {
    const supabaseUrl = process.env.SUPABASE_URL;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('Variabili Supabase mancanti');
    }

    const headers = {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`
    };
    const query = new URLSearchParams({
      id: `eq.${socioId}`,
      email: `eq.${String(email).trim().toLowerCase()}`,
      codice_fiscale: `eq.${String(codiceFiscale).trim().toUpperCase()}`,
      select: 'id'
    });
    const socioResponse = await fetch(`${supabaseUrl}/rest/v1/soci?${query}`, { headers });
    if (!socioResponse.ok) throw new Error('Verifica accesso non riuscita');
    const soci = await socioResponse.json();
    if (!Array.isArray(soci) || soci.length !== 1) {
      return res.status(403).json({ error: 'Accesso al regolamento non autorizzato' });
    }

    const signedUrlResponse = await fetch(
      `${supabaseUrl}/storage/v1/object/sign/${REGOLAMENTO_BUCKET}/${encodeURIComponent(REGOLAMENTO_FILE)}`,
      {
        method: 'POST',
        headers: { ...headers, 'Content-Type': 'application/json' },
        body: JSON.stringify({ expiresIn: 600, download: REGOLAMENTO_FILE })
      }
    );
    if (!signedUrlResponse.ok) throw new Error('Creazione link firmato non riuscita');
    const signedUrlData = await signedUrlResponse.json();
    if (!signedUrlData.signedURL) throw new Error('Link firmato non ricevuto');

    return res.status(200).json({
      url: `${supabaseUrl}/storage/v1${signedUrlData.signedURL}`
    });
  } catch (error) {
    console.error('Errore download regolamento:', error);
    return res.status(500).json({ error: 'Regolamento non disponibile al momento' });
  }
}