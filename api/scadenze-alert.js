export default async function handler(req, res) {
  if (req.method !== 'POST' && req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { RESEND_API_KEY, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY } = process.env;
  if (!RESEND_API_KEY || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
    return res.status(500).json({ error: 'Variabili ambiente mancanti su Vercel (RESEND_API_KEY / SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY)' });
  }

  try {
    const supabaseResponse = await fetch(`${SUPABASE_URL}/rest/v1/v_scadenze_soci?select=*`, {
      headers: {
        apikey: SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`
      }
    });
    const supabaseBody = await supabaseResponse.json();

    if (!supabaseResponse.ok) {
      return res.status(200).json({ success: false, message: 'Vista SQL non pronta o non accessibile: ' + (supabaseBody.message || supabaseBody.error || 'errore Supabase') });
    }

    const sociScadenze = supabaseBody;

    if (!sociScadenze || sociScadenze.length === 0) {
      return res.status(200).json({ success: true, processed: 0, logs: ["Nessun tesserato trovato nella vista di controllo."] });
    }

    let emailLogs = [];

    for (const socio of sociScadenze) {
      const { email, nome, cognome, giorni_alla_scadenza_medica, giorni_alla_scadenza_asi } = socio;

      if (giorni_alla_scadenza_medica !== null && [45, 30, 15].includes(giorni_alla_scadenza_medica)) {
        let recipients = email ? [email] : [];
        if (giorni_alla_scadenza_medica <= 30) {
          recipients.push('kawasemidojo@gmail.com');
        }
        if (recipients.length > 0) {
          await inviaEmail({
            apiKey: RESEND_API_KEY,
            to: recipients,
            subject: `AVVISO: Scadenza Certificato Medico tra ${giorni_alla_scadenza_medica} giorni`,
            html: `<p>Ciao <strong>${nome || ''} ${cognome || ''}</strong>,</p><p>ti ricordiamo che il tuo certificato medico scadrà tra <strong>${giorni_alla_scadenza_medica} giorni</strong>.</p>`
          });
          emailLogs.push(`Certificato medico inviato a ${email} (${giorni_alla_scadenza_medica}gg)`);
        }
      }

      if (giorni_alla_scadenza_asi === 15) {
        await inviaEmail({
          apiKey: RESEND_API_KEY,
          to: ['kawasemidojo@gmail.com'],
          subject: `ALERT ASI: Tessera per ${nome || ''} ${cognome || ''}`,
          html: `<p>La tessera ASI di <strong>${nome || ''} ${cognome || ''}</strong> scadrà tra 15 giorni.</p>`
        });
        emailLogs.push(`Alert ASI inviato per ${nome} ${cognome}`);
      }
    }

    return res.status(200).json({ success: true, processed: sociScadenze.length, logs: emailLogs });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ error: err.message });
  }
}

async function inviaEmail({ apiKey, to, subject, html }) {
  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`
    },
    body: JSON.stringify({
      from: 'A.S.D. Fight Academy <onboarding@resend.dev>',
      to,
      subject,
      html
    })
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Resend ${response.status}: ${body.slice(0, 300)}`);
  }
}