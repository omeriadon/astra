const cacheName = 'astra-fixture-v1';
self.addEventListener('install', event => {
    event.waitUntil(caches.open(cacheName).then(cache => cache.addAll(['/', '/fixture.js', '/cache'])));
    self.skipWaiting();
});
self.addEventListener('activate', event => event.waitUntil(self.clients.claim()));
self.addEventListener('fetch', event => {
    if (event.request.method !== 'GET' || new URL(event.request.url).origin !== self.location.origin) return;
    event.respondWith(fetch(event.request).catch(async () => {
        const cached = await caches.match(event.request, { ignoreSearch: true });
        return cached || new Response('Offline fixture cache miss', { status: 503 });
    }));
});
