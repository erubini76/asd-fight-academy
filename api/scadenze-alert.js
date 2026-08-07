import { Resend } from 'resend';
import { createClient } from '@supabase/supabase-js';

const resend = new Resend(process.env.RESEND_API_KEY);
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

export default async function handler(req, res) {
  if (req.method !== 'POST' && req.method !== 'GET') {
    return res.status(405.json({ error: 'Method not allowed' }));
  }

  try {
    // Interroghiamo la vista SQL creata nello step precedente
    const { data: sociScadenze, error } = await supabase
      .from('v_scadenze_soci')
      .select('*');

    if (error) throw error;

    let emailLogs = [];

    for (const socio of sociScadenze) {
      const { email, nome, cognome, giorni_alla_scadenza_medica, giorni_alla_scadenza_asi } = socio;

      // 1. Controllo Scadenza Certificato Medico (-45, -30, -15 giorni)
      if ([45, 30, 15].includes(giorni_alla_scadenza_medica)) {
        let recipients = [email];
        // Copia al presidente per -30 e -15 giorni
        if (giorni_alla_scadenza_medica <= 30) {
          recipients.push('kawasemidojo@gmail.com');
        }

        await resend.emails.send({
          from: 'A.S.D. Fight Academy <onboarding@resend.dev>', // Sostituire con dominio verificato se disponibile
          to: recipients,
          subject: `AVVISO: Scadenza Certificato Medico tra ${giorni_alla_scadenza_medica} giorni`,
          html: `<p>Ciao <strong>${nome} ${cognome}</strong>,</p><p>ti ricordiamo che il tuo certificato medico scadrà tra <strong>${giorni_alla_scadenza_medica} giorni</strong>. Ti invitiamo a caricarne uno nuovo al più presto.</p>`
        });
        emailLogs.push(`Certificato medico inviato a ${email} (${giorni_alla_scadenza_medica}gg)`);
      }

      // 2. Controllo Scadenza Tessera ASI (-15 giorni -> invio al Presidente)
      if (giorni_alla_scadenza_asi === 15) {
        await resend.emails.send({
          from: 'A.S.D. Fight Academy <onboarding@resend.dev>',
          to: ['kawasemidojo@gmail.com'],
          subject: `ALERT ASI: Scadenza Tessera per ${nome} ${cognome}`,
          html: `<p>Il Presidente viene informato che la tessera ASI del socio <strong>${nome} ${cognome}</strong> scadrà tra <strong>15 giorni</strong>.</p>`
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