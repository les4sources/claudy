import { Controller } from '@hotwired/stimulus';

// Préremplit le prix sourcier d'un nouveau palier et affiche le prix de vente
// conseillé (issue #157, marge conseillée : Michael, 2026-09-30).
//
// Le calcul vit côté serveur (`Catalog::BuildPrice`) et pas ici : la marge
// sourcier est datée et paramétrable dans Tarifs, la dupliquer en JS
// garantirait qu'elle diverge un jour. Ce contrôleur ne fait qu'aller chercher
// la proposition, remplir le champ sourcier et afficher le conseil.
//
// Le prix public n'est JAMAIS prérempli : c'est une décision humaine. Le prix
// conseillé (marge de 30 % sur l'achat) s'affiche à côté, pour décider.
//
// Le champ sourcier reste librement modifiable — ce qui est enregistré est la
// valeur saisie. On ne le réécrit donc jamais une fois que l'humain l'a touché.
export default class extends Controller {
  static targets = ['purchase', 'member', 'recommended', 'recommendedValue'];
  static values = { url: String, channel: String };

  connect() {
    this.memberTouched = false;
    this.controller = null;

    if (this.hasMemberTarget) {
      this.memberTarget.addEventListener('input', () => (this.memberTouched = true));
    }
  }

  async suggest() {
    const params = new URLSearchParams({
      channel: this.channelValue,
      purchase: this.hasPurchaseTarget ? this.purchaseTarget.value : '',
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
      if (!this.memberTouched && this.hasMemberTarget && data.member_price != null) {
        this.memberTarget.value = this.format(data.member_price);
      }
      this.showRecommended(data.recommended_public_price);
    } catch (error) {
      if (error.name !== 'AbortError') throw error;
    }
  }

  showRecommended(value) {
    if (!this.hasRecommendedTarget) return;

    const known = value !== null && value !== undefined;
    this.recommendedTarget.classList.toggle('invisible', !known);
    if (known && this.hasRecommendedValueTarget) {
      this.recommendedValueTarget.textContent = `${this.format(value)} €`;
    }
  }

  format(value) {
    return Number(value).toFixed(2).replace('.', ',');
  }
}
