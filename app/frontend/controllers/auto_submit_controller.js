import { Controller } from '@hotwired/stimulus';

// Soumet le formulaire porteur dès que le champ change — sans bouton « OK ».
// Deux usages sur l'index Séjours (Michael 2026-07-26) :
//   - le `<select>` de catégorie en ligne (delay 0 : le choix EST la validation) ;
//   - le champ de recherche (delay ~300 ms : on attend la fin de la frappe).
//
// Le formulaire reste soumissible nativement (touche Entrée, JS désactivé) : ce
// contrôleur ne fait qu'anticiper la soumission, il ne la remplace pas.
export default class extends Controller {
  static values = { delay: { type: Number, default: 0 } };

  connect() {
    this.timeout = null;
  }

  disconnect() {
    this.clear();
  }

  submit() {
    this.clear();
    if (this.delayValue > 0) {
      this.timeout = setTimeout(() => this.perform(), this.delayValue);
    } else {
      this.perform();
    }
  }

  perform() {
    // `requestSubmit` (et non `submit`) pour que Turbo intercepte la soumission
    // et que la validation HTML native s'applique.
    this.element.requestSubmit();
  }

  clear() {
    if (this.timeout) {
      clearTimeout(this.timeout);
      this.timeout = null;
    }
  }
}
