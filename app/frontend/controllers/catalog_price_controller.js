import { Controller } from '@hotwired/stimulus';

// Préremplit les prix sourcier et public d'un nouveau palier (issue #157).
//
// Le calcul vit côté serveur (`Catalog::BuildPrice`) et pas ici : les
// coefficients sont datés et paramétrables dans Tarifs, les dupliquer en JS
// garantirait qu'ils divergent un jour. Ce contrôleur ne fait qu'aller
// chercher la proposition et remplir les champs.
//
// Les champs restent librement modifiables — ce qui est enregistré est la
// valeur saisie, jamais le résultat du calcul. On ne réécrit donc jamais un
// champ que l'humain a déjà touché.
export default class extends Controller {
  static targets = ['purchase', 'reference', 'member', 'public'];
  static values = { url: String, channel: String };

  connect() {
    this.touched = new Set();
    this.controller = null;

    ['member', 'public'].forEach((name) => {
      if (this[`has${name[0].toUpperCase()}${name.slice(1)}Target`]) {
        this[`${name}Target`].addEventListener('input', () => this.touched.add(name));
      }
    });
  }

  async suggest() {
    const params = new URLSearchParams({
      channel: this.channelValue,
      purchase: this.hasPurchaseTarget ? this.purchaseTarget.value : '',
      reference: this.hasReferenceTarget ? this.referenceTarget.value : '',
    });

    // Une frappe rapide lance plusieurs requêtes : on annule la précédente pour
    // qu'une réponse en retard ne vienne pas écraser une proposition plus récente.
    this.controller?.abort();
    this.controller = new AbortController();

    try {
      const response = await fetch(`${this.urlValue}?${params}`, {
        signal: this.controller.signal,
        headers: { Accept: 'application/json' },
      });
      if (!response.ok) return;

      const data = await response.json();
      this.fill('member', data.member_price);
      this.fill('public', data.public_price);
    } catch (error) {
      if (error.name !== 'AbortError') throw error;
    }
  }

  fill(name, value) {
    if (this.touched.has(name) || value === null || value === undefined) return;

    const target = this[`${name}Target`];
    if (target) target.value = Number(value).toFixed(2).replace('.', ',');
  }
}
