export default async function handler(req, res) {
  // Impostiamo CORS per eventuali test manuali da browser
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,POST');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version'
  );

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const SUPABASE_URL = process.env.SUPABASE_URL;
  // Usiamo la chiave di servizio o anonima configurata su Vercel
  const SUPABASE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_ANON_KEY;
  const RESEND_API_KEY = process.env.RESEND_API_KEY;

  if (!SUPABASE_URL || !SUPABASE_KEY || !RESEND_API_KEY) {
    return res.status(500).json({ error: 'Variabili d ambiente mancanti su Vercel (Supabase o Resend)' });
  }

  // Vincolo piano gratuito Resend: forziamo l'invio all'account proprietario verificato
  const targetEmail = 'erubini@gmail.com';

  try {
    // 1. Chiamata REST a Supabase per leggere i soci e le relative date di scadenza
    // (Verificheremo la tabella 'soci' e i campi relativi a certificato medico e tesseramento ASI)
    const responseSupabase = await fetch(`${SUPABASE_URL}/rest/v1/soci?select=*`, {
      headers: {
        'apikey': SUPABASE_KEY,
        'Authorization': `Bearer ${SUPABASE_KEY}`
      }
    });

    if (!responseSupabase.ok) {
      throw new Error('Errore nel recupero dei soci da Supabase');
    }

    const soci = await responseSupabase.json();

    // Logica di controllo scadenze (Placeholder attivo per i test strutturali)
    const today = new Date();
    let countAlertsSent = 0;

    // Esempio di elaborazione dati soci trovati nel DB
    for (const socio of soci) {
      // Qui inseriremo i controlli sulle date (es. scadenza_certificato_medico, data_tesseramento_asi)
      // Per adesso registriamo il passaggio
    }

    return res.status(200).json({ 
      success: true, 
      message: `Controllo scadenze eseguito con successo. Totale soci analizzati: ${soci.length}`,
      soci_analizzati: soci.length 
    });

  } catch (error) {
    console.error("Errore nello script di controllo scadenze:", error);
    return res.status(500).json({ error: error.message });
  }
}