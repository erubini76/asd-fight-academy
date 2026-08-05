import { createClient } from '@supabase/supabase-js';

const RESEND_API_KEY = process.env.RESEND_API_KEY;
const SUPABASE_URL = process.env.SUPABASE_URL;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;
const ADMIN_EMAIL = 'kawasemidojo@gmail.com';

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

async function sendEmail(to, subject, htmlContent) {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${RESEND_API_KEY}`,
    },
    body: JSON.stringify({
      from: 'A.S.D. Fight Academy <onboarding@resend.dev>',
      to: [to],
      subject: subject,
      html: htmlContent,
    }),
  });
  return res.json();
}

export default async function handler(req, res) {
  try {
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    // 1. MONITORAGGIO CERTIFICATI MEDICI
    const { data: certificati, error: errCert } = await supabase
      .from('certificati_medici')
      .select('*, soci(nome, cognome, email)');

    if (errCert) throw errCert;

    let logCertificati = [];

    for (const cert of certificati) {
      if (!cert.data_scadenza || !cert.soci?.email) continue;

      const dataScad = new Date(cert.data_scadenza);
      const diffDays = Math.ceil((dataScad - today) / (1000 * 60 * 60 * 24));

      if ([45, 30, 15].includes(diffDays)) {
        const bodyAtleta = `
          <h2>Avviso Scadenza Certificato Medico</h2>
          <p>Ciao <strong>${cert.soci.nome} ${cert.soci.cognome}</strong>,</p>
          <p>Il tuo certificato medico scadrà il <strong>${cert.data_scadenza}</strong> (${diffDays} giorni rimanenti).</p>
          <p>Ti preghiamo di rinnovarlo e di inviarne copia alla segreteria.</p>
        `;
        await sendEmail(cert.soci.email, `Scadenza Certificato Medico (-${diffDays} gg)`, bodyAtleta);
        logCertificati.push(`Email inviata al socio ${cert.soci.email}`);

        // Invio copia alla segreteria a -30 e -15 gg
        if ([30, 15].includes(diffDays)) {
          const bodyAdmin = `
            <h3>Notifica Segreteria: Certificato in Scadenza</h3>
            <p>Atleta: <strong>${cert.soci.nome} ${cert.soci.cognome}</strong></p>
            <p>Scadenza: <strong>${cert.data_scadenza}</strong> (-${diffDays} gg)</p>
          `;
          await sendEmail(ADMIN_EMAIL, `[SEGRETERIA] Certificato in scadenza: ${cert.soci.nome}`, bodyAdmin);
          logCertificati.push(`Email admin inviata per ${cert.soci.nome}`);
        }
      }
    }

    // 2. MONITORAGGIO TESSERE ASI 365 GG
    const { data: soci, error: errSoci } = await supabase.from('soci').select('*');
    if (errSoci) throw errSoci;

    let logASI = [];

    for (const socio of soci) {
      if (!socio.data_tesseramento_asi) continue;

      const dataTess = new Date(socio.data_tesseramento_asi);
      const dataScadASI = new Date(dataTess.getTime() + 365 * 24 * 60 * 60 * 1000);
      const diffDaysASI = Math.ceil((dataScadASI - today) / (1000 * 60 * 60 * 24));

      if (diffDaysASI === 15) {
        const bodyASI = `
          <h2>Alert Scadenza Tesseramento ASI</h2>
          <p>La tessera ASI del socio <strong>${socio.nome} ${socio.cognome}</strong> (CF: ${socio.codice_fiscale}) scadrà il <strong>${dataScadASI.toISOString().split('T')[0]}</strong>.</p>
          <p>Procedere al rinnovo sul portale ASI (Cod. VEN-PD0814).</p>
        `;
        await sendEmail(ADMIN_EMAIL, `[ALERT ASI] Scadenza Tessera: ${socio.nome} ${socio.cognome}`, bodyASI);
        logASI.push(`Alert ASI inviato per ${socio.nome}`);
      }
    }

    return res.status(200).json({ success: true, logCertificati, logASI });
  } catch (error) {
    return res.status(500).json({ error: error.message });
  }
}
