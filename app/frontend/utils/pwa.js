// Claudy installable (redesign, Michael 2026-10-29). Enregistre le service
// worker quand le layout le demande (balise `claudy-service-worker`, posée en
// production seulement, cf. `PwaHelper`), et garde l'invitation à installer
// que Chrome propose une seule fois, souvent avant que la page soit prête :
// `pwa-install` la reprend ensuite.
const swTag = document.querySelector('meta[name="claudy-service-worker"]');
if (swTag && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register(swTag.content, { scope: '/' }).catch(() => {});
  });
}

window.addEventListener('beforeinstallprompt', (event) => {
  event.preventDefault();
  window.claudyInstallPrompt = event;
  window.dispatchEvent(new CustomEvent('claudy:installable'));
});

window.addEventListener('appinstalled', () => {
  window.claudyInstallPrompt = null;
  window.dispatchEvent(new CustomEvent('claudy:installed'));
});
