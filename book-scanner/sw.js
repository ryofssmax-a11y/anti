const C = 'bookscan-v1', F = ['./', 'index.html', 'app.js', 'pdf.js', 'icon.svg', 'manifest.webmanifest'];
self.addEventListener('install', (e) => e.waitUntil(caches.open(C).then((c) => c.addAll(F))));
self.addEventListener('activate', (e) => e.waitUntil(caches.keys().then((k) => Promise.all(k.filter((x) => x !== C).map((x) => caches.delete(x))))));
self.addEventListener('fetch', (e) => {
  if (new URL(e.request.url).origin !== location.origin) return;
  e.respondWith(fetch(e.request).catch(() => caches.match(e.request)));
});
