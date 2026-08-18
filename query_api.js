const SUPABASE_URL = 'https://twiizsottstaacnvrxkg.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InR3aWl6c290dHN0YWFjbnZyeGtnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU4NDk3ODAsImV4cCI6MjEwMTQyNTc4MH0.ksm6L4sWhCQ-zWY2SsYbZPuhdXhvevprrd2aIsMXfFI';

async function fetchSupabase(endpoint) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${endpoint}`, {
    headers: {
      'apikey': SUPABASE_ANON_KEY,
      'Authorization': `Bearer ${SUPABASE_ANON_KEY}`
    }
  });
  if (!response.ok) {
    throw new Error(`HTTP error! status: ${response.status} ${await response.text()}`);
  }
  return response.json();
}

async function run() {
  try {
    const soci = await fetchSupabase('soci?nome=ilike.*enrico*&cognome=ilike.*rubini*');
    console.log('--- SOCI FOUND ---');
    console.log(JSON.stringify(soci, null, 2));

    if (soci && soci.length > 0) {
      const targetSocio = soci.find(s => s.nome.toLowerCase().includes('enrico') && s.cognome.toLowerCase().includes('rubini'));
      if (targetSocio) {
        const iscrizioni = await fetchSupabase(`iscrizioni_corsi?socio_id=eq.${targetSocio.id}`);
        console.log('\n--- ISCRIZIONI CORSI ---');
        console.log(JSON.stringify(iscrizioni, null, 2));
      }
    }

    const istruttori = await fetchSupabase('istruttori_corsi?email=eq.fusaro.pierpaolo@gmail.com');
    console.log('\n--- ISTRUTTORI_CORSI ---');
    console.log(JSON.stringify(istruttori, null, 2));

  } catch (err) {
    console.error('Error:', err);
  }
}

run();
