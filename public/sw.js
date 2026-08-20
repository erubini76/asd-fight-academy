// Service worker minimale richiesto per l'installabilità della PWA.
const CACHE_NAME = 'fight-academy-shell-v1';

self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

// Pass-through di rete: nessuna cache offline, solo per soddisfare i criteri PWA.
self.addEventListener('fetch', (event) => {
  event.respondWith(fetch(event.request).catch(() => caches.match(event.request)));
});
