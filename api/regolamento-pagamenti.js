import { createClient } from '@supabase/supabase-js';

const REGOLAMENTO_BUCKET = 'regolamenti';
const REGOLAMENTO_FILE = 'Anno associativo 2026-27.pdf';

const supabase = createClient(
  process.env.SUPABASE_URL,
  process.env.SUPABASE_SERVICE_ROLE_KEY
);

export default async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Metodo non consentito' });
  }

  const { socioId, email, codiceFiscale } = req.body || {};
  if (!socioId || !email || !codiceFiscale) {
    return res.status(400).json({ error: 'Dati di accesso mancanti' });
  }

  try {
    const { data: socio, error: socioError } = await supabase
      .from('soci')
      .select('id')
      .eq('id', socioId)
      .eq('email', String(email).trim().toLowerCase())
      .eq('codice_fiscale', String(codiceFiscale).trim().toUpperCase())
      .maybeSingle();

    if (socioError) throw socioError;
    if (!socio) {
      return res.status(403).json({ error: 'Accesso al regolamento non autorizzato' });
    }

    const { data, error } = await supabase.storage
      .from(REGOLAMENTO_BUCKET)
      .createSignedUrl(REGOLAMENTO_FILE, 600, { download: REGOLAMENTO_FILE });

    if (error) throw error;
    return res.status(200).json({ url: data.signedUrl });
  } catch (error) {
    console.error('Errore download regolamento:', error);
    return res.status(500).json({ error: 'Regolamento non disponibile al momento' });
  }
}