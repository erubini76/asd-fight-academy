import { Resend } from 'resend';
import { createClient } from '@supabase/supabase-js';

const ADMIN_EMAIL = 'fighteste@gmail.com';
const FROM_EMAIL = process.env.EMAIL_FROM || 'Fight Academy <info@kawasemidojo.it>';
const resend = new Resend(process.env.RESEND_API_KEY);
const supabase = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY);

const buildMemberEmail = (memberEmail) => {
  const validEmail = typeof memberEmail === 'string' ? memberEmail.trim() : '';
  return {
    to: validEmail ? [validEmail] : [ADMIN_EMAIL],
    cc: validEmail && validEmail !== ADMIN_EMAIL ? [ADMIN_EMAIL] : undefined,
    reply_to: ADMIN_EMAIL
  };
};

export default async function handler(req, res) {
  if (req.method !== 'POST' && req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const socioId = typeof req.query?.socio_id === 'string' ? req.query.socio_id.trim() : '';

  try {
    const { data: tuttiSociScadenze, error } = await supabase
      .from('v_scadenze_soci')
      .select('*');
    const sociScadenze = socioId
      ? tuttiSociScadenze?.filter((socio) => socio.id === socioId || socio.socio_id === socioId)
      : tuttiSociScadenze;

    if (error) {
      return res.status(200).json({ success: false, message: "Vista SQL non pronta o vuota: " + error.message });
    }

    if (!sociScadenze || sociScadenze.length === 0) {
      return res.status(200).json({ success: true, processed: 0, logs: ["Nessun tesserato trovato nella vista di controllo."] });
    }

    let emailLogs = [];

    for (const socio of sociScadenze) {
      const { email, nome, cognome, giorni_alla_scadenza_medica, giorni_alla_scadenza_asi } = socio;

      if (giorni_alla_scadenza_medica !== null && [45, 30, 15].includes(giorni_alla_scadenza_medica)) {
        const memberMail = buildMemberEmail(email);
        if (memberMail.to.length > 0) {
          await resend.emails.send({
            from: FROM_EMAIL,
            to: memberMail.to,
            cc: memberMail.cc,
            reply_to: memberMail.reply_to,
            subject: `AVVISO: Scadenza Certificato Medico tra ${giorni_alla_scadenza_medica} giorni`,
            html: `<p>Ciao <strong>${nome || ''} ${cognome || ''}</strong>,</p><p>ti ricordiamo che il tuo certificato medico scadrà tra <strong>${giorni_alla_scadenza_medica} giorni</strong>.</p>`
          });
          emailLogs.push(`Certificato medico inviato a ${email || ADMIN_EMAIL} (${giorni_alla_scadenza_medica}gg)`);
        }
      }

      if (giorni_alla_scadenza_asi === 15) {
        await resend.emails.send({
          from: FROM_EMAIL,
          to: [ADMIN_EMAIL],
          reply_to: ADMIN_EMAIL,
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
