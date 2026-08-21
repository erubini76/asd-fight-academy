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

  const { tipo, nome, cognome, email, telefono, codice_fiscale, corso } = req.body;
  const RESEND_API_KEY = process.env.RESEND_API_KEY;
  const ADMIN_EMAIL = 'kawasemidojo@gmail.com';
  const FROM_EMAIL = process.env.EMAIL_FROM || 'Fight Academy <info@kawasemidojo.it>';

  if (!RESEND_API_KEY) {
    return res.status(500).json({ error: 'Chiave RESEND_API_KEY non configurata su Vercel' });
  }

  const buildMemberMail = (memberEmail) => {
    const validEmail = typeof memberEmail === 'string' ? memberEmail.trim() : '';
    return {
      to: validEmail ? [validEmail] : [ADMIN_EMAIL],
      cc: validEmail && validEmail !== ADMIN_EMAIL ? [ADMIN_EMAIL] : undefined,
      reply_to: ADMIN_EMAIL
    };
  };

  try {
    if (tipo === 'approvazione') {
      const memberMail = buildMemberMail(email);
      const resendApproval = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${RESEND_API_KEY}`
        },
        body: JSON.stringify({
          from: FROM_EMAIL,
          to: memberMail.to,
          cc: memberMail.cc,
          reply_to: memberMail.reply_to,
          subject: 'Iscrizione approvata - A.S.D. Fight Academy',
          html: `
            <div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
              <h2 style="color: #15803d;">A.S.D. FIGHT ACADEMY</h2>
              <p>Ciao <strong>${nome} ${cognome}</strong>,</p>
              <p>la tua iscrizione al corso <strong>${corso || 'selezionato'}</strong> è stata approvata.</p>
              <p>Puoi accedere all'Area Tesserati per consultare i tuoi dati.</p>
            </div>
          `
        })
      });
      const approvalResult = await resendApproval.json();
      if (!resendApproval.ok) {
        console.error('Errore Resend approvazione:', approvalResult);
        return res.status(500).json({ error: 'Errore invio email approvazione: ' + JSON.stringify(approvalResult) });
      }
      return res.status(200).json({ success: true, message: 'Email di approvazione inviata' });
    }

    const memberMail = buildMemberMail(email);

    const resendUser = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: memberMail.to,
        cc: memberMail.cc,
        reply_to: memberMail.reply_to,
        subject: `Ricezione Domanda - ${nome} ${cognome}`,
        html: `
          <div style="font-family: Arial, sans-serif; padding: 20px; color: #333;">
            <h2 style="color: #b91c1c;">A.S.D. FIGHT ACADEMY</h2>
            <p>Ciao <strong>${nome} ${cognome}</strong>,</p>
            <p>Abbiamo ricevuto correttamente la tua domanda di tesseramento per il corso <strong>${corso || 'Selezionato'}</strong>.</p>
            <p>Ti contatteremo al più presto.</p>
          </div>
        `
      })
    });

    const userResult = await resendUser.json();
    if (!resendUser.ok) {
      console.error('Errore Resend utente:', userResult);
      return res.status(500).json({ error: 'Errore invio email utente: ' + JSON.stringify(userResult) });
    }

    const resendAdmin = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: [ADMIN_EMAIL],
        reply_to: ADMIN_EMAIL,
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
      console.error('Errore Resend admin:', adminResult);
      return res.status(500).json({ error: 'Errore invio email admin: ' + JSON.stringify(adminResult) });
    }

    return res.status(200).json({ success: true, message: 'Email elaborate con successo' });
  } catch (error) {
    console.error('Eccezione invio email:', error);
    return res.status(500).json({ error: error.message });
  }
};