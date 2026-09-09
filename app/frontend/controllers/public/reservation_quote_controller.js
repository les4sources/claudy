import { Controller } from "@hotwired/stimulus"

// Recalcule le devis du funnel /reservation sans rechargement complet
// (AC-T2-10). À chaque modification d'un champ de composition, on soumet le
// formulaire de devis qui répond en Turbo Stream et remplace le panneau.
//
// ── POURQUOI CE CONTRÔLEUR SÉRIALISE SES REQUÊTES ──────────────────────────
// Cinq clics rapides sur la grille Espaces partaient en cinq POST /devis
// concurrents. Le brouillon vit dans un COOKIE de session : chaque réponse
// renvoie l'état complet du panier, et c'est la DERNIÈRE ARRIVÉE qui gagne —
// pas la dernière émise. Une réponse partie avec trois jours cochés écrasait
// donc une réponse partie avec cinq, et le visiteur se retrouvait avec un
// devis qui affirmait trois jours alors qu'il en voyait cinq cochés à l'écran.
// Le mensonge tenait jusqu'au clic suivant, et le brouillon persisté — celui
// qui part en demande — ne portait bel et bien que trois jours.
//
// Trois garde-fous, qui règlent chacun une moitié du problème :
//   1. une seule requête en vol ; un changement pendant ce temps marque le
//      formulaire « sale » et déclenche UNE requête de rattrapage à la fin,
//      avec l'état COURANT du formulaire (pas celui du clic manqué) ;
//   2. un compteur de séquence : toute réponse qui n'est pas celle de la
//      dernière requête émise est jetée sans être appliquée ;
//   3. `advance()` attend le silence complet avant de poster son propre état,
//      pour que ce soit bien lui qui écrive la session en dernier.
export default class extends Controller {
  static targets = ["form"]
  static values  = { url: String, nextUrl: String }

  connect() {
    this.pending  = null  // promesse de la requête de devis en vol, sinon null
    this.dirty    = false // le formulaire a bougé pendant qu'une requête volait
    this.sequence = 0     // numéro de la dernière requête ÉMISE
  }

  // Le devis se recalcule TOUJOURS contre `urlValue`, jamais contre l'action du
  // formulaire : les deux coïncident ici, mais le fallback noscript doit
  // continuer de mener où il mène. On applique nous-mêmes le Turbo Stream reçu.
  refresh() {
    if (!this.hasFormTarget) return

    if (this.pending) {
      this.dirty = true
      return
    }
    this.sendQuote()
  }

  sendQuote() {
    const seq = ++this.sequence

    this.pending = fetch(this.urlValue, {
      method: "POST",
      body: new FormData(this.formTarget),
      headers: {
        "X-CSRF-Token": this.csrfToken,
        "Accept": "text/vnd.turbo-stream.html"
      }
    })
      .then(response => response.text())
      .then(html => {
        // Réponse dépassée : une requête plus récente est partie depuis, et
        // c'est elle qui dit la vérité. L'appliquer ferait reculer l'affichage.
        if (seq !== this.sequence) return
        if (html.trim() && window.Turbo) window.Turbo.renderStreamMessage(html)
      })
      .catch(() => {})
      .finally(() => {
        this.pending = null
        if (this.dirty) {
          this.dirty = false
          this.sendQuote()
        }
      })

    return this.pending
  }

  // Attend qu'il n'y ait plus rien en vol NI en attente. Une seule attente ne
  // suffit pas : la requête en vol peut en déclencher une autre en se
  // terminant, quand le formulaire a bougé entretemps.
  async settled() {
    while (this.pending) {
      await this.pending
    }
  }

  // Sauvegarde le draft via le endpoint de devis (même token CSRF que le
  // formulaire) puis navigue vers l'étape suivante — les coordonnées. Évite le
  // problème per-form CSRF token que poserait un formaction vers un autre
  // endpoint.
  //
  // On attend d'abord le silence : sans ça, le POST de sortie pouvait être
  // écrasé par une réponse de devis encore en vol, et la demande partait avec
  // l'avant-dernier état de la composition.
  async advance(event) {
    event.preventDefault()

    if (!this.hasFormTarget) {
      window.location.href = this.nextUrlValue
      return
    }

    try {
      await this.settled()
      // Plus rien à rattraper, et toute réponse retardataire devient obsolète.
      this.dirty = false
      this.sequence++

      await fetch(this.formTarget.action, {
        method: "POST",
        body: new FormData(this.formTarget),
        headers: { "X-CSRF-Token": this.csrfToken }
      })
    } catch {
      // Un réseau qui lâche ne doit pas bloquer le visiteur sur l'étape 2 : le
      // serveur revalide de toute façon la composition à l'étape suivante.
    }

    window.location.href = this.nextUrlValue
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
