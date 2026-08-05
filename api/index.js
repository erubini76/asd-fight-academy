module.exports = (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Access-Control-Allow-Origin', '*');
  
  res.status(200).json({
    success: true,
    status: "Online",
    associazione: "A.S.D. Fight Academy",
    codiceFiscale: "91023520280",
    affiliazioneASI: "VEN-PD0814",
    timestamp: new Date().toISOString()
  });
};
