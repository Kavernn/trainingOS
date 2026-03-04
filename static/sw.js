const CACHE_NAME = "trainingos-v1";

self.addEventListener("install", event => {
  console.log("Service Worker installed");
  self.skipWaiting();
});

self.addEventListener("activate", event => {
  console.log("Service Worker activated");
});

self.addEventListener("fetch", event => {
  // ⚠️ important: on ne casse rien
  event.respondWith(fetch(event.request));
});