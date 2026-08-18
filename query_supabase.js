const { createClient } = require('@supabase/supabase-js');

const SUPABASE_URL = 'https://twiizsottstaacnvrxkg.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR3aWl6c290dHN0YWFjbnZyeGtnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4NDk3ODAsImV4cCI6MjEwMTQyNTc4MH0.ksm6L4sWhCQ-zWY2SsYbZPuhdXhvevprrd2aIsMXfFI';
const supabaseClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

async function run() {
  try {
    // 1. Fetch Enrico Rubini's data from 'soci'
    const { data: soci, error: sociError } = await supabaseClient
      .from('soci')
      .select('*')
      .or('nome.ilike.%enrico%,cognome.ilike.%rubini%');
    
    if (sociError) {
      console.error('Error fetching soci:', sociError);
    } else {
      console.log('--- SOCI FOUND ---');
      console.log(JSON.stringify(soci, null, 2));
    }

    if (soci && soci.length > 0) {
      const targetSocio = soci.find(s => s.nome.toLowerCase().includes('enrico') && s.cognome.toLowerCase().includes('rubini'));
      if (targetSocio) {
        // 2. Fetch enrollment courses (iscrizioni_corsi) for this socio_id
        const { data: iscrizioni, error: iscrizioniError } = await supabaseClient
          .from('iscrizioni_corsi')
          .select('*')
          .eq('socio_id', targetSocio.id);
        
        if (iscrizioniError) {
          console.error('Error fetching iscrizioni_corsi:', iscrizioniError);
        } else {
          console.log('\n--- ISCRIZIONI CORSI ---');
          console.log(JSON.stringify(iscrizioni, null, 2));
        }
      }
    }

    // 3. Fetch instructor row for fusaro.pierpaolo@gmail.com
    const { data: istruttori, error: istruttoriError } = await supabaseClient
      .from('istruttori_corsi')
      .select('*')
      .eq('email', 'fusaro.pierpaolo@gmail.com');

    if (istruttoriError) {
      console.error('Error fetching istruttori:', istruttoriError);
    } else {
      console.log('\n--- ISTRUTTOTI_CORSI ---');
      console.log(JSON.stringify(istruttori, null, 2));
    }

  } catch (err) {
    console.error('Unexpected error:', err);
  }
}

run();
