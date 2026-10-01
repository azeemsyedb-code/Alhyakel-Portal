/* Al Hyakel Portal service worker: lets the portal be installed like an app.
   Pages and files come from the network first (so updates show at once);
   the saved copy is only used when there is no internet. Supabase data is never cached. */
const CACHE = 'ah-portal-v1';
const CORE = ['index.html', 'login.html', 'documents.html', 'inventory.html', 'employees.html', 'access.html',
  'assets/portal.css', 'assets/shell.css', 'assets/portal.js', 'assets/config.js', 'assets/logo_mark.png',
  'assets/header.jpg', 'assets/footer.jpg', 'assets/stamp.png', 'assets/icon-192.png'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => Promise.allSettled(CORE.map(u => c.add(u)))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', e => {
  e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== location.origin) return;     // Supabase, CDNs, fonts: straight to the network
  e.respondWith(fetch(req).then(res => {
    if (res.ok) { const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); }
    return res;
  }).catch(() => caches.match(req, {ignoreSearch: true}).then(r => r || caches.match('index.html'))));
});
