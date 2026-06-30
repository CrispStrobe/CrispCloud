// web/service-worker.js
//
// CrispCloud PWA Service Worker
// - network-first for the HTML shell + Flutter JS (always consistent with the
//   latest deploy; cache is only an offline fallback)
// - network-first for API / dynamic requests
// - cache-first for immutable static assets (icons, manifest, fonts)
//
// Why the shell is network-first: the Flutter app code (`main.dart.js`,
// `flutter_bootstrap.js`, deferred `*.part.js`) changes hash every build and
// every Flutter upgrade. Caching it cache-first meant a returning user could be
// served a STALE `main.dart.js` that no longer matched the freshly-deployed
// `flutter_bootstrap.js`/`index.html` — a hard mismatch that renders a blank
// white screen. Serving the shell network-first guarantees the bootstrap and
// the app bundle always come from the same deploy.
//
// Bump CACHE_VERSION on any shell change to evict poisoned caches.

const CACHE_VERSION = 'v4';
const STATIC_CACHE  = `crisp-cloud-static-${CACHE_VERSION}`;
const DYNAMIC_CACHE = `crisp-cloud-dynamic-${CACHE_VERSION}`;

// App-shell resources to pre-cache on install (offline fallback only — these
// are still fetched network-first at runtime so the live deploy always wins).
const APP_SHELL = [
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/flutter.js',
  '/manifest.json',
  '/favicon.png',
  '/icons/Icon-192.png',
  '/icons/Icon-512.png',
  '/icons/Icon-maskable-192.png',
  '/icons/Icon-maskable-512.png',
];

// URL patterns treated as "API / network-first".
const NETWORK_FIRST_PATTERNS = [
  /\/api\//,
  /\/oauth/,
  /\/auth/,
];

// The HTML shell and Flutter JS bundle: must always match the live deploy, so
// these are served network-first (cache is only the offline fallback). Anything
// else (icons, fonts, hash-named immutable assets) stays cache-first.
function isAppShell(url) {
  const path = url.pathname;
  if (path === '/' || path === '/index.html') return true;
  if (path.endsWith('flutter_bootstrap.js')) return true;
  if (path.endsWith('flutter.js')) return true;
  if (path.endsWith('flutter_service_worker.js')) return true;
  if (path.endsWith('.dart.js')) return true;          // main.dart.js
  if (/\.part\.js$/.test(path)) return true;           // deferred chunks
  return false;
}

// --------------------------------------------------------------------------
// Install — pre-cache the app shell
// --------------------------------------------------------------------------
self.addEventListener('install', (event) => {
  console.log('[SW] Install – caching app shell');
  event.waitUntil(
    caches.open(STATIC_CACHE).then((cache) =>
      cache.addAll(APP_SHELL).catch((err) => {
        // Non-fatal: some resources may not exist yet during dev builds.
        console.warn('[SW] App-shell pre-cache partial failure:', err);
      })
    ).then(() => self.skipWaiting())
  );
});

// --------------------------------------------------------------------------
// Activate — delete stale caches
// --------------------------------------------------------------------------
self.addEventListener('activate', (event) => {
  console.log('[SW] Activate – pruning old caches');
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((k) => k !== STATIC_CACHE && k !== DYNAMIC_CACHE)
          .map((k) => {
            console.log('[SW] Deleting old cache:', k);
            return caches.delete(k);
          })
      )
    ).then(() => self.clients.claim())
  );
});

// --------------------------------------------------------------------------
// Fetch — route requests to the appropriate strategy
// --------------------------------------------------------------------------
self.addEventListener('fetch', (event) => {
  const { request } = event;
  const url = new URL(request.url);

  // Skip non-GET requests and browser-extension / chrome-extension URLs.
  if (request.method !== 'GET') return;
  if (!url.protocol.startsWith('http')) return;

  // Never intercept WASM, worker scripts, or source maps — let them 404
  // naturally instead of returning cached HTML from the SPA rewrite.
  const skipExtensions = ['.wasm', '.map'];
  const skipFiles = ['drift_worker.js', 'sqlite3.wasm'];
  if (skipExtensions.some(ext => url.pathname.endsWith(ext))) return;
  if (skipFiles.some(f => url.pathname.endsWith(f))) return;

  // App shell + Flutter JS and API calls are network-first (always match the
  // live deploy / latest data); immutable static assets are cache-first.
  const useNetworkFirst =
      isAppShell(url) || NETWORK_FIRST_PATTERNS.some((re) => re.test(url.pathname));

  if (useNetworkFirst) {
    event.respondWith(networkFirst(request));
  } else {
    event.respondWith(cacheFirst(request));
  }
});

// --------------------------------------------------------------------------
// Strategy: cache-first (static assets, app shell)
// --------------------------------------------------------------------------
async function cacheFirst(request) {
  const cached = await caches.match(request);
  if (cached) return cached;

  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(STATIC_CACHE);
      cache.put(request, response.clone());
    }
    return response;
  } catch (err) {
    console.warn('[SW] Cache-first network failure for', request.url, err);
    // Return a minimal offline page if the HTML shell itself is unavailable.
    const fallback = await caches.match('/index.html');
    return fallback || new Response('CrispCloud is offline', {
      status: 503,
      headers: { 'Content-Type': 'text/plain' },
    });
  }
}

// --------------------------------------------------------------------------
// Strategy: network-first (API calls, auth endpoints)
// --------------------------------------------------------------------------
async function networkFirst(request) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(DYNAMIC_CACHE);
      cache.put(request, response.clone());
    }
    return response;
  } catch (err) {
    console.warn('[SW] Network-first fallback to cache for', request.url);
    const cached = await caches.match(request);
    return cached || new Response(JSON.stringify({ error: 'offline' }), {
      status: 503,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}

// --------------------------------------------------------------------------
// Push notifications (from server-sent Web Push)
// --------------------------------------------------------------------------
self.addEventListener('push', (event) => {
  let data = { title: 'CrispCloud', body: 'New notification' };
  try {
    if (event.data) data = event.data.json();
  } catch (_) {
    if (event.data) data.body = event.data.text();
  }

  const options = {
    body: data.body || '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    tag: data.tag || 'crisp-cloud',
    data: data.url ? { url: data.url } : {},
  };

  event.waitUntil(
    self.registration.showNotification(data.title || 'CrispCloud', options)
  );
});

// --------------------------------------------------------------------------
// Notification click — focus or open the app
// --------------------------------------------------------------------------
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const targetUrl = (event.notification.data && event.notification.data.url)
    ? event.notification.data.url
    : '/';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if (client.url === targetUrl && 'focus' in client) {
          return client.focus();
        }
      }
      return clients.openWindow(targetUrl);
    })
  );
});
