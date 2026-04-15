// ── TrainingOS Service Worker ──────────────────────────
// ⚠️  CHANGE CE NUMÉRO À CHAQUE DÉPLOIEMENT pour forcer le refresh sur mobile
const CACHE_NAME = 'trainingos-v4';

const STATIC_ASSETS = [
  '/static/icons/icon-192.png',
  '/static/icons/icon-512.png',
  '/static/manifest.json',
];

// ── INSTALL ────────────────────────────────────────────
self.addEventListener('install', event => {
  console.log(`[SW] Installing ${CACHE_NAME}`);
  event.waitUntil(
    caches.open(CACHE_NAME)
      .then(cache => cache.addAll(STATIC_ASSETS.filter(Boolean)))
      .then(() => self.skipWaiting()) // activation immédiate sans attendre
  );
});

// ── ACTIVATE : supprime les vieux caches ───────────────
self.addEventListener('activate', event => {
  console.log(`[SW] Activating ${CACHE_NAME}`);
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(
        keys
          .filter(key => key !== CACHE_NAME)
          .map(key => { console.log(`[SW] Deleting old cache: ${key}`); return caches.delete(key); })
      ))
      .then(() => self.clients.claim()) // prend le contrôle de tous les onglets immédiatement
  );
});

// ── FETCH ──────────────────────────────────────────────
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // Ignore les requêtes non-GET
  if (event.request.method !== 'GET') return;

  // Ignore les APIs → toujours réseau
  if (url.pathname.startsWith('/api/')) return;

  // ── PAGES HTML → Network First ──────────────────────
  // Toujours essayer le réseau d'abord pour avoir la version fraîche
  if (event.request.headers.get('accept')?.includes('text/html')) {
    event.respondWith(
      fetch(event.request)
        .then(res => {
          // Mise en cache de la page fraîche
          if (res && res.status === 200) {
            const clone = res.clone();
            caches.open(CACHE_NAME).then(c => c.put(event.request, clone));
          }
          return res;
        })
        .catch(() => {
          // Offline → fallback sur la page cachée, ou l'accueil
          return caches.match(event.request)
            || caches.match('/');
        })
    );
    return;
  }

  // ── ASSETS STATIQUES (images, icons) → Cache First ──
  if (url.pathname.match(/\.(png|jpg|jpeg|svg|ico|woff2?|ttf)$/)) {
    event.respondWith(
      caches.match(event.request).then(cached => {
        if (cached) return cached;
        return fetch(event.request).then(res => {
          if (res && res.status === 200) {
            const clone = res.clone();
            caches.open(CACHE_NAME).then(c => c.put(event.request, clone));
          }
          return res;
        });
      })
    );
    return;
  }

  // ── Tout le reste → Network First, fallback cache ───
  event.respondWith(
    fetch(event.request)
      .catch(() => caches.match(event.request) || caches.match('/'))
  );
});