import { Resend } from 'resend';
import { createClient } from '@supabase/supabase-js';

const resend = new Resend(process.env.RESEND_API_KEY);
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

export default async function handler(req, res) {
  if (req.method !== 'POST' && req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  try {
    const { data: sociScadenze, error } = await supabase
      .from('v_scadenze_soci')
      .select('*');

    if (error) {
      return res.status(200).json({ success: false, message: "Vista SQL non pronta o vuota: " + error.message });
    }

    if (!sociScadenze || sociScadenze.length === 0) {
      return res.status(200).json({ success: true, processed: 0, logs: ["Nessun socio trovato nella vista di controllo."] });
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
          await resend.emails.send({
            from: 'A.S.D. Fight Academy <onboarding@resend.dev>',
            to: recipients,
            subject: `AVVISO: Scadenza Certificato Medico tra ${giorni_alla_scadenza_medica} giorni`,
            html: `<p>Ciao <strong>${nome || ''} ${cognome || ''}</strong>,</p><p>ti ricordiamo che il tuo certificato medico scadrà tra <strong>${giorni_alla_scadenza_medica} giorni</strong>.</p>`
          });
          emailLogs.push(`Certificato medico inviato a ${email} (${giorni_alla_scadenza_medica}gg)`);
        }
      }

      if (giorni_alla_scadenza_asi === 15) {
        await resend.emails.send({
          from: 'A.S.D. Fight Academy <onboarding@resend.dev>',
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
