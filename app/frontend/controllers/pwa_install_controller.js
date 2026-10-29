import { Controller } from '@hotwired/stimulus';

// L'invitation à installer Claudy (redesign, Michael 2026-10-29), discrète, sur
// Aujourd'hui. Elle ne se montre que là où l'installation est possible : sous
// Android, quand Chrome l'a proposée (`beforeinstallprompt`, gardé par
// `utils/pwa.js`) ; sur iPhone et iPad dans Safari, avec le geste à faire.
// Jamais dans l'app déjà installée ; « Plus tard » la referme pour de bon.
const DISMISSED_KEY = 'claudy:install-dismissed';

export default class extends Controller {
  static targets = ['install', 'ios'];

  connect() {
    this.refresh = this.refresh.bind(this);
    window.addEventListener('claudy:installable', this.refresh);
    window.addEventListener('claudy:installed', this.refresh);
    this.refresh();
  }

  disconnect() {
    window.removeEventListener('claudy:installable', this.refresh);
    window.removeEventListener('claudy:installed', this.refresh);
  }

  refresh() {
    const prompt = window.claudyInstallPrompt;
    const ios = this.isIos() && !prompt;
    this.element.hidden = this.installed() || this.dismissed() || !(prompt || ios);
    this.installTargets.forEach((el) => { el.hidden = !prompt; });
    this.iosTargets.forEach((el) => { el.hidden = !ios; });
  }

  async install() {
    const prompt = window.claudyInstallPrompt;
    if (!prompt) return;
    prompt.prompt();
    await prompt.userChoice.catch(() => null);
    window.claudyInstallPrompt = null;
    this.refresh();
  }

  dismiss() {
    try { localStorage.setItem(DISMISSED_KEY, '1'); } catch (_) { /* navigation privée */ }
    this.element.hidden = true;
  }

  installed() {
    return window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true;
  }

  dismissed() {
    try { return localStorage.getItem(DISMISSED_KEY) === '1'; } catch (_) { return false; }
  }

  // iPadOS se présente comme un Mac : on le reconnaît à l'écran tactile.
  isIos() {
    const ua = window.navigator.userAgent;
    return /iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  }
}
