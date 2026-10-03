/* Al Hyakel Portal service worker: lets the portal be installed like an app.
   Pages and files come from the network first (so updates show at once);
   the saved copy is only used when there is no internet. Supabase data is never cached. */
const CACHE = 'ah-portal-v3';
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

/* phone notifications (sent by the Supabase function "notify") */
self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (err) { d = {body: e.data && e.data.text()}; }
  e.waitUntil(self.registration.showNotification(d.title || 'Al Hyakel Portal', {
    body: d.body || '', icon: 'assets/icon-192.png', badge: 'assets/icon-192.png',
    tag: d.tag || undefined, renotify: !!d.tag, data: {url: d.url || 'index.html'}
  }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const url = new URL(e.notification.data && e.notification.data.url || 'index.html', self.registration.scope).href;
  e.waitUntil(self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(list => {
    const same = list.find(c => c.url.split('#')[0] === url.split('#')[0]);
    if (same) { same.navigate(url).catch(() => {}); return same.focus(); }
    return self.clients.openWindow(url);
  }));
});
