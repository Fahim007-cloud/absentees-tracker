const CACHE_NAME = 'absentees-tracker-v3';
const ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './icon-512-maskable.png',
  './apple-touch-icon.png'
];

// The app shell depends on these CDN libraries to even boot (React,
// Supabase client, html2canvas, jsPDF, ExcelJS, the in-browser JSX
// compiler). They're fetched explicitly at install time — the runtime
// fetch handler below deliberately doesn't cache cross-origin responses
// (that branch also carries live Supabase API calls, which must never
// be served stale), so without this the app would only work offline
// after a previous online visit had a chance to load them.
const CDN_ASSETS = [
  'https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js',
  'https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js',
  'https://cdn.jsdelivr.net/npm/exceljs@4.4.0/dist/exceljs.min.js',
  'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js',
  'https://unpkg.com/react@18/umd/react.production.min.js',
  'https://unpkg.com/react-dom@18/umd/react-dom.production.min.js',
  'https://unpkg.com/@babel/standalone/babel.min.js'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(async (cache) => {
      await cache.addAll(ASSETS);
      // Best-effort: don't let one failed CDN fetch break install.
      await Promise.all(CDN_ASSETS.map((url) =>
        fetch(url).then((res) => { if (res.ok) return cache.put(url, res); }).catch(() => {})
      ));
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;

  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) {
    // CDN scripts (React, Supabase, html2canvas, fonts) and API calls:
    // network-first, don't try to cache/intercept Supabase requests
    event.respondWith(fetch(event.request).catch(() => caches.match(event.request)));
    return;
  }

  // App shell (HTML/JSON/JS) — network-first, so a redeploy is picked up
  // on the very next load instead of being stuck on whatever got cached
  // the first time the app was opened. Falls back to cache when offline.
  event.respondWith(
    fetch(event.request).then((response) => {
      const copy = response.clone();
      caches.open(CACHE_NAME).then((cache) => cache.put(event.request, copy));
      return response;
    }).catch(() => caches.match(event.request).then((cached) => cached || caches.match('./index.html')))
  );
});
