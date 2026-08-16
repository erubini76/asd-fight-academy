module.exports = async (req, res) => {
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

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Metodo non consentito' });
  }

  const { nome, cognome, email, telefono, codice_fiscale, corso } = req.body;
  const RESEND_API_KEY = process.env.RESEND_API_KEY;

  if (!RESEND_API_KEY) {
    return res.status(500).json({ error: 'Chiave RESEND_API_KEY non configurata su Vercel' });
  }

  // Vincolo piano gratuito Resend: forziamo l'invio all'account proprietario verificato per evitare blocchi
  const targetEmail = 'erubini@gmail.com';

  try {
    // 1. Email di conferma simulata al Tesserato
    const resendUser = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`
      },
      body: JSON.stringify({
        from: 'A.S.D. Fight Academy <onboarding@resend.dev>',
        to: [targetEmail],
        subject: `[TEST UTENTE] Ricezione Domanda - ${nome} ${cognome}`,
        html: `
          <div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
            <h2 style="color: #b91c1c;">A.S.D. FIGHT ACADEMY</h2>
            <p>Ciao <strong>${nome} ${cognome}</strong>,</p>
            <p>Abbiamo ricevuto correttamente la tua domanda di tesseramento per il corso <strong>${corso || 'Selezionato'}</strong>.</p>
            <p>Email originale destinatario: ${email}</p>
          </div>
        `
      })
    });

    const userResult = await resendUser.json();
    if (!resendUser.ok) {
      console.error("Errore Resend utente:", userResult);
      return res.status(500).json({ error: "Errore invio email utente: " + JSON.stringify(userResult) });
    }

    // 2. Email di notifica al Presidente / Admin
    const resendAdmin = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`
      },
      body: JSON.stringify({
        from: 'A.S.D. Fight Academy <onboarding@resend.dev>',
        to: [targetEmail],
        subject: `[NUOVA ISCRIZIONE ADMIN] ${nome} ${cognome} - ${corso || 'Corso'}`,
        html: `
          <div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
            <h3 style="color: #b91c1c;">Nuovo Tesseramento</h3>
            <ul>
              <li><strong>Nome e Cognome:</strong> ${nome} ${cognome}</li>
              <li><strong>Codice Fiscale:</strong> ${codice_fiscale}</li>
              <li><strong>Email:</strong> ${email}</li>
              <li><strong>Telefono:</strong> ${telefono}</li>
              <li><strong>Corso Scelto:</strong> ${corso}</li>
            </ul>
          </div>
        `
      })
    });

    const adminResult = await resendAdmin.json();
    if (!resendAdmin.ok) {
      console.error("Errore Resend admin:", adminResult);
      return res.status(500).json({ error: "Errore invio email admin: " + JSON.stringify(adminResult) });
    }

    return res.status(200).json({ success: true, message: 'Email elaborate con successo' });
  } catch (error) {
    console.error("Eccezione invio email:", error);
    return res.status(500).json({ error: error.message });
  }
};