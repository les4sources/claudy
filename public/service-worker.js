// Le service worker de Claudy (redesign, Michael 2026-10-29, maquette
// « Claudy dans la poche »). Trois règles, rien de plus :
//
// 1. La coquille (polices, styles, scripts de Vite, icônes) se garde dès
//    qu'elle a été vue : ses fichiers portent une empreinte, ils ne changent
//    jamais sous le même nom.
// 2. Aujourd'hui, l'Agenda et la Cuisine se lisent d'abord sur le réseau ; la
//    dernière copie reçue reste sur le téléphone et sert quand le réseau
//    manque, marquée de l'heure de la copie (`data-offline-copy` sur <body>).
// 3. Tout le reste passe tel quel. Sans réseau, une page qu'on n'a pas en copie
//    affiche `/hors-ligne.html`. Rien n'écrit hors ligne : un formulaire envoyé
//    sans réseau échoue comme avant.
//
// La copie des pages est effacée à la déconnexion, et dès qu'une page renvoie
// vers la connexion : un téléphone prêté ne garde pas la journée de quelqu'un.
//
// Changer VERSION remplace les caches au prochain chargement.
const VERSION = "2026-10-29-1"
const SHELL_CACHE = `claudy-shell-${VERSION}`
const PAGES_CACHE = "claudy-pages"
const OFFLINE_URL = "/hors-ligne.html"
const PRECACHE = [OFFLINE_URL, "/icons/claudy-192.png", "/apple-touch-icon.png"]

// Les écrans qu'on veut pouvoir relire au fond du domaine, sans réseau.
const READABLE_OFFLINE = [/^\/$/, /^\/aujourdhui$/, /^\/kitchen\/orders$/]
// Les fichiers à empreinte : servis du cache, jamais redemandés.
const SHELL_ASSETS = [/^\/vite\//, /^\/vite-dev\//, /^\/icons\//, /\.(woff2?|ttf)$/]

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(SHELL_CACHE).then((cache) => cache.addAll(PRECACHE)).then(() => self.skipWaiting()))
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((key) => key.startsWith("claudy-shell-") && key !== SHELL_CACHE).map((key) => caches.delete(key))))
      .then(() => self.clients.claim())
  )
})

// Appelée par la page au moment de la déconnexion.
self.addEventListener("message", (event) => {
  if (event.data === "claudy:forget-pages") event.waitUntil(caches.delete(PAGES_CACHE))
})

self.addEventListener("fetch", (event) => {
  const request = event.request
  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return

  // Se déconnecter oublie les copies, quel que soit le chemin pris.
  if (request.method !== "GET") {
    if (url.pathname === "/users/sign_out") event.waitUntil(caches.delete(PAGES_CACHE))
    return
  }

  if (SHELL_ASSETS.some((pattern) => pattern.test(url.pathname))) {
    event.respondWith(cacheFirst(request))
    return
  }

  if (isPageRequest(request)) event.respondWith(networkFirstPage(request, url))
})

// Une page entière : une navigation, ou une visite Turbo (fetch qui accepte du
// HTML, sans cadre). Un cadre Turbo n'est jamais mis en copie.
function isPageRequest(request) {
  if (request.mode === "navigate") return true
  return (request.headers.get("Accept") || "").includes("text/html") && !request.headers.get("Turbo-Frame")
}

async function cacheFirst(request) {
  const cached = await caches.match(request)
  if (cached) return cached
  const response = await fetch(request)
  if (response.ok) {
    const cache = await caches.open(SHELL_CACHE)
    cache.put(request, response.clone())
  }
  return response
}

async function networkFirstPage(request, url) {
  const readable = READABLE_OFFLINE.some((pattern) => pattern.test(url.pathname))
  try {
    const response = await fetch(request)
    // Renvoyé vers la connexion : la session est finie, les copies aussi.
    if (response.redirected && new URL(response.url).pathname.startsWith("/users/sign_in")) {
      await caches.delete(PAGES_CACHE)
    } else if (readable && response.ok && !response.redirected) {
      const cache = await caches.open(PAGES_CACHE)
      await cache.put(request.url, await stampCopy(response.clone()))
    }
    return response
  } catch (error) {
    if (readable) {
      const copy = await caches.open(PAGES_CACHE).then((cache) => cache.match(request.url))
      if (copy) return copy
    }
    const offline = await caches.match(OFFLINE_URL)
    return offline || Response.error()
  }
}

// La copie porte l'heure où elle a été prise : la page la dit en bandeau.
async function stampCopy(response) {
  const html = await response.text()
  const stamped = html.replace(/<body([^>]*)>/i, `<body$1 data-offline-copy="${new Date().toISOString()}">`)
  const headers = new Headers(response.headers)
  headers.delete("Content-Length")
  return new Response(stamped, { status: 200, statusText: "OK", headers })
}
