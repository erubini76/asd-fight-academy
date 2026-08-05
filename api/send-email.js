module.exports = async (req, res) => {
  // Configurazione CORS per consentire le chiamate dal Frontend
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET,OPTIONS,POST');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'X-CSRF-Token, X-Requested-With, Accept, Accept-Version, Content-Length, Content-MD5, Content-Type, Date, X-Api-Version'
  );

  // Gestione pre-flight request CORS
  if (req.method === 'OPTIONS') {
    res.status(200).end();
    return;
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Metodo non consentito' });
  }

  const { nome, cognome, email, telefono, corso_scelto } = req.body;
  const RESEND_API_KEY = process.env.RESEND_API_KEY;

  if (!RESEND_API_KEY) {
    return res.status(500).json({ error: 'Chiave RESEND_API_KEY non configurata su Vercel' });
  }

  try {
    // 1. Email di conferma inviata al Socio / Atleta
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`
      },
      body: JSON.stringify({
        from: 'A.S.D. Fight Academy <onboarding@resend.dev>',
        to: [email],
        subject: 'Ricezione Domanda di Ammissione - A.S.D. Fight Academy',
        html: `
          <div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
            <h2 style="color: #b91c1c;">A.S.D. FIGHT ACADEMY</h2>
            <p>Ciao <strong>${nome} ${cognome}</strong>,</p>
            <p>Abbiamo ricevuto correttamente la tua domanda di ammissione a socio per il corso <strong>${corso_scelto}</strong>.</p>
            <p>La segreteria verificherà i dati inviati e ti contatterà a breve per completare il tesseramento.</p>
            <hr style="border: 0; border-top: 1px solid #ccc; margin: 20px 0;" />
            <p style="font-size: 12px; color: #666;">
              A.S.D. Fight Academy - C.F. 91023520280<br>
              Sede Operativa: Via B. Powell 2, Este (PD)
            </p>
          </div>
        `
      })
    });

    // 2. Email di notifica inviata al Presidente (kawasemidojo@gmail.com)
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`
      },
      body: JSON.stringify({
        from: 'A.S.D. Fight Academy <onboarding@resend.dev>',
        to: ['kawasemidojo@gmail.com'],
        subject: `[NUOVA ISCRIZIONE] ${nome} ${cognome} - ${corso_scelto}`,
        html: `
          <div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
            <h3 style="color: #b91c1c;">Nuova Domanda di Ammissione a Socio</h3>
            <ul>
              <li><strong>Nome e Cognome:</strong> ${nome} ${cognome}</li>
              <li><strong>Email:</strong> ${email}</li>
              <li><strong>Telefono:</strong> ${telefono}</li>
              <li><strong>Corso Scelto:</strong> ${corso_scelto}</li>
            </ul>
            <p>Accedi al Dashboard di Supabase per consultare la scheda anagrafica completa.</p>
          </div>
        `
      })
    });

    return res.status(200).json({ success: true, message: 'Email inviate con successo' });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
};
