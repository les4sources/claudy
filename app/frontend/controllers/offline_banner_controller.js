import { Controller } from '@hotwired/stimulus';

// Le bandeau « Hors ligne » (redesign, Michael 2026-10-29). Deux cas :
// - la page est une COPIE servie par le service worker (`data-offline-copy`
//   sur <body>, l'heure de la copie) : on dit de quand datent les données ;
// - le réseau tombe pendant qu'on lit : la page reste lisible, mais rien ne
//   s'enregistre tant qu'il manque.
export default class extends Controller {
  static targets = ['text'];

  connect() {
    this.update = this.update.bind(this);
    window.addEventListener('online', this.update);
    window.addEventListener('offline', this.update);
    this.update();
  }

  disconnect() {
    window.removeEventListener('online', this.update);
    window.removeEventListener('offline', this.update);
  }

  update() {
    const copy = document.body.dataset.offlineCopy;
    const offline = copy || navigator.onLine === false;
    this.element.hidden = !offline;
    if (!offline) return;

    this.textTarget.textContent = copy
      ? `données de ${this.when(new Date(copy))}. Rien ne s’enregistre tant que le réseau manque.`
      : 'la page reste lisible, mais rien ne s’enregistre tant que le réseau manque.';
  }

  when(date) {
    const time = date.toLocaleTimeString('fr-BE', { hour: '2-digit', minute: '2-digit' });
    if (date.toDateString() === new Date().toDateString()) return time;
    return `${date.toLocaleDateString('fr-BE', { weekday: 'long', day: 'numeric', month: 'long' })}, ${time}`;
  }
}
