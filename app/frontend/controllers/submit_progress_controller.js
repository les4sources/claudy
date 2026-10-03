import { Controller } from "@hotwired/stimulus"

// Retour visuel pendant l'enregistrement d'un formulaire avec photos (fiches de
// la carte). En 5G, téléverser une photo prend du temps : sans signe de vie, on
// reclique sur « Enregistrer ». Dès l'envoi, le bouton se désactive, montre un
// spinner, puis la progression des photos (« Envoi des photos… 42 % ») et enfin
// « Enregistrement… » pendant que le serveur répond.
//
// Les photos partent en direct upload (@rails/activestorage) : un premier
// `submit` est intercepté pour téléverser, puis Active Storage reclique
// lui-même sur le bouton (même désactivé) pour la vraie soumission Turbo.
//
// Usage (Slim), sur le <form> :
//   data: { controller: "submit-progress",
//           action: "submit->submit-progress#start direct-upload:initialize->submit-progress#track
//                    direct-upload:progress->submit-progress#progress direct-uploads:end->submit-progress#uploaded
//                    direct-upload:error->submit-progress#reset turbo:submit-end->submit-progress#finish" }
// et le bouton `maps/save_button` (cibles button, spinner, label).
export default class extends Controller {
  static targets = ["button", "spinner", "label"]
  static values = {
    savingLabel: { type: String, default: "Enregistrement…" },
    uploadingLabel: { type: String, default: "Envoi des photos…" }
  }

  connect() {
    this.busy = false
    this.uploadsDone = false
    this.uploads = new Map()
  }

  start(event) {
    if (this.busy) return
    // Annulé par un autre écouteur que le téléversement d'Active Storage : rien
    // ne partira, le bouton doit rester disponible.
    const uploading = this.element.hasAttribute("data-direct-uploads-processing")
    if (event.defaultPrevented && !uploading) return

    this.busy = true
    this.idleLabel = this.labelTarget.textContent
    this.buttonTarget.disabled = true
    this.buttonTarget.setAttribute("aria-busy", "true")
    this.spinnerTarget.classList.remove("hidden")
    if (uploading) {
      this.showUploadProgress()
    } else {
      this.labelTarget.textContent = this.savingLabelValue
    }
  }

  track(event) {
    const { id, file } = event.detail
    this.uploads.set(id, { size: file.size || 1, progress: 0 })
  }

  progress(event) {
    // Le navigateur peut encore signaler un « progress » tardif une fois les
    // photos parties : on ne revient pas en arrière.
    if (!this.busy || this.uploadsDone) return
    const upload = this.uploads.get(event.detail.id)
    if (upload) upload.progress = Math.max(upload.progress, event.detail.progress)
    this.showUploadProgress()
  }

  showUploadProgress() {
    let total = 0
    let sent = 0
    this.uploads.forEach(({ size, progress }) => {
      total += size
      sent += size * progress / 100
    })
    const percent = total ? Math.min(100, Math.round(sent / total * 100)) : 0
    this.labelTarget.textContent = `${this.uploadingLabelValue} ${percent}\u00a0%`
  }

  // Photos téléversées : reste la réponse du serveur.
  uploaded() {
    if (!this.busy) return
    this.uploadsDone = true
    this.labelTarget.textContent = this.savingLabelValue
  }

  // Turbo réactive le bouton à la fin de la requête. En cas de succès, la fiche
  // est remplacée dans la foulée : on garde le bouton bloqué jusque-là. En cas
  // d'échec (erreur réseau…), on le rend.
  finish(event) {
    if (event.detail.success) {
      this.buttonTarget.disabled = true
    } else {
      this.reset()
    }
  }

  reset() {
    if (!this.busy) return
    this.busy = false
    this.uploadsDone = false
    this.uploads.clear()
    this.buttonTarget.disabled = false
    this.buttonTarget.removeAttribute("aria-busy")
    this.spinnerTarget.classList.add("hidden")
    this.labelTarget.textContent = this.idleLabel
  }
}
