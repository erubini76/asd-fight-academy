const ADMIN_EMAIL = 'kawasemidojo@gmail.com';
const FROM_EMAIL = process.env.EMAIL_FROM || 'Fight Academy <info@kawasemidojo.it>';

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

module.exports = async (req, res) => {
  res.setHeader('Access-Control-Allow-Credentials', true);
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST,OPTIONS');
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

  const RESEND_API_KEY = process.env.RESEND_API_KEY;
  if (!RESEND_API_KEY) {
    return res.status(500).json({ error: 'Chiave RESEND_API_KEY non configurata su Vercel' });
  }

  const { corso, istruttoreEmail, istruttoreNome, righe, totaleCumulativo } = req.body || {};

  const istruttoreEmailValida = typeof istruttoreEmail === 'string' ? istruttoreEmail.trim() : '';
  if (!istruttoreEmailValida) {
    return res.status(400).json({ error: 'Email istruttore principale mancante o non valida' });
  }
  if (!Array.isArray(righe) || righe.length === 0) {
    return res.status(400).json({ error: 'Nessun mese selezionato per la notifica' });
  }

  const elencoMesi = righe.map(r => `${r.meseLabel} ${r.anno}`).join(', ');

  const righeHtml = righe.map(r => `
    <tr>
      <td style="padding:8px;border:1px solid #334155;">${escapeHtml(r.meseLabel)} ${escapeHtml(r.anno)}</td>
      <td style="padding:8px;border:1px solid #334155;text-align:right;">€${Number(r.contanti || 0).toFixed(2)}</td>
      <td style="padding:8px;border:1px solid #334155;text-align:right;">€${Number(r.bonifici || 0).toFixed(2)}</td>
      <td style="padding:8px;border:1px solid #334155;text-align:right;">€${Number(r.totale || 0).toFixed(2)}</td>
      <td style="padding:8px;border:1px solid #334155;text-align:right;">€${Number(r.quotaIstruttore || 0).toFixed(2)}</td>
      <td style="padding:8px;border:1px solid #334155;text-align:right;">€${Number(r.quotaPalestra || 0).toFixed(2)}</td>
      <td style="padding:8px;border:1px solid #334155;text-align:right;font-weight:bold;">€${Number(r.conguaglio || 0).toFixed(2)}</td>
    </tr>
  `).join('');

  const html = `
    <div style="font-family: Arial, sans-serif; padding: 20px; color: #1e293b;">
      <h2 style="color: #b91c1c;">A.S.D. FIGHT ACADEMY</h2>
      <p>Ciao <strong>${escapeHtml(istruttoreNome || '')}</strong>,</p>
      <p>Ti comunichiamo il conguaglio relativo al corso <strong>${escapeHtml(corso || '')}</strong> per i mesi: <strong>${escapeHtml(elencoMesi)}</strong>.</p>
      <table style="border-collapse: collapse; width: 100%; font-size: 13px;">
        <thead>
          <tr style="background:#0f172a;color:#fff;">
            <th style="padding:8px;border:1px solid #334155;">Mese</th>
            <th style="padding:8px;border:1px solid #334155;">Contanti</th>
            <th style="padding:8px;border:1px solid #334155;">Bonifici</th>
            <th style="padding:8px;border:1px solid #334155;">Totale</th>
            <th style="padding:8px;border:1px solid #334155;">Quota Istruttore</th>
            <th style="padding:8px;border:1px solid #334155;">Quota Palestra</th>
            <th style="padding:8px;border:1px solid #334155;">Istruttore &rarr; Palestra</th>
          </tr>
        </thead>
        <tbody>
          ${righeHtml}
        </tbody>
      </table>
      <p style="margin-top:16px;font-size:15px;">
        <strong>Totale cumulativo conguaglio (Istruttore &rarr; Palestra): €${Number(totaleCumulativo || 0).toFixed(2)}</strong>
      </p>
      <p style="font-size:12px;color:#64748b;margin-top:8px;">
        Valore positivo: versamento dovuto dall'istruttore alla palestra in contanti.<br>
        Valore negativo: credito da accreditare all'istruttore.
      </p>
      <p style="margin-top:20px;">I mesi indicati sono stati chiusi (bloccati) e non sono piu modificabili dal registro incassi.</p>
    </div>
  `;

  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${RESEND_API_KEY}`
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: [istruttoreEmailValida],
        cc: [ADMIN_EMAIL],
        reply_to: ADMIN_EMAIL,
        subject: `[Fight Academy] Notifica Conguaglio - Corso ${corso || ''} - Mesi: ${elencoMesi}`,
        html
      })
    });

    const result = await response.json();
    if (!response.ok) {
      console.error('Errore Resend conguaglio:', result);
      return res.status(500).json({ error: 'Errore invio email conguaglio: ' + JSON.stringify(result) });
    }

    return res.status(200).json({ success: true, message: 'Notifica conguaglio inviata' });
  } catch (err) {
    console.error('Eccezione invio email conguaglio:', err);
    return res.status(500).json({ error: err.message });
  }
};
